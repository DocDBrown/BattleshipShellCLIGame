#!/usr/bin/env bats

setup() {
	# no persistent state needed; tests will invoke the script as a subprocess
	:
}

teardown() {
	:
}

@test "launcher_Integration_exits_with_error_when_arg_parser_detects_conflicting_options" {
	run timeout 5s bash "${BATS_TEST_DIRNAME}/battleship_helper_3.sh" --new --load some.save
	# Expect non-zero exit
	[ "$status" -ne 0 ]
	# Expect an informative error message mentioning the conflict
	[[ "$output" == *"Conflicting options: --new and --load"* ]] || [[ "$output" == *"Conflicting options"* ]]
}

@test "launcher_Integration_exits_with_error_when_arg_parser_detects_unknown_argument" {
	run timeout 5s bash "${BATS_TEST_DIRNAME}/battleship_helper_3.sh" --this-flag-does-not-exist
	[ "$status" -ne 0 ]
	[[ "$output" == *"Unknown argument: --this-flag-does-not-exist"* ]] || [[ "$output" == *"Unknown argument"* ]]
}

@test "launcher_Integration_exits_with_error_when_arg_parser_detects_missing_value" {
	run timeout 5s bash "${BATS_TEST_DIRNAME}/battleship_helper_3.sh" --size
	[ "$status" -ne 0 ]
	[[ "$output" == *"Missing value for --size"* ]] || [[ "$output" == *"Missing value for"* ]]
}
