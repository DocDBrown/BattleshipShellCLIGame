#!/usr/bin/env bats

setup() {
	:
}

teardown() {
	:
}

@test "get_current_mode_updates_after_runtime_toggle" {
	# Simulate a terminal that already reports color support by stubbing probe results
	run bash -c "export BS_TERM_PROBED=1; export BS_TERM_HAS_COLOR=1; source \"$BATS_TEST_DIRNAME/accessibility_modes.sh\"; bs_accessibility_current_mode"
	[ "$status" -eq 0 ]
	[ "$output" = "color" ]

	# Toggle to monochrome and verify
	run bash -c "export BS_TERM_PROBED=1; export BS_TERM_HAS_COLOR=1; source \"$BATS_TEST_DIRNAME/accessibility_modes.sh\"; bs_accessibility_set_mode monochrome; bs_accessibility_current_mode"
	[ "$status" -eq 0 ]
	[ "$output" = "monochrome" ]

	# Toggle back to color and verify
	run bash -c "export BS_TERM_PROBED=1; export BS_TERM_HAS_COLOR=1; source \"$BATS_TEST_DIRNAME/accessibility_modes.sh\"; bs_accessibility_set_mode color; bs_accessibility_current_mode"
	[ "$status" -eq 0 ]
	[ "$output" = "color" ]
}
