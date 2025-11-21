#!/usr/bin/env bats

@test "is_non_empty_accepts_non_empty_string_player" {
	run bash -c "source \"${BATS_TEST_DIRNAME}/validation.sh\"; is_non_empty_string player"
	[ "$status" -eq 0 ]
}

@test "is_non_empty_rejects_empty_string" {
	run bash -c "source \"${BATS_TEST_DIRNAME}/validation.sh\"; is_non_empty_string ''"
	[ "$status" -ne 0 ]
}

@test "is_safe_filename_accepts_simple_filename_save1_txt" {
	run bash -c "source \"${BATS_TEST_DIRNAME}/validation.sh\"; is_safe_filename 'save1.txt'"
	[ "$status" -eq 0 ]
}

@test "is_safe_filename_rejects_leading_hyphen_path_traversal_and_control_chars" {
	run bash -c "source \"${BATS_TEST_DIRNAME}/validation.sh\"; is_safe_filename '-bad'"
	[ "$status" -ne 0 ]

	run bash -c "source \"${BATS_TEST_DIRNAME}/validation.sh\"; is_safe_filename 'dir/file'"
	[ "$status" -ne 0 ]

	run bash -c "source \"${BATS_TEST_DIRNAME}/validation.sh\"; is_safe_filename 'bad..txt'"
	[ "$status" -ne 0 ]

	run bash -c "source \"${BATS_TEST_DIRNAME}/validation.sh\"; is_safe_filename $'a\\x07b'"
	[ "$status" -ne 0 ]
}

@test "is_safe_filename_rejects_empty_string" {
	run bash -c "source \"${BATS_TEST_DIRNAME}/validation.sh\"; is_safe_filename ''"
	[ "$status" -ne 0 ]
}
