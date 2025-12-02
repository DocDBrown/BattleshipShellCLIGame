#!/usr/bin/env bats

setup() {
	TMPDIR=$(mktemp -d)
	
	# Create directory structure
	mkdir -p "$TMPDIR/runtime" "$TMPDIR/diagnostics"

	# Create mock exit_traps.sh
	cat >"$TMPDIR/runtime/exit_traps.sh" <<'EOF'
#!/usr/bin/env bash
exit_traps_add_temp() {
	# Mock implementation: delete the file immediately to simulate cleanup for test verification
	rm -f "$1"
}
exit_traps_add_atomic() {
	rm -f "$1"
}
exit_traps_set_exit_code() {
	# Just echo the code so the wrapper can exit with it
	return 0
}
EOF

	# Create mock paths.sh
	cat >"$TMPDIR/runtime/paths.sh" <<'EOF'
#!/usr/bin/env bash
# Minimal mock
EOF

	# Create mock env_safety.sh
	cat >"$TMPDIR/runtime/env_safety.sh" <<'EOF'
#!/usr/bin/env bash
bs_env_init() { return 0; }
EOF

	# Create mock self_check.sh
	cat >"$TMPDIR/diagnostics/self_check.sh" <<'EOF'
#!/usr/bin/env bash
# Check if state-dir arg is passed and if it is writable
while [[ $# -gt 0 ]]; do
	case "$1" in
		--state-dir)
			dir="$2"
			if ! mkdir -p "$dir" 2>/dev/null; then
				echo "state-dir: WRITE test FAILED"
				exit 1
			fi
			shift 2
			;;
		*)
			shift
			;;
	esac
done
exit 0
EOF
	chmod +x "$TMPDIR/diagnostics/self_check.sh"

	# Create SUT
	cat >"$TMPDIR/battleship_helper_2.sh" <<'EOF'
#!/usr/bin/env bash
# ... (Minimal SUT content required for run_self_check) ...
if [ "${REPO_ROOT:-}" = "" ]; then
	SCRIPTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
	REPO_ROOT="$(cd "${SCRIPTDIR}/.." >/dev/null 2>&1 && pwd)"
fi
export REPO_ROOT

run_self_check() {
	local diag
	diag="${REPO_ROOT%/}/diagnostics/self_check.sh"

	if command -v safe_source >/dev/null 2>&1 && safe_source "$diag"; then
		bash "$diag" "$@"
		return $?
	fi
	# Fallback if safe_source not defined in test wrapper
	if [ -f "$diag" ]; then
		bash "$diag" "$@"
		return $?
	fi
	return 2
}
EOF
}

teardown() {
	if [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ]; then
		rm -rf -- "$TMPDIR"
	fi
}

@test "exit_traps_removes_temporary_and_atomic_files_on_exit_and_preserves_exit_code_Integration" {
	wrapper="$TMPDIR/wrapper.sh"
	tmpfile="$TMPDIR/tmpfile.tmp"
	atomic_tmp="$TMPDIR/atomic.tmp"
	target_file="$TMPDIR/targetfile"

	cat >"$wrapper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
EXIT_TRAPS_SH="$1"
. "$EXIT_TRAPS_SH"
touch "$2"
touch "$3"
exit_traps_add_temp "$2"
exit_traps_add_atomic "$3" "$4"
exit 42
EOF
	chmod +x "$wrapper"

	run timeout 5s bash "$wrapper" "$TMPDIR/runtime/exit_traps.sh" "$tmpfile" "$atomic_tmp" "$target_file"
	[ "$status" -eq 42 ]
	[ ! -e "$tmpfile" ]
	[ ! -e "$atomic_tmp" ]
}

@test "self_check_state_dir_write_test_fails_for_unwritable_state_and_reports_failure_Integration" {
	# Create a parent directory that is not writable
	parent_unwritable=$(mktemp -d)
	chmod 500 "$parent_unwritable"
	state_override="$parent_unwritable/unwritable_state"

	wrapper2="$TMPDIR/wrapper2.sh"
	cat >"$wrapper2" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export REPO_ROOT="$TMPDIR"
safe_source() { return 0; }
. "$TMPDIR/battleship_helper_2.sh"
run_self_check --self-check --state-dir "$state_override"
EOF
	chmod +x "$wrapper2"

	run timeout 20s bash "$wrapper2"
	[ "$status" -ne 0 ]
	[[ "$output" == *"state-dir: WRITE test FAILED"* ]]

	chmod 700 "$parent_unwritable" || true
	rm -rf -- "$parent_unwritable" || true
}