#!/usr/bin/env bats

setup() {
	SCRIPT="${BATS_TEST_DIRNAME}/help_text.sh"
}

@test "unit_print_usage_outputs_concise_usage_only_without_long_help_sections" {
	run timeout 5s bash -c "source \"$SCRIPT\" && battleship_help_usage_short"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Usage: battleship.sh <command> [options]"* ]] || fail "missing usage line"
	[[ "$output" == *"Commands: new, load, play, help, version"* ]] || fail "missing commands list"
	[[ "$output" != *"Examples:"* ]] || fail "unexpected Examples section"
	[[ "$output" != *"Privacy & state"* ]] || fail "unexpected Privacy section"
}

@test "unit_print_usage_ignores_unexpected_arguments_and_returns_same_concise_output" {
	run timeout 5s bash -c "source \"$SCRIPT\" && battleship_help_usage_short"
	baseline="$output"
	run timeout 5s bash -c "source \"$SCRIPT\" && set -- unexpected arg && battleship_help_usage_short \"\$@\""
	[ "$status" -eq 0 ]
	[ "$output" = "$baseline" ] || fail "output changed when given unexpected arguments"
}

@test "unit_short_usage_does_not_include_examples_privacy_or_state_directory_text" {
	run timeout 5s bash -c "BATTLESHIP_STATE_DIR=/tmp/custom_state source \"$SCRIPT\" && battleship_help_usage_short"
	[ "$status" -eq 0 ]
	[[ "$output" != *"Examples:"* ]] || fail
	[[ "$output" != *"Privacy & state"* ]] || fail
	[[ "$output" != *"/tmp/custom_state"* ]] || fail
}

@test "unit_print_help_includes_new_and_load_command_examples" {
	run timeout 5s bash -c "source \"$SCRIPT\" && battleship_help_long"
	[ "$status" -eq 0 ]
	[[ "$output" == *"battleship.sh new --size standard --ai normal"* ]] || fail "missing new example"
	[[ "$output" == *"battleship.sh load /path/to/save.json"* ]] || fail "missing load example"
}

@test "unit_print_help_includes_board_sizes_and_ai_levels_together" {
	run timeout 5s bash -c "source \"$SCRIPT\" && battleship_help_long"
	[ "$status" -eq 0 ]
	board_line=$(printf "%s\n" "$output" | grep -n -m1 "Board sizes" | cut -d: -f1 || true)
	ai_line=$(printf "%s\n" "$output" | grep -n -m1 "AI difficulty levels" | cut -d: -f1 || true)
	[ -n "$board_line" ] || fail "no board sizes section"
	[ -n "$ai_line" ] || fail "no AI levels section"
	[ "$board_line" -le "$ai_line" ] || fail "board sizes should appear before AI levels"
}
