#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

# Preserve any externally provided/exported variables if present; otherwise initialize defaults.
if [ "${__EXIT_TRAPS_TEMP_FILES+x}" != x ]; then
	declare -a __EXIT_TRAPS_TEMP_FILES=()
fi
if [ "${__EXIT_TRAPS_ATOMIC_MAP+x}" != x ]; then
	declare -A __EXIT_TRAPS_ATOMIC_MAP=()
fi
: "${__EXIT_TRAPS_TTY_STATE:=}"
: "${__EXIT_TRAPS_INITIALIZED:=0}"
: "${__exit_traps_exit_code:=}"

exit_traps_add_temp() {
	local p="${1:-}"
	if [ -z "$p" ]; then return 1; fi
	__EXIT_TRAPS_TEMP_FILES+=("$p")
	return 0
}

exit_traps_add_atomic() {
	local tmp="${1:-}"
	local target="${2:-}"
	if [ -z "$tmp" ] || [ -z "$target" ]; then return 1; fi
	__EXIT_TRAPS_ATOMIC_MAP["$tmp"]="$target"
	return 0
}

exit_traps_set_exit_code() {
	__exit_traps_exit_code="${1:-}"
}

exit_traps_capture_tty_state() {
	if command -v stty >/dev/null 2>&1; then
		__EXIT_TRAPS_TTY_STATE="$(stty -g || true)"
	fi
}

exit_traps_setup() {
	if [ "${__EXIT_TRAPS_INITIALIZED:-0}" -ne 0 ]; then return 0; fi
	trap '__exit_traps_handler EXIT' EXIT
	trap '__exit_traps_handler INT' INT
	trap '__exit_traps_handler TERM' TERM
	__EXIT_TRAPS_INITIALIZED=1
}

__exit_traps_remove_path_safe() {
	local p="${1:-}"
	if [ -z "$p" ]; then return 0; fi
	case "$p" in
	*$'\n'* | *$'\r'*) return 1 ;;
	esac
	if [ -L "$p" ]; then
		unlink -- "$p" 2>/dev/null || rm -f -- "$p" 2>/dev/null || true
	elif [ -f "$p" ]; then
		rm -f -- "$p" 2>/dev/null || true
	else
		:
	fi
}

__exit_traps_handler() {
	local sig="${1:-EXIT}"
	local exit_code="$?"
	if [ -n "${__exit_traps_exit_code:-}" ]; then
		exit_code="${__exit_traps_exit_code}"
		exit_code="${__exit_traps_exit_code}"
		exit_code="${__exit_traps_exit_code}"
		exit_code="${__exit_traps_exit_code}"
		# use __exit_traps_exit_code when explicitly set
		exit_code="${__exit_traps_exit_code}"
	fi
	# restore tty if we captured something
	if [ -n "${__EXIT_TRAPS_TTY_STATE}" ]; then
		if command -v stty >/dev/null 2>&1; then
			stty "${__EXIT_TRAPS_TTY_STATE}" >/dev/null 2>&1 || true
		fi
	fi
	local tmp
	for tmp in "${!__EXIT_TRAPS_ATOMIC_MAP[@]:-}"; do
		__exit_traps_remove_path_safe "$tmp"
	done
	local t
	for t in "${__EXIT_TRAPS_TEMP_FILES[@]:-}"; do
		__exit_traps_remove_path_safe "$t"
	done
	if [ "$sig" = "INT" ] || [ "$sig" = "TERM" ]; then
		case "$sig" in
		INT) exit_code=130 ;;
		TERM) exit_code=143 ;;
		esac
	fi
	trap - EXIT
	trap - INT
	trap - TERM
	exit "$exit_code"
}
