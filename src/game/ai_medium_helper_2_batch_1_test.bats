#!/usr/bin/env bats

setup() {
	# Source the library under test from the same directory as this test file.
	# shellcheck disable=SC1091
	. "${BATS_TEST_DIRNAME}/ai_medium_helper_2.sh"
}

@test "unit_medium_hunt_mode_respects_board_bounds_at_corner_and_only_returns_valid_neighbors" {
	BS_AI_MEDIUM_BOARD_SIZE=3
	declare -a BS_AI_MEDIUM_CELLSTATES
	for i in $(seq 0 $((BS_AI_MEDIUM_BOARD_SIZE * BS_AI_MEDIUM_BOARD_SIZE - 1))); do
		BS_AI_MEDIUM_CELLSTATES[i]=unknown
	done

	# Corner index 0 (row 0, col 0). Valid orthogonal neighbours are 3 (down) and 1 (right).
	# With helper's order up, down, left, right we expect index 3.
	bs_ai_medium_pick_hunt_adjacent 0
	ret=$?
	[ "$ret" -eq 0 ]
	[ "${_BS_AI_MEDIUM_RET_IDX:-}" -eq 3 ]
}

@test "unit_medium_hunt_mode_remembers_hunt_cluster_across_multiple_calls_and_continues_probing" {
	BS_AI_MEDIUM_BOARD_SIZE=3
	declare -a BS_AI_MEDIUM_CELLSTATES
	for i in $(seq 0 8); do
		BS_AI_MEDIUM_CELLSTATES[i]=unknown
	done

	# First pick around center (index 4) should be up (1).
	bs_ai_medium_pick_hunt_adjacent 4
	ret=$?
	[ "$ret" -eq 0 ]
	idx1=${_BS_AI_MEDIUM_RET_IDX}
	BS_AI_MEDIUM_CELLSTATES[idx1]=hit

	# After marking the first as hit, the next pick should move to the next orthogonal unknown (7).
	bs_ai_medium_pick_hunt_adjacent 4
	ret2=$?
	[ "$ret2" -eq 0 ]
	idx2=${_BS_AI_MEDIUM_RET_IDX}

	[ "$idx1" -ne "$idx2" ]
	[ "$idx1" -eq 1 ]
	[ "$idx2" -eq 7 ]
}

@test "unit_medium_hunt_mode_returns_to_random_mode_when_no_valid_hunt_targets_remain" {
	BS_AI_MEDIUM_BOARD_SIZE=3
	declare -a BS_AI_MEDIUM_CELLSTATES
	for i in $(seq 0 8); do
		BS_AI_MEDIUM_CELLSTATES[i]=unknown
	done

	# All orthogonal neighbours of the center (4) are non-unknown.
	BS_AI_MEDIUM_CELLSTATES[1]=miss
	BS_AI_MEDIUM_CELLSTATES[3]=miss
	BS_AI_MEDIUM_CELLSTATES[5]=miss
	BS_AI_MEDIUM_CELLSTATES[7]=miss

	# Capture the non-zero status inside an if so it doesn't trip set -e.
	if bs_ai_medium_pick_hunt_adjacent 4; then
		hunt_status=0
	else
		hunt_status=$?
	fi

	[ "$hunt_status" -eq 1 ]

	# Stub RNG so that random selection is deterministic: always pick the minimum in range.
	# shellcheck disable=SC2317
	bs_rng_int_range() {
		if [ "$#" -ne 2 ]; then
			return 2
		fi
		printf "%d\n" "$1"
	}

	_bs_ai_medium_pick_random_unknown
	rand_status=$?
	[ "$rand_status" -eq 0 ]

	idx=${_BS_AI_MEDIUM_RET_IDX}
	# Index must be within board and correspond to an unknown cell.
	[ "$idx" -ge 0 ]
	[ "$idx" -lt 9 ]
	[ "${BS_AI_MEDIUM_CELLSTATES[idx]}" = "unknown" ]
}

@test "unit_medium_never_targets_same_cell_twice_across_hunt_and_random_modes" {
	BS_AI_MEDIUM_BOARD_SIZE=3
	declare -a BS_AI_MEDIUM_CELLSTATES
	for i in $(seq 0 8); do
		BS_AI_MEDIUM_CELLSTATES[i]=unknown
	done

	# Deterministic RNG: always pick the minimum candidate index.
	# shellcheck disable=SC2317
	bs_rng_int_range() {
		if [ "$#" -ne 2 ]; then
			return 2
		fi
		printf "%d\n" "$1"
	}

	_bs_ai_medium_pick_random_unknown
	first=${_BS_AI_MEDIUM_RET_IDX}
	BS_AI_MEDIUM_CELLSTATES[first]=miss

	_bs_ai_medium_pick_random_unknown
	second=${_BS_AI_MEDIUM_RET_IDX}

	[ "$first" -ne "$second" ]
}

@test "unit_medium_builds_hunt_candidates_from_provided_turn_history_with_multiple_hits" {
	BS_AI_MEDIUM_BOARD_SIZE=3
	declare -a BS_AI_MEDIUM_CELLSTATES
	for i in $(seq 0 8); do
		BS_AI_MEDIUM_CELLSTATES[i]=unknown
	done

	# Simulate prior hits at indices 1 and 4; helper should still pick a valid orthogonal unknown.
	BS_AI_MEDIUM_CELLSTATES[1]=hit
	BS_AI_MEDIUM_CELLSTATES[4]=hit

	bs_ai_medium_pick_hunt_adjacent 4
	ret=$?
	[ "$ret" -eq 0 ]
	# With 1 already non-unknown, the next orthogonal in order is 7 (down).
	[ "${_BS_AI_MEDIUM_RET_IDX}" -eq 7 ]
}
