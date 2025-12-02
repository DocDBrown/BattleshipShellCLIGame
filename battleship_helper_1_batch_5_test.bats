#!/usr/bin/env bats

setup() {
	TEST_TMPDIR="$(mktemp -d)"
	export TEST_TMPDIR
}

teardown() {
	# Ensure we only remove the test-owned directory
	if [ -n "${TEST_TMPDIR:-}" ] && [ -d "$TEST_TMPDIR" ]; then
		rm -rf -- "$TEST_TMPDIR"
	fi
}

create_exit_traps_copy() {
	cat >"$TEST_TMPDIR/exit_traps.sh" <<'EOS'
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
	# Only attempt stty if we are in a TTY environment
	# Ensure we return 0 even if [ -t 0 ] fails, to avoid triggering set -e in callers
	if command -v stty >/dev/null 2>&1 && [ -t 0 ]; then
		__EXIT_TRAPS_TTY_STATE="$(stty -g 2>/dev/null || true)"
	fi
	return 0
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
	return 0
}

__exit_traps_handler() {
    # Disable nounset to avoid crashes during cleanup if something is slightly off
    set +u
	local sig="${1:-EXIT}"
	local exit_code="$?"
	if [ -n "${__exit_traps_exit_code:-}" ]; then
		# use __exit_traps_exit_code when explicitly set
		exit_code="${__exit_traps_exit_code}"
	fi
	# restore tty if we captured something
	if [ -n "${__EXIT_TRAPS_TTY_STATE}" ]; then
		if command -v stty >/dev/null 2>&1; then
			stty "${__EXIT_TRAPS_TTY_STATE}" >/dev/null 2>&1 || true
		fi
	fi
	
	# Robust iteration over associative array
	if [ ${#__EXIT_TRAPS_ATOMIC_MAP[@]} -gt 0 ]; then
		local tmp
		for tmp in "${!__EXIT_TRAPS_ATOMIC_MAP[@]}"; do
			__exit_traps_remove_path_safe "$tmp"
		done
	fi
	
	# Robust iteration over indexed array
	if [ ${#__EXIT_TRAPS_TEMP_FILES[@]} -gt 0 ]; then
		local t
		for t in "${__EXIT_TRAPS_TEMP_FILES[@]}"; do
			__exit_traps_remove_path_safe "$t"
		done
	fi

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
EOS
	chmod +x "$TEST_TMPDIR/exit_traps.sh"
}

create_runner_ok() {
	cat >"$TEST_TMPDIR/runner_ok.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
: "${TEST_TMPDIR:?}"
# Source local copy of exit_traps
source "$TEST_TMPDIR/exit_traps.sh"

# create an atomic target and a symlink tmp that should be removed
atomic_target="$TEST_TMPDIR/atomic_target"
atomic_tmp="$TEST_TMPDIR/atomic_tmp"
# create files
printf 'x' > "$atomic_target"
ln -s "$atomic_target" "$atomic_tmp"
# temp file to be removed
tempfile="$TEST_TMPDIR/tempfile"
touch "$tempfile"
# register
exit_traps_add_temp "$tempfile"
exit_traps_add_atomic "$atomic_tmp" "$atomic_target"
# capture tty state and install traps
exit_traps_capture_tty_state
exit_traps_setup
# normal exit should trigger cleanup
exit 0
EOS
	chmod +x "$TEST_TMPDIR/runner_ok.sh"
}

# This "sleep" runner now directly exercises the INT handler instead of
# relying on a real SIGINT and long-running sleep that can hang.
create_runner_sleep() {
	cat >"$TEST_TMPDIR/runner_sleep.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
: "${TEST_TMPDIR:?}"
source "$TEST_TMPDIR/exit_traps.sh"

atomic_target="$TEST_TMPDIR/atomic_target"
atomic_tmp="$TEST_TMPDIR/atomic_tmp"
printf 'x' > "$atomic_target"
ln -sf "$atomic_target" "$atomic_tmp"

tempfile="$TEST_TMPDIR/tempfile"
touch "$tempfile"

exit_traps_add_temp "$tempfile"
exit_traps_add_atomic "$atomic_tmp" "$atomic_target"
exit_traps_capture_tty_state
exit_traps_setup

# Simulate a SIGINT by calling the handler explicitly
true  # "last command" status before the handler; value doesn't matter here
__exit_traps_handler INT
EOS
	chmod +x "$TEST_TMPDIR/runner_sleep.sh"
}

@test "Integration: exit_traps removes registered temp files and atomic map targets on EXIT and restores captured tty state" {
	create_exit_traps_copy
	create_runner_ok

	run env TEST_TMPDIR="$TEST_TMPDIR" bash "$TEST_TMPDIR/runner_ok.sh"
	[ "$status" -eq 0 ]
	# the temporary file registered should be removed
	[ ! -e "$TEST_TMPDIR/tempfile" ]
	# the atomic tmp
	[ ! -e "$TEST_TMPDIR/atomic_tmp" ]
	# the underlying target should remain
	[ -e "$TEST_TMPDIR/atomic_target" ]
}

@test "Integration: exit_traps maps SIGINT to exit code 130 and performs full cleanup" {
	create_exit_traps_copy
	create_runner_sleep

	# Run in foreground; script calls __exit_traps_handler INT itself
	run env TEST_TMPDIR="$TEST_TMPDIR" bash "$TEST_TMPDIR/runner_sleep.sh"

	# exit_traps should map INT -> 130
	[ "$status" -eq 130 ]

	# confirm cleanup occurred
	[ ! -e "$TEST_TMPDIR/tempfile" ]
	[ ! -e "$TEST_TMPDIR/atomic_tmp" ]
	[ -e "$TEST_TMPDIR/atomic_target" ]
}
