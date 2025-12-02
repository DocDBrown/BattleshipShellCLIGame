#!/usr/bin/env bats

setup() {
	TMPTESTDIR="$(mktemp -d)"
}

teardown() {
	if [ -n "${TMPTESTDIR:-}" ] && [ "${TMPTESTDIR}" != "/" ] && [[ "${TMPTESTDIR}" = /* ]]; then
		rm -rf -- "${TMPTESTDIR}"
	fi
}

@test "Integration_paths_bs_path_log_file_returns_log_path_and_creates_parent_logs_dir" {
	cat >"${TMPTESTDIR}/paths.sh" <<'SH'
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

_bs_default_state_dir() {
	local p
	if [[ -n "${XDG_STATE_HOME-}" ]]; then p="${XDG_STATE_HOME%/}/battleship"; else p="${HOME%/}/.local/state/battleship"; fi
	_bs_normalize "$p" || printf '%s' "$p"
}

bs_path_state_dir_from_cli() {
	local override="${1-}"
	local dir
	if [[ -n "$override" ]]; then
		dir="$(_bs_normalize "$override")" || return 2
	else
		dir="$(_bs_default_state_dir)"
	fi
	_bs_make_dir_secure "$dir" || return 3
	printf '%s\n' "$dir"
}

bs_path_log_file() {
	local state
	state="$(bs_path_state_dir_from_cli "${1-}" )" || return 1
	local d="$state/logs"
	_bs_make_dir_secure "$d" || return 2
	printf '%s\n' "$d/battleship.log"
}
SH

	run timeout 5s bash -c "source \"${TMPTESTDIR}/paths.sh\" && bs_path_log_file \"${TMPTESTDIR}/state\""
	[ "$status" -eq 0 ]
	[ "$output" = "${TMPTESTDIR}/state/logs/battleship.log" ]
	[ -d "${TMPTESTDIR}/state/logs" ]
}

@test "Integration_paths_bs_path_config_and_cache_dir_default_and_override_behavior" {
	cat >"${TMPTESTDIR}/paths.sh" <<'SH'
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

_bs_default_config_dir() {
	local p
	if [[ -n "${XDG_CONFIG_HOME-}" ]]; then p="${XDG_CONFIG_HOME%/}/battleship"; else p="${HOME%/}/.config/battleship"; fi
	_bs_normalize "$p" || printf '%s' "$p"
}

_bs_default_cache_dir() {
	local p
	if [[ -n "${XDG_CACHE_HOME-}" ]]; then p="${XDG_CACHE_HOME%/}/battleship"; else p="${HOME%/}/.cache/battleship"; fi
	_bs_normalize "$p" || printf '%s' "$p"
}

bs_path_config_dir_from_cli() {
	local override="${1-}"
	local dir
	if [[ -n "$override" ]]; then
		dir="$(_bs_normalize "$override")" || return 2
	else
		dir="$(_bs_default_config_dir)"
	fi
	_bs_make_dir_secure "$dir" || return 3
	printf '%s\n' "$dir"
}

bs_path_cache_dir_from_cli() {
	local override="${1-}"
	local dir
	if [[ -n "$override" ]]; then
		dir="$(_bs_normalize "$override")" || return 2
	else
		dir="$(_bs_default_cache_dir)"
	fi
	_bs_make_dir_secure "$dir" || return 3
	printf '%s\n' "$dir"
}
SH

	XDG_CONFIG_HOME="${TMPTESTDIR}/xdg_config"
	XDG_CACHE_HOME="${TMPTESTDIR}/xdg_cache"

	run timeout 5s bash -c "export XDG_CONFIG_HOME='${XDG_CONFIG_HOME}'; export XDG_CACHE_HOME='${XDG_CACHE_HOME}'; source '${TMPTESTDIR}/paths.sh' && bs_path_config_dir_from_cli && bs_path_cache_dir_from_cli"
	[ "$status" -eq 0 ]
	[[ "$output" = *"${XDG_CONFIG_HOME}/battleship"* ]]
	[[ "$output" = *"${XDG_CACHE_HOME}/battleship"* ]]

	run timeout 5s bash -c "source '${TMPTESTDIR}/paths.sh' && bs_path_config_dir_from_cli '${TMPTESTDIR}/override_conf'"
	[ "$status" -eq 0 ]
	[ "$output" = "${TMPTESTDIR}/override_conf" ]
	[ -d "${TMPTESTDIR}/override_conf" ]
}

@test "Integration_self_check_check_state_dir_detects_unwritable_state_dir_and_returns_failure" {
	# place self_check.sh and runtime/paths.sh in test temp dir layout to match expectations
	mkdir -p "${TMPTESTDIR}/runtime"

	cat >"${TMPTESTDIR}/runtime/paths.sh" <<'SH'
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

_bs_default_state_dir() {
	local p
	if [[ -n "${XDG_STATE_HOME-}" ]]; then p="${XDG_STATE_HOME%/}/battleship"; else p="${HOME%/}/.local/state/battleship"; fi
	_bs_normalize "$p" || printf '%s' "$p"
}

bs_path_state_dir_from_cli() {
	local override="${1-}"
	local dir
	if [[ -n "$override" ]]; then
		dir="$(_bs_normalize "$override")" || return 2
	else
		dir="$(_bs_default_state_dir)"
	fi
	_bs_make_dir_secure "$dir" || return 3
	printf '%s\n' "$dir"
}
SH

	cat >"${TMPTESTDIR}/self_check.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
RUNTIME_DIR="$SCRIPT_DIR/../runtime"
PATHS_SH="$RUNTIME_DIR/paths.sh"

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
	if command -v mktemp; then
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
	check_state_dir "$override" || exit 2
	exit 0
}

main "$@"
SH

	readonly_parent="${TMPTESTDIR}/readonly_parent"
	mkdir -p "${readonly_parent}"
	chmod 0500 "${readonly_parent}"
	override_path="${readonly_parent}/substate"

	run timeout 5s bash "${TMPTESTDIR}/self_check.sh" --self-check --state-dir "${override_path}"
	# Expect failure to resolve due to inability to create the state dir under a non-writable parent
	[ "$status" -ne 0 ]
	[[ "$output" = *"state-dir: FAILED to resolve state directory"* || "$output" = *"state-dir: WRITE test FAILED"* ]]
}