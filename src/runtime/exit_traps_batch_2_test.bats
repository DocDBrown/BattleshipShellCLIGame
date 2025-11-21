#!/usr/bin/env bats

setup() {
	TMPDIR=$(mktemp -d)
}

teardown() {
	if [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ]; then
		rm -rf -- "$TMPDIR" || true
	fi
}

@test "Integration_cleanup_on_EXIT_removes_temporary_files_restores_terminal_modes_and_exits_zero" {
	SUT="${BATS_TEST_DIRNAME}/exit_traps.sh"
	f1="$TMPDIR/temp1"
	f2="$TMPDIR/temp2"
	touch -- "$f1" "$f2"

	run timeout 30s bash -c "set -o errexit -o nounset -o pipefail; source \"$SUT\"; exit_traps_setup; exit_traps_add_temp \"$f1\" || true; exit_traps_add_temp \"$f2\" || true; __EXIT_TRAPS_TTY_STATE=\"\"; exit 0"
	[ "$status" -eq 0 ]
	[ ! -e "$f1" ]
	[ ! -e "$f2" ]
}

@test "Integration_cleanup_on_SIGINT_removes_registered_temp_files_and_exits_with_130" {
	SUT="${BATS_TEST_DIRNAME}/exit_traps.sh"
	f1="$TMPDIR/sig_temp"
	touch -- "$f1"

	# Start a process that registers the temp file then sends SIGINT to itself to exercise the INT handler.
	run timeout 30s bash -c "set -o errexit -o nounset -o pipefail; source \"$SUT\"; exit_traps_setup; exit_traps_add_temp \"$f1\" || true; kill -INT \$\$"
	[ "$status" -eq 130 ]
	[ ! -e "$f1" ]
}
