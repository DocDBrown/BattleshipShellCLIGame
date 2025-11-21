#!/usr/bin/env bats

setup() {
	TMPDIR="$(mktemp -d -t bs_tests.XXXXXX)"
	if [[ -z "$TMPDIR" || ! -d "$TMPDIR" ]]; then
		echo "failed to create tmpdir" >&2
		exit 1
	fi
}

teardown() {
	if [[ -n "${TMPDIR-}" && "$TMPDIR" = /* && -d "$TMPDIR" ]]; then
		rm -rf -- "$TMPDIR"
	fi
}

@test "Integration_bs_path_state_dir_from_cli_creates_state_directory_with_0700_when_XDG_SET" {
	run timeout 5s bash -c 'export XDG_STATE_HOME=""'
	# run the real function with XDG_STATE_HOME set to a test-local path
	run timeout 5s bash -c 'export XDG_STATE_HOME="'"$TMPDIR"'/xdghome"; export HOME="'"$TMPDIR"'/home"; source "'"$BATS_TEST_DIRNAME"'/paths.sh"; bs_path_state_dir_from_cli'
	[ "$status" -eq 0 ]
	expected="$TMPDIR/xdghome/battleship"
	[ "$output" = "$expected" ]
	[ -d "$expected" ]
	perms=$(stat -c %a -- "$expected")
	[ "$perms" -eq 700 ]
}

@test "Integration_bs_path_state_dir_from_cli_creates_state_directory_with_0700_under_HOME_fallback" {
	run timeout 5s bash -c 'unset XDG_STATE_HOME'
	run timeout 5s bash -c 'unset XDG_STATE_HOME; export HOME="'"$TMPDIR"'/home"; source "'"$BATS_TEST_DIRNAME"'/paths.sh"; bs_path_state_dir_from_cli'
	[ "$status" -eq 0 ]
	expected="$TMPDIR/home/.local/state/battleship"
	[ "$output" = "$expected" ]
	[ -d "$expected" ]
	perms=$(stat -c %a -- "$expected")
	[ "$perms" -eq 700 ]
}

@test "Integration_bs_path_state_dir_from_cli_refuses_unsafe_CLI_override_and_does_not_create_directory" {
	unsafe_override="$TMPDIR/some/unsafe/../evil"
	run timeout 5s bash -c 'source "'"$BATS_TEST_DIRNAME"'/paths.sh"; bs_path_state_dir_from_cli "'"$unsafe_override"'"'
	[ "$status" -eq 2 ]
	[ ! -e "$unsafe_override" ]
}
