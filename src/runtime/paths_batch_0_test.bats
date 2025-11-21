#!/usr/bin/env bats

setup() {
	TEST_TMPDIR=$(mktemp -d "${BATS_TEST_DIRNAME}/tmp.XXXXXX")
	HOME_DIR="$TEST_TMPDIR/home"
	mkdir -p "$HOME_DIR"
}

teardown() {
	if [[ -n "$TEST_TMPDIR" && "$TEST_TMPDIR" == "${BATS_TEST_DIRNAME}/"* ]]; then
		rm -rf "$TEST_TMPDIR"
	else
		echo "Refusing to remove unsafe tmpdir: $TEST_TMPDIR" >&2
		return 1
	fi
}

@test "Unit_bs_path_state_dir_from_cli_returns_normalized_XDG_STATE_HOME_path_when_XDG_SET" {
	TEST_HOME="$HOME_DIR"
	XDG_STATE_HOME="$TEST_TMPDIR/xdgstate"
	mkdir -p "$TEST_TMPDIR"
	run timeout 30s env HOME="$TEST_HOME" XDG_STATE_HOME="$XDG_STATE_HOME" bash -c "source \"$BATS_TEST_DIRNAME/paths.sh\"; bs_path_state_dir_from_cli"
	[ "$status" -eq 0 ]
	expected="$XDG_STATE_HOME/battleship"
	[ "$output" = "$expected" ]
	[ -d "$expected" ]
}

@test "Unit_bs_path_state_dir_from_cli_falls_back_to_HOME_dot_local_state_when_XDG_unset" {
	unset XDG_STATE_HOME
	TEST_HOME="$HOME_DIR"
	run timeout 30s env HOME="$TEST_HOME" bash -c "source \"$BATS_TEST_DIRNAME/paths.sh\"; bs_path_state_dir_from_cli"
	[ "$status" -eq 0 ]
	expected="$TEST_HOME/.local/state/battleship"
	[ "$output" = "$expected" ]
	[ -d "$expected" ]
}

@test "Unit_bs_path_state_dir_from_cli_accepts_safe_CLI_override_and_returns_normalized_path" {
	# create a cli override that contains duplicate slashes and trailing slash
	mkdir -p "$TEST_TMPDIR"
	override="$TEST_TMPDIR/override//subdir//"
	normalized="$TEST_TMPDIR/override/subdir"
	run timeout 30s env HOME="$HOME_DIR" bash -c "source \"$BATS_TEST_DIRNAME/paths.sh\"; bs_path_state_dir_from_cli \"$override\""
	[ "$status" -eq 0 ]
	[ "$output" = "$normalized" ]
	[ -d "$normalized" ]
}

@test "Unit_bs_path_state_dir_from_cli_rejects_CLI_override_with_dotdot_and_errors" {
	override="$TEST_TMPDIR/.."
	run timeout 30s env HOME="$HOME_DIR" bash -c "source \"$BATS_TEST_DIRNAME/paths.sh\"; bs_path_state_dir_from_cli \"$override\""
	# function returns 2 when normalization rejects the value
	[ "$status" -eq 2 ]
}

@test "Unit_bs_path_state_dir_from_cli_rejects_CLI_override_starting_with_dash_and_errors" {
	override="-badpath"
	run timeout 30s env HOME="$HOME_DIR" bash -c "source \"$BATS_TEST_DIRNAME/paths.sh\"; bs_path_state_dir_from_cli \"$override\""
	[ "$status" -eq 2 ]
}
