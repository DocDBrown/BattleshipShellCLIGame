#!/usr/bin/env bats

setup() {
	TMPDIR=$(mktemp -d)
}

teardown() {
	if [ -n "${TMPDIR-}" ] && [ -d "$TMPDIR" ]; then
		rm -f "$TMPDIR"/* || true
		rmdir "$TMPDIR" || true
	fi
}

@test "unit_prompt_coordinate_trims_whitespace_and_upcases_input_before_calling_validation" {
	run timeout 5s bash -c "source \"${BATS_TEST_DIRNAME}/tui_prompts.sh\"; prompt_coordinate 8 2>&1" <<'EOF'
    a5
EOF
	[ "$status" -eq 0 ]
	[ "$output" = "A5" ]
}

@test "unit_prompt_coordinate_reprompts_on_empty_input_and_returns_error_message" {
	run timeout 5s bash -c "source \"${BATS_TEST_DIRNAME}/tui_prompts.sh\"; prompt_coordinate 8 2>&1" <<'EOF'

A5
EOF
	[ "$status" -eq 0 ]
	# ensure the function emitted the empty-input error message and returned the valid coordinate
	printf "%s" "$output" | grep -q "Input cannot be empty." || exit 1
	printf "%s" "$output" | grep -q "A5" || exit 1
}

@test "unit_prompt_coordinate_reprompts_on_validation_failure_and_preserves_single_line_prompting" {
	# First invalid coordinate, then valid one. Count prompts to ensure reprompt occurred and error message emitted.
	run timeout 5s bash -c "source \"${BATS_TEST_DIRNAME}/tui_prompts.sh\"; prompt_coordinate 8 2>&1" <<'EOF'
Z99
B5
EOF
	[ "$status" -eq 0 ]
	printf "%s" "$output" | grep -q "Invalid coordinate." || exit 1
	prompt_str="Enter coordinate (e.g. A5): "
	count=$(printf "%s" "$output" | grep -oF "$prompt_str" | wc -l | tr -d ' ')
	[ "$count" -ge 2 ]
}

@test "unit_prompt_coordinate_handles_backspaces_gracefully_and_passes_correct_normalized_value" {
	# Compose input that types 'a', backspace, then 'B5' -> resulting input should be 'B5'
	tmpfile="$TMPDIR/input_bs.txt"
	printf $'a\bB5\n' >"$tmpfile"
	run timeout 5s bash -c "source \"${BATS_TEST_DIRNAME}/tui_prompts.sh\"; prompt_coordinate 8 2>&1" <"$tmpfile"
	[ "$status" -eq 0 ]
	[ "$output" = "B5" ]
}

@test "unit_prompt_yes_no_accepts_y_n_yes_no_with_whitespace_and_returns_boolean" {
	# Test several acceptable inputs; default is N so empty input should return non-zero status
	run timeout 5s bash -c "source \"${BATS_TEST_DIRNAME}/tui_prompts.sh\"; prompt_yes_no 2>&1" <<'EOF'
 y 
EOF
	[ "$status" -eq 0 ]

	run timeout 5s bash -c "source \"${BATS_TEST_DIRNAME}/tui_prompts.sh\"; prompt_yes_no 2>&1" <<'EOF'
YES
EOF
	[ "$status" -eq 0 ]

	run timeout 5s bash -c "source \"${BATS_TEST_DIRNAME}/tui_prompts.sh\"; prompt_yes_no 2>&1" <<'EOF'
 n
EOF
	[ "$status" -ne 0 ]

	run timeout 5s bash -c "source \"${BATS_TEST_DIRNAME}/tui_prompts.sh\"; prompt_yes_no 2>&1" <<'EOF'
NO
EOF
	[ "$status" -ne 0 ]

	# empty input should respect default 'n' and return non-zero
	run timeout 5s bash -c "source \"${BATS_TEST_DIRNAME}/tui_prompts.sh\"; prompt_yes_no 2>&1" <<'EOF'

EOF
	[ "$status" -ne 0 ]
}
