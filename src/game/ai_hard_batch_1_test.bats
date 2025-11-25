#!/usr/bin/env bats

# Target queue, forbidden cells, and persistence tests

setup() {
	BATS_TEST_DIRNAME_TMP="$(mktemp -d)"
	export BATS_TEST_DIRNAME_TMP

	# Mock rng.sh: deterministic index from MOCK_RNG_VALUE (default 0)
	cat >"${BATS_TEST_DIRNAME_TMP}/rng.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

bs_rng_int_range() {
  # Ignore range bounds; caller uses valid ranges.
  echo "${MOCK_RNG_VALUE:-0}"
}
EOF

	# Mock board_state.sh: only board size
	cat >"${BATS_TEST_DIRNAME_TMP}/board_state.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

BS_BOARD_SIZE=10
EOF

	# Copy SUT into this temp dir
	cp "${BATS_TEST_DIRNAME}/ai_hard.sh" "${BATS_TEST_DIRNAME_TMP}/ai_hard.sh"

	# shellcheck disable=SC1090,SC1091
	. "${BATS_TEST_DIRNAME_TMP}/ai_hard.sh"

	bs_ai_hard_init
}

teardown() {
	rm -rf "${BATS_TEST_DIRNAME_TMP}"
}

@test "unit_ai_hard_does_not_target_cells_already_marked_hit_or_miss" {
	# Mark 1,1 as visited
	export BS_AI_HARD_VISITED_1_1=1

	# RNG returns index 0 (first candidate)
	export MOCK_RNG_VALUE=0

	run bs_ai_hard_choose_shot
	[ "$status" -eq 0 ]

	# Should not pick 1 1, as it's already visited
	[ "$output" != "1 1" ]
	# With row-major candidate list, index 0 becomes 1,2
	[ "$output" = "1 2" ]
}

@test "unit_ai_hard_avoids_impossible_targets_out_of_bounds_or_contradicting_inference" {
	# Scenario 1: horizontal hits 5,5 and 5,6 → queue must not contain verticals
	bs_ai_hard_init
	bs_ai_hard_notify_result 5 5 "hit"
	bs_ai_hard_notify_result 5 6 "hit"

	local found_vertical=0
	local r c i
	for ((i = 0; i < ${#BS_AI_HARD_TARGET_QUEUE_R[@]}; i++)); do
		r=${BS_AI_HARD_TARGET_QUEUE_R[i]}
		c=${BS_AI_HARD_TARGET_QUEUE_C[i]}
		if [ "$r" -ne 5 ]; then
			found_vertical=1
		fi
	done
	[ "$found_vertical" -eq 0 ]

	# Scenario 2: hits at 1,1 and 1,2 → ensure no out-of-bounds col 0
	bs_ai_hard_init
	bs_ai_hard_notify_result 1 1 "hit"
	bs_ai_hard_notify_result 1 2 "hit"

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
	bs_ai_hard_init

	# Turn 1: Hit at 5,5
	bs_ai_hard_notify_result 5 5 "hit"
	[ "$BS_AI_HARD_STATE" = "target" ]

	# Turn 2: choose neighbor from queue
	run bs_ai_hard_choose_shot
	[ "$status" -eq 0 ]
	local shot1="$output"
	[[ "$shot1" =~ ^(4\ 5|6\ 5|5\ 4|5\ 6)$ ]]

	# Turn 3: Miss there; should remain in target mode (queue still has other neighbors)
	read -r r1 c1 <<<"$shot1"
	bs_ai_hard_notify_result "$r1" "$c1" "miss"
	[ "$BS_AI_HARD_STATE" = "target" ]

	# Turn 4: choose another shot, distinct from previous
	run bs_ai_hard_choose_shot
	[ "$status" -eq 0 ]
	local shot2="$output"
	[ "$shot2" != "$shot1" ]
}

@test "unit_ai_hard_marks_ship_sunk_and_adds_forbidden_neighbor_cells_to_avoid" {
	bs_ai_hard_init

	# Hit at 5,5 then sink at 5,6 (ship of length 2)
	bs_ai_hard_notify_result 5 5 "hit"
	bs_ai_hard_notify_result 5 6 "sink"

	# Check a few neighbors are forbidden (visited)
	[ "${BS_AI_HARD_VISITED_4_5:-}" = "1" ] # neighbor of both
	[ "${BS_AI_HARD_VISITED_5_7:-}" = "1" ] # neighbor of 5,6
	[ "${BS_AI_HARD_VISITED_6_6:-}" = "1" ] # diagonal neighbor

	# Hit tracking cleared
	[ "${#BS_AI_HARD_HITS_R[@]}" -eq 0 ]
	[ "${#BS_AI_HARD_HITS_C[@]}" -eq 0 ]
}

@test "unit_ai_hard_forbidden_cells_prevent_targeting_neighbors_of_sunk_ships" {
	bs_ai_hard_init

	# Hit 5,5 and sink 5,6, marking neighbors forbidden
	bs_ai_hard_notify_result 5 5 "hit"
	bs_ai_hard_notify_result 5 6 "sink"

	# Neighbor 5,7 should be visited
	[ "${BS_AI_HARD_VISITED_5_7:-}" = "1" ]

	# Fresh hunt: ensure 5,7 is never chosen as a candidate
	bs_ai_hard_init
	export BS_AI_HARD_VISITED_5_7=1

	run bs_ai_hard_choose_shot
	[ "$status" -eq 0 ]
	[ "$output" != "5 7" ]
}
