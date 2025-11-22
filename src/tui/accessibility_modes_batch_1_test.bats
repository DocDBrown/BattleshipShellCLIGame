#!/usr/bin/env bats

setup() {
	:
}

teardown() {
	:
}

@test "init_with_no_flags_without_color_support_sets_mode_monochrome" {
	run bash -c "export TERM=dumb; unset COLORTERM BS_MONOCHROME BS_NO_COLOR NO_COLOR BS_HIGH_CONTRAST BS_ACCESS_MODE; src_dir='${BATS_TEST_DIRNAME}'; source \"\$src_dir/../util/terminal_capabilities.sh\"; source \"\$src_dir/accessibility_modes.sh\"; bs_accessibility_current_mode"
	[ "$status" -eq 0 ]
	[ "$output" = "monochrome" ]
}

@test "init_with_both_high_contrast_and_monochrome_flags_prefers_monochrome" {
	run bash -c "export BS_MONOCHROME=1; export BS_HIGH_CONTRAST=1; unset BS_ACCESS_MODE; src_dir='${BATS_TEST_DIRNAME}'; source \"\$src_dir/../util/terminal_capabilities.sh\"; source \"\$src_dir/accessibility_modes.sh\"; bs_accessibility_current_mode"
	[ "$status" -eq 0 ]
	[ "$output" = "monochrome" ]
}

@test "mapping_returns_non_empty_values_for_all_roles_in_color_mode" {
	run bash -c "export COLORTERM=truecolor; unset BS_ACCESS_MODE; src_dir='${BATS_TEST_DIRNAME}'; source \"\$src_dir/../util/terminal_capabilities.sh\"; source \"\$src_dir/accessibility_modes.sh\"; bs_accessibility_map_all"
	[ "$status" -eq 0 ]
	for role in hit miss ship water status; do
		value=$(printf "%s" "$output" | awk -F= -v r="$role" '$1==r{print substr($0,index($0,"=")+1)}')
		[ -n "$value" ] || {
			echo "expected non-empty value for $role in color mode"
			false
		}
	done
}

@test "mapping_returns_non_empty_values_for_all_roles_in_monochrome_mode" {
	run bash -c "export BS_MONOCHROME=1; unset BS_ACCESS_MODE; src_dir='${BATS_TEST_DIRNAME}'; source \"\$src_dir/../util/terminal_capabilities.sh\"; source \"\$src_dir/accessibility_modes.sh\"; bs_accessibility_map_all"
	[ "$status" -eq 0 ]
	for role in hit miss ship water status; do
		value=$(printf "%s" "$output" | awk -F= -v r="$role" '$1==r{print substr($0,index($0,"=")+1)}')
		[ -n "$value" ] || {
			echo "expected non-empty value for $role in monochrome mode"
			false
		}
	done
}

@test "mapping_hit_role_differs_between_color_and_monochrome_modes" {
	run bash -c "export COLORTERM=truecolor; unset BS_ACCESS_MODE; src_dir='${BATS_TEST_DIRNAME}'; source \"\$src_dir/../util/terminal_capabilities.sh\"; source \"\$src_dir/accessibility_modes.sh\"; bs_accessibility_style_for hit"
	[ "$status" -eq 0 ]
	color_hit="$output"
	[ -n "$color_hit" ]

	run bash -c "export BS_MONOCHROME=1; unset BS_ACCESS_MODE; src_dir='${BATS_TEST_DIRNAME}'; source \"\$src_dir/../util/terminal_capabilities.sh\"; source \"\$src_dir/accessibility_modes.sh\"; bs_accessibility_style_for hit"
	[ "$status" -eq 0 ]
	mono_hit="$output"
	[ -n "$mono_hit" ]

	[ "$color_hit" != "$mono_hit" ]
}
