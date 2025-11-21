#!/usr/bin/env bats

# Ensure functions are sourced from the same directory as this test file via BATS_TEST_DIRNAME

@test "validate_coordinate_rejects_column_number_out_of_range_A11_on_board_size_10" {
	run timeout 5s bash -c "source \"${BATS_TEST_DIRNAME}/validation.sh\" && validate_coordinate \"A11\" 10"
	[ "$status" -eq 1 ]
}

@test "validate_coordinate_rejects_lowercase_a1_on_board_size_10" {
	run timeout 5s bash -c "source \"${BATS_TEST_DIRNAME}/validation.sh\" && validate_coordinate \"a1\" 10"
	[ "$status" -eq 1 ]
}

@test "validate_coordinate_rejects_malformed_A_only" {
	run timeout 5s bash -c "source \"${BATS_TEST_DIRNAME}/validation.sh\" && validate_coordinate \"A\" 10"
	[ "$status" -eq 1 ]
}

@test "validate_ai_difficulty_accepts_known_difficulties_easy_medium_hard" {
	run timeout 5s bash -c "source \"${BATS_TEST_DIRNAME}/validation.sh\" && validate_ai_difficulty easy"
	[ "$status" -eq 0 ]

	run timeout 5s bash -c "source \"${BATS_TEST_DIRNAME}/validation.sh\" && validate_ai_difficulty medium"
	[ "$status" -eq 0 ]

	run timeout 5s bash -c "source \"${BATS_TEST_DIRNAME}/validation.sh\" && validate_ai_difficulty hard"
	[ "$status" -eq 0 ]
}

@test "validate_ai_difficulty_rejects_invalid_or_miscased_difficulties" {
	run timeout 5s bash -c "source \"${BATS_TEST_DIRNAME}/validation.sh\" && validate_ai_difficulty Easy"
	[ "$status" -eq 1 ]

	run timeout 5s bash -c "source \"${BATS_TEST_DIRNAME}/validation.sh\" && validate_ai_difficulty unknown"
	[ "$status" -eq 1 ]
}
