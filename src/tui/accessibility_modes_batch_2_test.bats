#!/usr/bin/env bats

setup() {
	export BATS_TEST_DIRNAME
	export TERM=xterm-256color
}

@test "mapping_role_changes_for_high_contrast_vs_normal_color_when_color_supported" {
	run bash -c 'export COLORTERM=truecolor; . "${BATS_TEST_DIRNAME}/accessibility_modes.sh"; bs_accessibility_set_mode color || exit 3; a="$(bs_accessibility_style_for hit)"; bs_accessibility_set_mode high-contrast || exit 4; b="$(bs_accessibility_style_for hit)"; printf "%s\n%s\n" "$a" "$b"'
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == *"X"* ]]
	[[ "${lines[0]}" != *"✖"* ]]
	[[ "${lines[1]}" == *"✖"* ]]
}

@test "runtime_toggle_from_color_to_monochrome_updates_mode_and_mappings" {
	run bash -c 'export COLORTERM=truecolor; . "${BATS_TEST_DIRNAME}/accessibility_modes.sh"; bs_accessibility_set_mode color || exit 3; bs_accessibility_set_mode monochrome || exit 4; printf "%s\n%s\n" "$(bs_accessibility_current_mode)" "$(bs_accessibility_style_for hit)"'
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "monochrome" ]
	[ "${lines[1]}" = "X" ]
}

@test "runtime_toggle_to_high_contrast_updates_mode_and_mappings_when_color_supported" {
	run bash -c 'export COLORTERM=truecolor; . "${BATS_TEST_DIRNAME}/accessibility_modes.sh"; bs_accessibility_set_mode high-contrast || exit 3; printf "%s\n%s\n" "$(bs_accessibility_current_mode)" "$(bs_accessibility_style_for hit)"'
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "high-contrast" ]
	[[ "${lines[1]}" == *"✖"* ]]
}

@test "runtime_toggle_to_high_contrast_is_ignored_when_color_not_supported_and_mode_remains_monochrome" {
	run bash -c 'export BS_MONOCHROME=1; . "${BATS_TEST_DIRNAME}/accessibility_modes.sh"; before="$(bs_accessibility_current_mode)"; bs_accessibility_set_mode high-contrast; rc=$?; after="$(bs_accessibility_current_mode)"; sym="$(bs_accessibility_style_for hit)"; printf "%s\n%s\n%s\n%s\n" "$before" "$rc" "$after" "$sym"'
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "monochrome" ]
	[ "${lines[1]}" -eq 1 ]
	[ "${lines[2]}" = "monochrome" ]
	[ "${lines[3]}" = "X" ]
}

@test "get_current_mode_reflects_initial_mode_after_initialization" {
	run bash -c 'export COLORTERM=truecolor; export BS_HIGH_CONTRAST=1; . "${BATS_TEST_DIRNAME}/accessibility_modes.sh"; printf "%s\n" "$(bs_accessibility_current_mode)"'
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "high-contrast" ]
}