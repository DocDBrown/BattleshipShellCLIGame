#!/usr/bin/env bats

@test "unit_parse_new_happy_path_emits_key_value_config_and_exits_zero" {
	run timeout 30s bash "${BATS_TEST_DIRNAME}/arg_parser.sh" --new
	[ "$status" -eq 0 ]
	echo "$output" | grep -q "^new=1$"
}

@test "unit_reject_conflicting_new_and_load_flags_with_nonzero_exit_and_error_message" {
	run timeout 30s bash "${BATS_TEST_DIRNAME}/arg_parser.sh" --new --load /tmp/somefile
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "Conflicting options: --new and --load"
}

@test "unit_error_when_load_missing_argument_exits_nonzero_with_clear_message" {
	run timeout 30s bash "${BATS_TEST_DIRNAME}/arg_parser.sh" --load
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "Missing value for --load"
}

@test "unit_accept_load_with_file_argument_emits_normalized_load_path_and_exits_zero" {
	tmpdir=$(mktemp -d)
	path="$tmpdir/foo/../bar"
	run timeout 30s bash "${BATS_TEST_DIRNAME}/arg_parser.sh" --load "$path"
	[ "$status" -eq 0 ]
	expected="$tmpdir/bar"
	echo "$output" | grep -q "^load_file=${expected}$"
	rm -rf "$tmpdir"
}

@test "unit_accept_valid_size_within_bounds_emits_normalized_size_and_exits_zero" {
	run timeout 30s bash "${BATS_TEST_DIRNAME}/arg_parser.sh" --size 10
	[ "$status" -eq 0 ]
	echo "$output" | grep -q "^size=10$"
}
