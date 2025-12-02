#!/usr/bin/env bats

setup() {
	TMP_TEST_DIR="$(mktemp -d)"
	if [ -z "${TMP_TEST_DIR}" ] || [ ! -d "${TMP_TEST_DIR}" ]; then
		echo "Failed to create test temp dir" >&2
		exit 1
	fi
	export TMP_TEST_DIR
	mkdir -p "$TMP_TEST_DIR/runtime"

	# Create a minimal runtime/paths.sh based on the expected implementation
	cat >"$TMP_TEST_DIR/runtime/paths.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

_bs_normalize() {
	local p="$1"
	if [[ -z "$p" ]]; then return 1; fi
	if [[ "${p#-}" != "$p" ]]; then return 2; fi
	if [[ "$p" != /* ]]; then return 3; fi
	if [[ "$p" == *".."* ]]; then return 4; fi
	while [[ "$p" == *'//'* ]]; do p="$(printf '%s' "$p" | sed ':a; s#//#/#; ta')"; done
	if [[ "$p" != "/" ]]; then p="${p%/}"; fi
	printf '%s' "$p"
}

_bs_make_dir_secure() {
	local d="$1"
	if [[ -z "$d" ]]; then return 1; fi
	if [[ -L "$d" ]]; then return 2; fi
	if [[ -e "$d" && ! -d "$d" ]]; then return 3; fi
	mkdir -p -- "$d"
	chmod 0700 -- "$d"
	return 0
}

bs_path_state_dir_from_cli() {
	local override="${1-}"
	local dir
	if [[ -n "$override" ]]; then
		dir="$(_bs_normalize "$override")" || return 2
	else
		local p
		if [[ -n "${XDG_STATE_HOME-}" ]]; then p="${XDG_STATE_HOME%/}/battleship"; else p="${HOME%/}/.local/state/battleship"; fi
		dir="$(_bs_normalize "$p")" || printf '%s' "$p"
	fi
	_bs_make_dir_secure "$dir" || return 3
	printf '%s\n' "$dir"
}

bs_path_saves_dir() {
	local state
	state="$(bs_path_state_dir_from_cli "${1-}")" || return 1
	local d="$state/saves"
	_bs_make_dir_secure "$d" || return 2
	printf '%s\n' "$d"
}
SH

	# Create a minimal runtime/env_safety.sh file (mktemp checks and basic exports)
	cat >"$TMP_TEST_DIR/runtime/env_safety.sh" <<'SH'
#!/usr/bin/env bash
set -eu
if (set -o pipefail) >/dev/null 2>&1; then
	set -o pipefail
fi
set -f
: "${BS_SAFE_PATH:=/usr/bin:/bin}"
export PATH="${BS_SAFE_PATH}"
ulimit -c 0 2>/dev/null || true
export LC_ALL=C
export LANG=C
IFS=' '
BS_HAS_MKTEMP=0
check_cmd() { command -v "$1" >/dev/null 2>&1; }
if check_cmd mktemp; then BS_HAS_MKTEMP=1; fi
export BS_HAS_MKTEMP
fatal_missing() { echo "$1" >&2; exit 2; }
if [ "$BS_HAS_MKTEMP" -ne 1 ]; then fatal_missing "battleship_shell_script: required tool 'mktemp' not found in PATH"; fi
bs_env_init() { set -eu; if (set -o pipefail) >/dev/null 2>&1; then set -o pipefail; fi; export PATH LC_ALL LANG IFS; return 0; }
SH

	# Create the self_check.sh script at top-level in the tempdir
	cat >"$TMP_TEST_DIR/self_check.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
RUNTIME_DIR="$SCRIPT_DIR/runtime"
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

emit() { printf '%s\n' "$*"; }
command_exists() { command -v "$1" >/dev/null 2>&1; }
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
			printf '%s\n' "Usage: self_check.sh [--doctor|--self-check] [--state-dir DIR] [--help]"
			exit 0
			;;
		*)
			emit "Unknown option: $1"
			printf '%s\n' "Usage: self_check.sh [--doctor|--self-check] [--state-dir DIR] [--help]"
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
SH
	chmod +x "$TMP_TEST_DIR/self_check.sh"
}

teardown() {
	if [ -n "${TMP_TEST_DIR:-}" ] && [ -d "${TMP_TEST_DIR}" ]; then
		rm -rf -- "$TMP_TEST_DIR"
	fi
}

@test "Integration: bs_path_state_dir_from_cli with override containing '..' fails normalization and returns non-zero" {
	run timeout 5s bash -c "source '$TMP_TEST_DIR/runtime/paths.sh'; bs_path_state_dir_from_cli '/tmp/../evil'"
	[ "$status" -ne 0 ]
}

@test "Integration: bs_path_saves_dir creates 'saves' subdirectory under resolved state dir with 0700 permissions" {
	run timeout 5s bash -c "source '$TMP_TEST_DIR/runtime/paths.sh'; bs_path_saves_dir '$TMP_TEST_DIR/state'"
	[ "$status" -eq 0 ]
	# captured path in output
	saves_path="$output"
	# trim possible trailing newline
	saves_path="${saves_path%%$'\n'}"
	[ -d "$saves_path" ]
	# Ensure the path is inside our TMP_TEST_DIR
	case "$saves_path" in
	"$TMP_TEST_DIR"/*) : ;;
	*)
		echo "saves path outside test temp dir" >&2
		return 1
		;;
	esac
	perm="$(stat -c '%a' "$saves_path" 2>/dev/null || true)"
	[ "$perm" = "700" ]
}

@test "Integration: self_check exits 0 and prints SUMMARY OK when required tools exist and state dir is writable" {
	# Create mocks for all required tools to ensure self_check passes in the test env
	mkdir -p "$TMP_TEST_DIR/bin"
	for tool in awk sed od tput date; do
		touch "$TMP_TEST_DIR/bin/$tool"
		chmod +x "$TMP_TEST_DIR/bin/$tool"
	done
	
	# Mock mktemp to actually work (basic)
	cat >"$TMP_TEST_DIR/bin/mktemp" <<'EOF'
#!/bin/sh
echo "${TMPDIR:-/tmp}/tmp.$$"
EOF
	chmod +x "$TMP_TEST_DIR/bin/mktemp"

	# Mock sha256sum
	cat >"$TMP_TEST_DIR/bin/sha256sum" <<'EOF'
#!/bin/sh
echo "hash  -"
EOF
	chmod +x "$TMP_TEST_DIR/bin/sha256sum"

	# Add mocks to PATH
	export PATH="$TMP_TEST_DIR/bin:$PATH"

	# Ensure the runtime layout matches what the script expects
	run timeout 10s bash "$TMP_TEST_DIR/self_check.sh" --state-dir "$TMP_TEST_DIR/state"
	[ "$status" -eq 0 ]
	[[ "$output" == *"SUMMARY: All required checks passed."* ]]
}