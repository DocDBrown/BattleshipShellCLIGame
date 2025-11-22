#!/usr/bin/env bats

setup() {
	# No external setup required; tests source the module and then configure probe variables before invoking functions.
	:
}

@test "init_with_monochrome_flag_sets_mode_monochrome" {
	run timeout 5s bash -c ". \"${BATS_TEST_DIRNAME}/accessibility_modes.sh\"; export BS_TERM_PROBED=1; export BS_TERM_HAS_COLOR=0; export BS_MONOCHROME=1; bs_accessibility_current_mode"
	[ "$status" -eq 0 ]
	[ "$output" = "monochrome" ]
}

@test "init_with_no_color_flag_sets_mode_monochrome" {
	run timeout 5s bash -c ". \"${BATS_TEST_DIRNAME}/accessibility_modes.sh\"; export BS_TERM_PROBED=1; export BS_TERM_HAS_COLOR=1; export NO_COLOR=1; bs_accessibility_current_mode"
	[ "$status" -eq 0 ]
	[ "$output" = "monochrome" ]
}

@test "init_with_high_contrast_and_color_support_sets_mode_high_contrast" {
	run timeout 5s bash -c ". \"${BATS_TEST_DIRNAME}/accessibility_modes.sh\"; export BS_TERM_PROBED=1; export BS_TERM_HAS_COLOR=1; export BS_HIGH_CONTRAST=1; bs_accessibility_current_mode"
	[ "$status" -eq 0 ]
	[ "$output" = "high-contrast" ]
}

@test "init_with_high_contrast_without_color_support_sets_mode_monochrome" {
	run timeout 5s bash -c ". \"${BATS_TEST_DIRNAME}/accessibility_modes.sh\"; export BS_TERM_PROBED=1; export BS_TERM_HAS_COLOR=0; export BS_HIGH_CONTRAST=1; bs_accessibility_current_mode"
	[ "$status" -eq 0 ]
	[ "$output" = "monochrome" ]
}

@test "init_with_no_flags_and_color_support_sets_mode_color" {
	run timeout 5s bash -c ". \"${BATS_TEST_DIRNAME}/accessibility_modes.sh\"; export BS_TERM_PROBED=1; export BS_TERM_HAS_COLOR=1; unset BS_HIGH_CONTRAST BS_MONOCHROME NO_COLOR BS_NO_COLOR || true; bs_accessibility_current_mode"
	[ "$status" -eq 0 ]
	[ "$output" = "color" ]
}
