#!/usr/bin/env bats

setup() {
	SCRIPT="${BATS_TEST_DIRNAME}/validation.sh"
	if [ ! -f "${SCRIPT}" ]; then
		echo "validation.sh not found in test directory"
		exit 1
	fi
}

@test "validate_board_size_accepts_minimum_8" {
	run timeout 5s bash -c ". \"${SCRIPT}\" && validate_board_size 8"
	[ "$status" -eq 0 ]
}

@test "validate_board_size_accepts_midrange_10" {
	run timeout 5s bash -c ". \"${SCRIPT}\" && validate_board_size 10"
	[ "$status" -eq 0 ]
}

@test "validate_board_size_accepts_maximum_12" {
	run timeout 5s bash -c ". \"${SCRIPT}\" && validate_board_size 12"
	[ "$status" -eq 0 ]
}

@test "validate_board_size_rejects_below_minimum_7" {
	run timeout 5s bash -c ". \"${SCRIPT}\" && validate_board_size 7"
	[ "$status" -ne 0 ]
}

@test "validate_board_size_rejects_above_maximum_13" {
	run timeout 5s bash -c ". \"${SCRIPT}\" && validate_board_size 13"
	[ "$status" -ne 0 ]
}
