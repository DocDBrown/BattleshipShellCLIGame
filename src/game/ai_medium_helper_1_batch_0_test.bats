#!/usr/bin/env bats

# shellcheck disable=SC1091,SC2030,SC2031,SC2004,SC2154,SC2034
. "${BATS_TEST_DIRNAME}/ai_medium_helper_1.sh"

setup() {
	BS_AI_MEDIUM_BOARD_SIZE=5
	BS_AI_MEDIUM_CELLSTATES=()
	BS_AI_MEDIUM_HUNT_QUEUE=()
	total=$((BS_AI_MEDIUM_BOARD_SIZE * BS_AI_MEDIUM_BOARD_SIZE))
	for ((i = 0; i < total; i++)); do
		BS_AI_MEDIUM_CELLSTATES[i]='unknown'
	done
}

teardown() {
	BS_AI_MEDIUM_CELLSTATES=()
	BS_AI_MEDIUM_HUNT_QUEUE=()
}

@test "ai_medium_init_creates_empty_hunt_context_and_allows_random_fire" {
	[ "${#BS_AI_MEDIUM_HUNT_QUEUE[@]}" -eq 0 ]
	if _bs_ai_medium_idx_from_raw 0 0; then
		[ "$_BS_AI_MEDIUM_RET_IDX" -eq 0 ]
	else
		false
	fi
}

@test "ai_medium_random_select_in_bounds_and_excludes_previously_targeted_cells" {
	idx=7
	BS_AI_MEDIUM_CELLSTATES[idx]='miss'
	_bs_ai_medium_push_hunt "$idx"
	[ "${#BS_AI_MEDIUM_HUNT_QUEUE[@]}" -eq 0 ]
	if ! _bs_ai_medium_idx_from_raw 5 0; then
		:
	else
		false
	fi
}

@test "ai_medium_random_excludes_all_previous_shots_after_hunt_fallback" {
	total=$((BS_AI_MEDIUM_BOARD_SIZE * BS_AI_MEDIUM_BOARD_SIZE))
	for ((i = 0; i < total; i++)); do
		BS_AI_MEDIUM_CELLSTATES[i]='miss'
	done
	_bs_ai_medium_push_hunt 2
	[ "${#BS_AI_MEDIUM_HUNT_QUEUE[@]}" -eq 0 ]
}

@test "ai_medium_on_hit_enters_hunt_and_returns_adjacent_unshot_candidates" {
	r=2
	c=2
	idx=$((r * BS_AI_MEDIUM_BOARD_SIZE + c))
	left=$((r * BS_AI_MEDIUM_BOARD_SIZE + (c - 1)))
	BS_AI_MEDIUM_CELLSTATES[left]='miss'
	_bs_ai_medium_enqueue_neighbors "$idx"
	[ "${#BS_AI_MEDIUM_HUNT_QUEUE[@]}" -eq 3 ]
	found_up=0
	found_down=0
	found_right=0
	up=$(((r - 1) * BS_AI_MEDIUM_BOARD_SIZE + c))
	down=$(((r + 1) * BS_AI_MEDIUM_BOARD_SIZE + c))
	right=$((r * BS_AI_MEDIUM_BOARD_SIZE + (c + 1)))
	for val in "${BS_AI_MEDIUM_HUNT_QUEUE[@]}"; do
		if [ "$val" -eq "$up" ]; then found_up=1; fi
		if [ "$val" -eq "$down" ]; then found_down=1; fi
		if [ "$val" -eq "$right" ]; then found_right=1; fi
	done
	[ "$found_up" -eq 1 ]
	[ "$found_down" -eq 1 ]
	[ "$found_right" -eq 1 ]
}

@test "ai_medium_hunt_generation_respects_board_boundaries_no_out_of_bounds_cells" {
	idx=0
	BS_AI_MEDIUM_HUNT_QUEUE=()
	_bs_ai_medium_enqueue_neighbors "$idx"
	[ "${#BS_AI_MEDIUM_HUNT_QUEUE[@]}" -eq 2 ]
	a=$((1 * BS_AI_MEDIUM_BOARD_SIZE + 0))
	b=$((0 * BS_AI_MEDIUM_BOARD_SIZE + 1))
	have_a=0
	have_b=0
	for val in "${BS_AI_MEDIUM_HUNT_QUEUE[@]}"; do
		if [ "$val" -eq "$a" ]; then have_a=1; fi
		if [ "$val" -eq "$b" ]; then have_b=1; fi
	done
	[ "$have_a" -eq 1 ]
	[ "$have_b" -eq 1 ]
}
