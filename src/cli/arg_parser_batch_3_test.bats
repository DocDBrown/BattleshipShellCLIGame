#!/usr/bin/env bats

setup() {
	SCRIPT="${BATS_TEST_DIRNAME}/arg_parser.sh"
}

@test "unit_self_check_quiet_success_exits_zero_and_emits_machine_friendly_intent" {
	run timeout 5s bash "$SCRIPT" --self-check
	[ "$status" -eq 0 ]
	[[ "$output" == *"self_check=1"* ]]
	[[ "$output" == *"action="* ]]
}

@test "unit_self_check_quiet_failure_exits_nonzero_and_emits_machine_friendly_intent" {
	run timeout 5s bash "$SCRIPT" --self-check --unknown
	[ "$status" -ne 0 ]
	[[ "$output" == *"ERROR=Unknown argument: --unknown"* ]]
}

@test "unit_error_on_unknown_flag_exits_nonzero_and_emits_error_intent" {
	run timeout 5s bash "$SCRIPT" --unknown
	[ "$status" -ne 0 ]
	[[ "$output" == *"Unknown argument: --unknown"* ]]
	[[ "$output" != *"ERROR="* ]]
}
