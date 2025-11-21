#!/usr/bin/env bats

setup() {
	SCRIPT="${BATS_TEST_DIRNAME}/arg_parser.sh"
}

@test "unit_reject_non_numeric_size_exits_nonzero_with_error" {
	run timeout 30s bash "$SCRIPT" --size foo
	[ "$status" -ne 0 ]
	[[ "$output" == *"Invalid size: foo"* ]]
}

@test "unit_reject_out_of_range_size_exits_nonzero_with_error" {
	run timeout 30s bash "$SCRIPT" --size 20
	[ "$status" -ne 0 ]
	[[ "$output" == *"Size must be between 8 and 12"* ]]
}

@test "unit_accept_valid_ai_value_emits_normalized_ai_and_exits_zero" {
	run timeout 30s bash "$SCRIPT" --ai medium
	[ "$status" -eq 0 ]
	[[ "$output" == *"ai=medium"* ]]
}

@test "unit_reject_invalid_ai_value_exits_nonzero_with_error" {
	run timeout 30s bash "$SCRIPT" --ai ultra
	[ "$status" -ne 0 ]
	[[ "$output" == *"Invalid ai level: ultra"* ]]
}

@test "unit_accept_numeric_seed_emits_normalized_seed_and_exits_zero" {
	run timeout 30s bash "$SCRIPT" --seed 123
	[ "$status" -eq 0 ]
	[[ "$output" == *"seed=123"* ]]
}
