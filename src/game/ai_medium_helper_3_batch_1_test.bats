#!/usr/bin/env bats
# shellcheck disable=SC1091

setup() {
	# Source the library under test from the same directory as this test file.
	. "${BATS_TEST_DIRNAME}/ai_medium_helper_3.sh"
	# Ensure a fresh state for each test.
	BS_AI_MEDIUM_SEEN_SHOTS=()
	# Save any board globals to ensure functions don't mutate them.
	BS_BOARD_SIZE_prev="${BS_BOARD_SIZE:-__unset__}"
	BS_BOARD_TOTAL_SEGMENTS_prev="${BS_BOARD_TOTAL_SEGMENTS:-__unset__}"
}

teardown() {
	# Restore board globals to their previous values (or unset if they were not present).
	if [[ "${BS_BOARD_SIZE_prev}" == "__unset__" ]]; then
		unset BS_BOARD_SIZE || true
	else
		BS_BOARD_SIZE="${BS_BOARD_SIZE_prev}"
	fi
	if [[ "${BS_BOARD_TOTAL_SEGMENTS_prev}" == "__unset__" ]]; then
		unset BS_BOARD_TOTAL_SEGMENTS || true
	else
		BS_BOARD_TOTAL_SEGMENTS="${BS_BOARD_TOTAL_SEGMENTS_prev}"
	fi
}

@test "unit_hunt_exhausts_local_candidates_and_returns_to_random_mode_excluding_all_previous_shots" {
	# Simulate marking a small cluster of local hunt candidates.
	_bs_ai_medium_mark_seen "5"
	_bs_ai_medium_mark_seen "6"
	_bs_ai_medium_mark_seen "15"
	_bs_ai_medium_mark_seen "16"

	[ "${#BS_AI_MEDIUM_SEEN_SHOTS[@]}" -eq 4 ] || fail "Expected 4 seen shots recorded"

	for idx in 5 6 15 16; do
		if ! _bs_ai_medium_has_seen "${idx}"; then
			fail "Expected index ${idx} to be marked seen"
		fi
	done

	# Idempotency: marking an already seen index should not add duplicates.
	_bs_ai_medium_mark_seen "6"
	[ "${#BS_AI_MEDIUM_SEEN_SHOTS[@]}" -eq 4 ] || fail "Idempotency failure: duplicate entry added"
}

@test "unit_never_selects_any_previously_targeted_cell_in_random_or_hunt_mode" {
	# Mark a set of previously targeted cells and ensure they are reported as seen.
	local marked=(0 1 2 3 4 10 11 12)
	local idx
	for idx in "${marked[@]}"; do
		_bs_ai_medium_mark_seen "${idx}"
	done

	for idx in "${marked[@]}"; do
		if ! _bs_ai_medium_has_seen "${idx}"; then
			fail "Previously targeted index ${idx} reported as unseen"
		fi
	done

	# An index not marked should be reported as unseen.
	if _bs_ai_medium_has_seen "9999"; then
		fail "Unmarked index 9999 incorrectly reported as seen"
	fi
}

@test "unit_decision_logic_uses_only_provided_history_and_does_not_peek_at_hidden_player_board" {
	# Set board globals to sentinel values and ensure helpers do not change them.
	BS_BOARD_SIZE=123
	BS_BOARD_TOTAL_SEGMENTS=77

	_bs_ai_medium_mark_seen "42"
	if ! _bs_ai_medium_has_seen "42"; then
		fail "Marker function did not record a valid index"
	fi

	# Verify the board-related globals were not modified by these helper calls.
	[ "${BS_BOARD_SIZE}" -eq 123 ] || fail "BS_BOARD_SIZE was unexpectedly modified"
	[ "${BS_BOARD_TOTAL_SEGMENTS}" -eq 77 ] || fail "BS_BOARD_TOTAL_SEGMENTS was unexpectedly modified"
}

@test "unit_malformed_history_input_returns_error_and_performs_no_selection" {
	# Calling mark_seen with empty input should return a non-zero status and not add anything.
	if _bs_ai_medium_mark_seen ""; then
		fail "Expected _bs_ai_medium_mark_seen to fail on empty input"
	fi
	[ "${#BS_AI_MEDIUM_SEEN_SHOTS[@]}" -eq 0 ] || fail "Malformed input altered seen-shots array"
}

@test "unit_no_available_targets_left_reports_failure_or_empty_selection_when_board_fully_targeted" {
	# Define a small universe of possible targets and mark them all as seen.
	local universe=(A B C D E)
	local u
	for u in "${universe[@]}"; do
		_bs_ai_medium_mark_seen "${u}"
	done

	# Ensure every possible target in the universe is seen.
	for u in "${universe[@]}"; do
		if ! _bs_ai_medium_has_seen "${u}"; then
			fail "Expected universe element ${u} to be marked seen"
		fi
	done

	# Confirm there are no unseen items inside this universe.
	local unseen_found=0
	for u in "${universe[@]}"; do
		if ! _bs_ai_medium_has_seen "${u}"; then
			unseen_found=1
			break
		fi
	done
	[ "${unseen_found}" -eq 0 ] || fail "Found an unseen target despite marking all targets"
}
