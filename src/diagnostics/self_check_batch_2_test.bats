#!/usr/bin/env bats

setup() {
	TMPDIR="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp.XXXXXX")"
	if [[ -z "${TMPDIR}" ]]; then
		fail "failed to create temp dir"
	fi
}

teardown() {
	if [[ -n "${TMPDIR}" && "${TMPDIR}" == "${BATS_TEST_DIRNAME}/"* ]]; then
		rm -rf -- "${TMPDIR}"
	fi
}

@test "Unit__bs_path_state_dir_from_cli_uses_provided_argument" {
	run timeout 5s bash -c "source \"${BATS_TEST_DIRNAME}/../runtime/paths.sh\"; bs_path_state_dir_from_cli \"$TMPDIR/custom\""
	[ "$status" -eq 0 ]
	[ "$output" = "$TMPDIR/custom" ]
}

@test "Unit__bs_path_state_dir_from_cli_defaults_to_home_dir_when_no_arg" {
	# Mock HOME to control the output
	export HOME="$TMPDIR/fake_home"
	mkdir -p "$HOME"

	run timeout 5s bash -c "source \"${BATS_TEST_DIRNAME}/../runtime/paths.sh\"; bs_path_state_dir_from_cli"
	[ "$status" -eq 0 ]

	# Verify it starts with HOME
	[[ "$output" == "$HOME/"* ]]
	# Verify it contains 'battleship' (flexible match to avoid brittleness on exact folder name)
	[[ "$output" == *"battleship"* ]]
}

@test "Unit__bs_path_state_dir_from_cli_fails_if_home_unset_and_no_arg" {
	run timeout 5s bash -c "unset HOME; source \"${BATS_TEST_DIRNAME}/../runtime/paths.sh\"; bs_path_state_dir_from_cli"
	[ "$status" -ne 0 ]
}
