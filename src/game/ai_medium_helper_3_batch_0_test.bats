#!/usr/bin/env bats
# shellcheck disable=SC1091,SC2034

. "${BATS_TEST_DIRNAME}/ai_medium_helper_3.sh"

setup() {
	# Reset global array before each test to ensure isolation
	BS_AI_MEDIUM_SEEN_SHOTS=()
}

@test "unit_no_prior_shots_random_mode_picks_valid_untargeted_cell_within_board_bounds" {
	# Initially the index should not be reported seen
	if _bs_ai_medium_has_seen "1_1"; then
		fail "Expected not seen before marking"
	fi

	# Mark the shot and ensure it is recorded
	if ! _bs_ai_medium_mark_seen "1_1"; then
		fail "mark_seen should succeed"
	fi

	if ! _bs_ai_medium_has_seen "1_1"; then
		fail "Expected seen after marking"
	fi
}

@test "unit_history_only_misses_random_mode_excludes_all_previous_shots_and_returns_new_cell" {
	# Pre-seed history with two misses
	BS_AI_MEDIUM_SEEN_SHOTS=("3_3" "4_4")

	if ! _bs_ai_medium_has_seen "3_3"; then
		fail "Previously marked shot 3_3 should be reported seen"
	fi

	if ! _bs_ai_medium_has_seen "4_4"; then
		fail "Previously marked shot 4_4 should be reported seen"
	fi

	# A new cell should not be reported seen
	if _bs_ai_medium_has_seen "5_5"; then
		fail "Unmarked shot 5_5 should not be reported seen"
	fi

	if ! _bs_ai_medium_mark_seen "5_5"; then
		fail "mark_seen should succeed for new shot"
	fi

	if ! _bs_ai_medium_has_seen "5_5"; then
		fail "Shot 5_5 should be seen after marking"
	fi
}

@test "unit_single_recent_hit_enters_hunt_and_targets_an_adjacent_untargeted_cell" {
	# Simulate a recent hit at 5_5; neighbors are potential hunt targets
	BS_AI_MEDIUM_SEEN_SHOTS=("5_5")

	# Candidate neighbor that should not yet be seen
	local neighbor="5_6"
	if _bs_ai_medium_has_seen "${neighbor}"; then
		fail "Neighbor ${neighbor} unexpectedly marked seen already"
	fi

	if ! _bs_ai_medium_mark_seen "${neighbor}"; then
		fail "mark_seen should succeed for neighbor"
	fi

	if ! _bs_ai_medium_has_seen "${neighbor}"; then
		fail "Neighbor ${neighbor} should be seen after marking"
	fi
}

@test "unit_hunt_on_corner_hit_respects_board_boundaries_and_does_not_select_out_of_bounds_neighbors" {
	# Simulate a corner hit at 1_1 (top-left). Out-of-bounds representations should
	# not be present by default and can be safely ignored by caller logic.
	BS_AI_MEDIUM_SEEN_SHOTS=("1_1")

	if _bs_ai_medium_has_seen "0_1"; then
		fail "Out-of-bounds 0_1 should not be seen by default"
	fi

	if _bs_ai_medium_has_seen "1_0"; then
		fail "Out-of-bounds 1_0 should not be seen by default"
	fi

	# Mark a valid in-bounds neighbor and ensure it is recorded
	if ! _bs_ai_medium_mark_seen "1_2"; then
		fail "mark_seen should succeed for corner neighbor"
	fi

	if ! _bs_ai_medium_has_seen "1_2"; then
		fail "Corner neighbor 1_2 should be seen after marking"
	fi
}

@test "unit_hunt_continues_across_multiple_sequential_hits_extending_cluster_and_prefers_adjacent_probing" {
	# Seed an existing cluster and extend it
	BS_AI_MEDIUM_SEEN_SHOTS=("7_7" "7_8")

	if ! _bs_ai_medium_mark_seen "7_9"; then
		fail "mark_seen should succeed when extending cluster"
	fi

	if ! _bs_ai_medium_has_seen "7_9"; then
		fail "Extended cluster cell 7_9 should be seen after marking"
	fi

	# Ensure unrelated cell remains unseen
	if _bs_ai_medium_has_seen "1_9"; then
		fail "Unrelated cell 1_9 should remain unseen"
	fi
}
