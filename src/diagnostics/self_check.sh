#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
RUNTIME_DIR="$SCRIPT_DIR/../runtime"
PATHS_SH="$RUNTIME_DIR/paths.sh"
ENV_SAFETY_SH="$RUNTIME_DIR/env_safety.sh"

if [[ -f "$ENV_SAFETY_SH" ]]; then
	# shellcheck source=/dev/null
	source "$ENV_SAFETY_SH"
fi

if [[ -f "$PATHS_SH" ]]; then
	# shellcheck source=/dev/null
	source "$PATHS_SH"
else
	echo "warning: runtime/paths.sh not found; state dir checks will be limited" >&2
fi

print_usage() {
	cat <<'USAGE'
Usage: self_check.sh [--doctor|--self-check] [--state-dir DIR] [--help]
Performs environment checks for battleship_shell_script.
USAGE
}

emit() { printf '%s\n' "$*"; }

command_exists() {
	command -v "$1" >/dev/null 2>&1
}

get_version() {
	local cmd="$1"
	local out
	if out="$("$cmd" --version 2>&1)"; then
		printf '%s' "$(printf '%s' "$out" | head -n1)"
		return 0
	fi
	if out="$("$cmd" -V 2>&1)"; then
		printf '%s' "$(printf '%s' "$out" | head -n1)"
		return 0
	fi
	if out="$("$cmd" -v 2>&1)"; then
		printf '%s' "$(printf '%s' "$out" | head -n1)"
		return 0
	fi
	return 1
}

check_tool() {
	local label="$1"
	shift
	local cmds=("$@")
	for c in "${cmds[@]}"; do
		if command_exists "$c"; then
			local ver
			if ver="$(get_version "$c" 2>/dev/null)"; then
				emit "$label: OK ($c) - ${ver}"
			else
				emit "$label: OK ($c) - version unknown"
			fi
			return 0
		fi
	done
	emit "$label: MISSING"
	return 1
}

check_sha_tool() {
	if command_exists sha256sum; then
		local ver
		if ver="$(get_version sha256sum 2>/dev/null)"; then
			emit "sha256: OK (sha256sum) - ${ver}"
		else
			emit "sha256: OK (sha256sum) - version unknown"
		fi
		return 0
	fi
	if command_exists shasum; then
		emit "sha256: OK (shasum) - supports -a 256"
		return 0
	fi
	emit "sha256: MISSING (sha256sum or shasum)"
	return 1
}

check_network_optional() {
	if command_exists nc || command_exists ncat; then
		emit "network: OK (nc/ncat available)"
		return 0
	fi
	emit "network: OPTIONAL (no nc/ncat found; /dev/tcp support not probed)"
	return 2
}

check_state_dir() {
	local override="${1-}"
	local state
	set +e
	if [[ -n "${override}" ]]; then
		state="$(bs_path_state_dir_from_cli "$override" 2>/dev/null || true)"
	else
		state="$(bs_path_state_dir_from_cli 2>/dev/null || true)"
	fi
	set -e
	if [[ -z "${state}" ]]; then
		emit "state-dir: FAILED to resolve state directory (paths.sh may be missing or returned error)"
		return 2
	fi
	emit "state-dir: RESOLVED to ${state}"
	# test writeability
	local tmp=""
	set +e
	if command_exists mktemp; then
		tmp="$(mktemp "${state}/.bself.XXXX" 2>/dev/null || true)"
	else
		tmp="${state}/.bself.$$"
		touch "$tmp" 2>/dev/null || tmp=""
	fi
	set -e
	if [[ -n "${tmp}" && -e "${tmp}" ]]; then
		emit "state-dir: WRITE test succeeded (created temp file)"
		rm -f -- "$tmp" || true
	else
		emit "state-dir: WRITE test FAILED (cannot create files in ${state}). Check permissions."
		return 2
	fi
	# disk space heuristic
	if command_exists df; then
		local avail
		avail="$(df -P "$state" 2>/dev/null | tail -n1 | tr -s ' ' | cut -d' ' -f4 || true)"
		if [[ -n "$avail" ]]; then
			emit "state-dir: AVAILABLE_SPACE_KB=${avail}"
			if [[ "$avail" -lt 1024 ]]; then
				emit "state-dir: WARN available space low (<1MB)"
			fi
		else
			emit "state-dir: AVAILABLE_SPACE unknown (df failed)"
		fi
	else
		emit "state-dir: AVAILABLE_SPACE unknown (df not found)"
	fi
	return 0
}

main() {
	local mode="self-check"
	local override=""
	while [[ "${#}" -gt 0 ]]; do
		case "$1" in
		--doctor | --self-check)
			mode="$1"
			shift
			;;
		--state-dir)
			override="$2"
			shift 2
			;;
		--state-dir=*)
			override="${1#*=}"
			shift
			;;
		-h | --help)
			print_usage
			exit 0
			;;
		*)
			emit "Unknown option: $1"
			print_usage
			exit 2
			;;
		esac
	done

	emit "Self-check mode: ${mode}"
	local failed=0
	check_tool "awk" awk gawk mawk || failed=1
	check_tool "sed" sed gsed || failed=1
	check_tool "od" od || failed=1
	check_tool "mktemp" mktemp || failed=1
	check_tool "tput" tput || failed=1
	check_sha_tool || failed=1
	check_tool "date" date || failed=1
	check_network_optional || true
	check_state_dir "$override" || failed=1

	if [[ "$failed" -ne 0 ]]; then
		emit "SUMMARY: ISSUES detected. See lines above for remediation hints."
		exit 2
	fi
	emit "SUMMARY: All required checks passed."
	exit 0
}

main "$@"
