#!/usr/bin/env bats
setup() {
	SCRIPT="$BATS_TEST_DIRNAME/tui_prompts.sh"
}

@test "unit_prompt_yes_no_reprompts_until_valid_choice_and_displays_consistent_error_message" {
	run timeout 30s bash -c 'printf "maybe\nYes\n" | { source "'"$SCRIPT"'"; prompt_yes_no "Are you sure? [y/N]: " n; }'
	[ "$status" -eq 0 ]
	[[ "$output" == *"Please answer yes or no (y/n)."* ]]
	[[ "$output" != *$'\n\n'* ]]
}

@test "unit_confirm_overwrite_returns_true_on_confirmation_and_false_on_denial" {
	run timeout 30s bash -c 'printf "y\n" | { source "'"$SCRIPT"'"; confirm_overwrite "save1"; exit $?; }'
	[ "$status" -eq 0 ]

	run timeout 30s bash -c 'printf "n\n" | { source "'"$SCRIPT"'"; confirm_overwrite "save1"; exit $?; }'
	[ "$status" -eq 1 ]

	run timeout 30s bash -c '{ source "'"$SCRIPT"'"; confirm_overwrite ""; exit $?; }'
	[ "$status" -eq 2 ]
}

@test "unit_prompt_ship_placement_choice_accepts_valid_options_and_normalizes_input" {
	run timeout 30s bash -c 'printf "HARD\n" | { source "'"$SCRIPT"'"; prompt_ai_difficulty; }'
	[ "$status" -eq 0 ]
	[ "$output" = "hard" ]
}

@test "unit_prompts_avoid_emitting_extra_blank_lines_on_reprompt_to_keep_prompt_on_single_line" {
	run timeout 30s bash -c 'printf "bad\n10\n" | { source "'"$SCRIPT"'"; prompt_board_size "Enter board size (8-12): "; }'
	[ "$status" -eq 0 ]
	[[ "$output" != *$'\n\n'* ]]
}

@test "integration_prompt_coordinate_accepts_valid_coordinate_using_validation_sh_integration" {
	run timeout 30s bash -c 'printf "a5\n" | { source "'"$SCRIPT"'"; prompt_coordinate 8 "Enter coordinate (e.g. A5): "; }'
	[ "$status" -eq 0 ]
	[ "$output" = "A5" ]
}
