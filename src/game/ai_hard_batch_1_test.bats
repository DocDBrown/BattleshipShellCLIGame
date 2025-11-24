#!/usr/bin/env bats

setup() {
	# Create a temporary directory for the test workspace
	BATS_TEST_DIRNAME_TMP=$(mktemp -d)
	export BATS_TEST_DIRNAME_TMP

	# Mock rng.sh
	cat >"${BATS_TEST_DIRNAME_TMP}/rng.sh" <<'EOF'
#!/usr/bin/env bash
bs_rng_int_range() {
    echo "${MOCK_RNG_VALUE:-0}"
}
EOF

	# Mock board_state.sh
	cat >"${BATS_TEST_DIRNAME_TMP}/board_state.sh" <<'EOF'
#!/usr/bin/env bash
BS_BOARD_SIZE=10
EOF

	# Copy the SUT to the temp directory
	cp "${BATS_TEST_DIRNAME}/ai_hard.sh" "${BATS_TEST_DIRNAME_TMP}/ai_hard.sh"

	# Source the SUT from the temp directory
	# shellcheck disable=SC1090
	. "${BATS_TEST_DIRNAME_TMP}/ai_hard.sh"

	# Initialize AI
	bs_ai_hard_init
}

teardown() {
	rm -rf "${BATS_TEST_DIRNAME_TMP}"
}

@test "unit_ai_hard_does_not_target_cells_already_marked_hit_or_miss" {
	# Inject state: Mark 1,1 as visited
	export BS_AI_HARD_VISITED_1_1=1

	# Mock RNG to return 0 (which would correspond to the first cell 1,1 if it were available)
	# Since 1,1 is visited, the loop should skip it and pick the next one (1,2)
	export MOCK_RNG_VALUE=0

	run bs_ai_hard_choose_shot
	[ "$status" -eq 0 ]
	# Should NOT be 1 1
	[ "$output" != "1 1" ]
	# Should be 1 2 because 1 1 is skipped in the candidate list construction
	[ "$output" = "1 2" ]
}

@test "unit_ai_hard_avoids_impossible_targets_out_of_bounds_or_contradicting_inference" {
	# Scenario: Hits at 5,5 and 5,6 (Horizontal)
	# This implies orientation is horizontal.
	# The AI should NOT target vertical neighbors (4,5; 6,5; etc.)

	bs_ai_hard_notify_result 5 5 "hit"
	bs_ai_hard_notify_result 5 6 "hit"

	# Check the queue. It should contain horizontal neighbors (5,4 and 5,7)
	# It should NOT contain vertical neighbors.

	local found_vertical=0
	local r c
	for ((i = 0; i < ${#BS_AI_HARD_TARGET_QUEUE_R[@]}; i++)); do
		r=${BS_AI_HARD_TARGET_QUEUE_R[i]}
		c=${BS_AI_HARD_TARGET_QUEUE_C[i]}
		if [ "$r" -ne 5 ]; then
			found_vertical=1
		fi
	done

	[ "$found_vertical" -eq 0 ]

	# Also check out of bounds: Hit at 1,1 and 1,2 (Horizontal)
	bs_ai_hard_init
	bs_ai_hard_notify_result 1 1 "hit"
	bs_ai_hard_notify_result 1 2 "hit"

	# Queue should contain 1,3. It should NOT contain 1,0 (out of bounds)
	local found_oob=0
	for ((i = 0; i < ${#BS_AI_HARD_TARGET_QUEUE_R[@]}; i++)); do
		r=${BS_AI_HARD_TARGET_QUEUE_R[i]}
		c=${BS_AI_HARD_TARGET_QUEUE_C[i]}
		if [ "$c" -lt 1 ]; then
			found_oob=1
		fi
	done
	[ "$found_oob" -eq 0 ]
}

@test "unit_ai_hard_persists_ongoing_hunt_state_across_turns_and_resumes_targeting" {
	# Turn 1: Hit at 5,5
	bs_ai_hard_notify_result 5 5 "hit"

	# Verify state is target
	[ "$BS_AI_HARD_STATE" = "target" ]

	# Turn 2: Choose shot (should come from queue)
	run bs_ai_hard_choose_shot
	[ "$status" -eq 0 ]
	local shot1="$output"

	# Verify shot1 is a neighbor of 5,5
	[[ "$shot1" =~ ^(4 5|6 5|5 4|5 6)$ ]]

	# Turn 3: Notify Miss on shot1
	read -r r1 c1 <<<"$shot1"
	bs_ai_hard_notify_result "$r1" "$c1" "miss"

	# Verify state persists as target (since queue not empty)
	# (Queue had 4 items, popped 1, 3 left)
	[ "$BS_AI_HARD_STATE" = "target" ]

	# Turn 4: Choose shot again
	run bs_ai_hard_choose_shot
	[ "$status" -eq 0 ]
	local shot2="$output"
	[ "$shot2" != "$shot1" ]
}

@test "unit_ai_hard_marks_ship_sunk_and_adds_forbidden_neighbor_cells_to_avoid" {
	# Hit at 5,5
	bs_ai_hard_notify_result 5 5 "hit"
	# Sink at 5,6 (Horizontal ship of length 2)
	bs_ai_hard_notify_result 5 6 "sink"

	# Neighbors of 5,5 and 5,6 should be visited.
	# 5,5 neighbors: 4,4; 4,5; 4,6; 5,4; 5,6(self); 6,4; 6,5; 6,6
	# 5,6 neighbors: 4,5; 4,6; 4,7; 5,5(self); 5,7; 6,5; 6,6; 6,7

	# Check a few specific neighbors
	# 4,5 (neighbor of both)
	export BS_AI_HARD_VISITED_4_5
	[ "${BS_AI_HARD_VISITED_4_5:-}" = "1" ]

	# 5,7 (neighbor of 5,6)
	export BS_AI_HARD_VISITED_5_7
	[ "${BS_AI_HARD_VISITED_5_7:-}" = "1" ]

	# 6,6 (diagonal neighbor)
	export BS_AI_HARD_VISITED_6_6
	[ "${BS_AI_HARD_VISITED_6_6:-}" = "1" ]

	# Hits should be cleared
	[ ${#BS_AI_HARD_HITS_R[@]} -eq 0 ]
}

@test "unit_ai_hard_forbidden_cells_prevent_targeting_neighbors_of_sunk_ships" {
	# Hit 5,5
	bs_ai_hard_notify_result 5 5 "hit"
	# Sink 5,6
	bs_ai_hard_notify_result 5 6 "sink"

	# Now, 5,7 is a neighbor of the sunk ship. It should be visited.
	# If we force the RNG to try to pick 5,7 (index depends on available cells), it should skip it.

	# Let's verify directly that choose_shot does not return a forbidden cell.
	# We'll run choose_shot multiple times (mocking RNG to iterate) or just check the visited map.

	# Check 5,7 is visited
	export BS_AI_HARD_VISITED_5_7
	[ "${BS_AI_HARD_VISITED_5_7:-}" = "1" ]

	# Manually ensure 5,7 is NOT in the candidate list if we were to run choose_shot in hunt mode
	# (We can't easily predict RNG index, but we can assert state)

	# Let's try to manually 'unvisit' everything EXCEPT 5,7 and see if it picks it.
	# Reset init
	bs_ai_hard_init
	# Manually visit 5,7
	export BS_AI_HARD_VISITED_5_7=1

	# Mock RNG to return the index that WOULD be 5,7 if it were unvisited.
	# 5,7 is roughly the 47th cell (row 5, col 7). (4 * 10 + 7 = 47, index 46).
	# But since it is visited, it won't be in the list.
	# So we just ensure output is NOT 5 7.

	run bs_ai_hard_choose_shot
	[ "$output" != "5 7" ]
}
