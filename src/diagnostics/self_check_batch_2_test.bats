#!/usr/bin/env bats
setup() {
	TMPDIR_TEST="$(mktemp -d)"
	PATHS_SH="$BATS_TEST_DIRNAME/../runtime/paths.sh"
}
teardown() {
	if [[ -n "$TMPDIR_TEST" && -d "$TMPDIR_TEST" ]]; then
		rm -rf -- "$TMPDIR_TEST"
	fi
}

@test "Unit__bs_path_state_dir_from_cli_with_valid_override_returns_normalized_dir_and_creates_secure_dir" {
	run bash -c "source \"$PATHS_SH\" && bs_path_state_dir_from_cli \"$TMPDIR_TEST//state//sub//\""
	[ "$status" -eq 0 ]
	trimmed_output="$(printf '%s' "$output")"
	expected="$TMPDIR_TEST/state/sub"
	[ "$trimmed_output" = "$expected" ]
	[ -d "$trimmed_output" ]
	# verify permission bits are 700 (owner read/write/execute only)
	perms="$(stat -c %a "$trimmed_output")"
	[ "$perms" -eq 700 ]
}

@test "Unit__bs_path_state_dir_from_cli_with_invalid_override_propagates_normalize_error" {
	# non-absolute path should cause bs_path_state_dir_from_cli to return non-zero (return 2 expected)
	run bash -c "source \"$PATHS_SH\" && bs_path_state_dir_from_cli \"relative/path\""
	[ "$status" -ne 0 ]
	[ "$status" -eq 2 ]
}

@test "Unit__bs_path_config_dir_from_cli_with_valid_override_returns_normalized_dir_and_creates_secure_dir" {
	run bash -c "source \"$PATHS_SH\" && bs_path_config_dir_from_cli \"$TMPDIR_TEST//config//cfg//\""
	[ "$status" -eq 0 ]
	out="$(printf '%s' "$output")"
	exp="$TMPDIR_TEST/config/cfg"
	[ "$out" = "$exp" ]
	[ -d "$out" ]
	perms="$(stat -c %a "$out")"
	[ "$perms" -eq 700 ]
}

@test "Unit__bs_path_cache_dir_from_cli_with_valid_override_returns_normalized_dir_and_creates_secure_dir" {
	run bash -c "source \"$PATHS_SH\" && bs_path_cache_dir_from_cli \"$TMPDIR_TEST//cache///tmp//\""
	[ "$status" -eq 0 ]
	out="$(printf '%s' "$output")"
	exp="$TMPDIR_TEST/cache/tmp"
	[ "$out" = "$exp" ]
	[ -d "$out" ]
	perms="$(stat -c %a "$out")"
	[ "$perms" -eq 700 ]
}

@test "Unit__bs_path_saves_dir_returns_saves_subdir_and_creates_it_securely" {
	run bash -c "source \"$PATHS_SH\" && bs_path_saves_dir \"$TMPDIR_TEST//stateroot//\""
	[ "$status" -eq 0 ]
	out="$(printf '%s' "$output")"
	exp="$TMPDIR_TEST/stateroot/saves"
	[ "$out" = "$exp" ]
	[ -d "$out" ]
	perms="$(stat -c %a "$out")"
	[ "$perms" -eq 700 ]
}
