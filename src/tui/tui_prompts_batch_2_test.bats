#!/usr/bin/env bats

setup() {
	SCRIPT="$BATS_TEST_DIRNAME/tui_prompts.sh"
}

@test "integration_prompt_coordinate_handles_validation_error_code_2_board_size_and_shows_board_size_error" {
	run timeout 30s bash -c "source \"$SCRIPT\"; prompt_coordinate 7" <<'EOF'
A1
EOF
	[ "$status" -eq 2 ]
	[[ "$output" == *"Invalid board size, must be an integer between 8 and 12."* ]]
}

@test "integration_confirm_save_rejects_unsafe_filename_using_validation_sh_integration" {
	run timeout 30s bash -c "source \"$SCRIPT\"; confirm_overwrite \"../escape\""
	[ "$status" -eq 2 ]
}
