#!/usr/bin/env bats

@test "validate_board_size_rejects_non_integer_nine" {
	run timeout 30s bash -c "source \"$BATS_TEST_DIRNAME/validation.sh\" && validate_board_size nine"
	[ "$status" -eq 1 ]
}

@test "validate_coordinate_accepts_A10_on_board_size_10" {
	run timeout 30s bash -c "source \"$BATS_TEST_DIRNAME/validation.sh\" && validate_coordinate A10 10"
	[ "$status" -eq 0 ]
}

@test "validate_coordinate_accepts_I9_on_board_size_9" {
	run timeout 30s bash -c "source \"$BATS_TEST_DIRNAME/validation.sh\" && validate_coordinate I9 9"
	[ "$status" -eq 0 ]
}

@test "validate_coordinate_accepts_J1_on_board_size_10" {
	run timeout 30s bash -c "source \"$BATS_TEST_DIRNAME/validation.sh\" && validate_coordinate J1 10"
	[ "$status" -eq 0 ]
}

@test "validate_coordinate_rejects_row_letter_out_of_range_K1_on_board_size_10" {
	run timeout 30s bash -c "source \"$BATS_TEST_DIRNAME/validation.sh\" && validate_coordinate K1 10"
	[ "$status" -eq 1 ]
}
