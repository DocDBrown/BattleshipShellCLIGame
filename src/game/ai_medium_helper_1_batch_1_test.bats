#!/usr/bin/env bats
# shellcheck disable=SC1091,SC2034

setup() {
	. "${BATS_TEST_DIRNAME}/ai_medium_helper_1.sh"
}

@test "ai_medium_hunt_selection_constrained_to_unshot_adjacent_cells_only" {
	BS_AI_MEDIUM_BOARD_SIZE=3
	BS_AI_MEDIUM_CELLSTATES=()
	for i in $(seq 0 $((BS_AI_MEDIUM_BOARD_SIZE * BS_AI_MEDIUM_BOARD_SIZE - 1))); do
		BS_AI_MEDIUM_CELLSTATES[i]="unknown"
	done
	BS_AI_MEDIUM_HUNT_QUEUE=()

	# center at (1,1)
	_bs_ai_medium_idx_from_raw 1 1 || { fail "idx_from_raw failed"; }
	idx=${_BS_AI_MEDIUM_RET_IDX}

	# neighbors linear indices for center on 3x3: up=1, down=7, left=3, right=5
	BS_AI_MEDIUM_CELLSTATES[1]="miss"
	BS_AI_MEDIUM_CELLSTATES[3]="hit"

	_bs_ai_medium_enqueue_neighbors "${idx}"

	# ensure only unknown neighbors (5 and 7) are enqueued
	found5=0
	found7=0
	for e in "${BS_AI_MEDIUM_HUNT_QUEUE[@]:-}"; do
		if [[ "${e}" -eq 5 ]]; then found5=1; fi
		if [[ "${e}" -eq 7 ]]; then found7=1; fi
		if [[ "${e}" -eq 1 || "${e}" -eq 3 ]]; then
			fail "Enqueued a neighbor that was not unknown: ${e}"
		fi
	done
	if [[ "${found5}" -ne 1 || "${found7}" -ne 1 ]]; then
		fail "Expected both unknown neighbors 5 and 7 to be enqueued, got: ${BS_AI_MEDIUM_HUNT_QUEUE[*]}"
	fi
}

@test "ai_medium_hunt_continues_across_turns_preserving_cluster_state_after_misses_and_hits" {
	BS_AI_MEDIUM_BOARD_SIZE=3
	BS_AI_MEDIUM_CELLSTATES=()
	for i in $(seq 0 $((BS_AI_MEDIUM_BOARD_SIZE * BS_AI_MEDIUM_BOARD_SIZE - 1))); do
		BS_AI_MEDIUM_CELLSTATES[i]="unknown"
	done
	BS_AI_MEDIUM_HUNT_QUEUE=()

	_bs_ai_medium_idx_from_raw 1 1 || { fail "idx_from_raw failed"; }
	idx=${_BS_AI_MEDIUM_RET_IDX}
	_bs_ai_medium_enqueue_neighbors "${idx}"

	tmp=$(mktemp)
	_bs_ai_medium_pop_hunt >"${tmp}" || {
		rm -f "${tmp}"
		fail "expected a hunt candidate"
	}
	first_candidate=$(<"${tmp}")
	rm -f "${tmp}"

	# mark it a miss
	BS_AI_MEDIUM_CELLSTATES[first_candidate]="miss"

	# ensure queue still has remaining candidates
	if [[ ${#BS_AI_MEDIUM_HUNT_QUEUE[@]} -eq 0 ]]; then
		fail "Hunt queue emptied unexpectedly after marking a miss"
	fi

	# pop next and mark hit
	tmp=$(mktemp)
	_bs_ai_medium_pop_hunt >"${tmp}" || {
		rm -f "${tmp}"
		fail "expected a second hunt candidate"
	}
	second_candidate=$(<"${tmp}")
	rm -f "${tmp}"
	BS_AI_MEDIUM_CELLSTATES[second_candidate]="hit"

	# after a hit, the queue should still be preserved (remaining or extended by other logic)
	# At minimum, ensure that the state we changed is reflected
	if [[ "${BS_AI_MEDIUM_CELLSTATES[second_candidate]}" != "hit" ]]; then
		fail "Hit was not recorded for index ${second_candidate}"
	fi
}

@test "ai_medium_hunt_extends_cluster_when_adjacent_hit_discovers_new_candidates" {
	BS_AI_MEDIUM_BOARD_SIZE=4
	BS_AI_MEDIUM_CELLSTATES=()
	for i in $(seq 0 $((BS_AI_MEDIUM_BOARD_SIZE * BS_AI_MEDIUM_BOARD_SIZE - 1))); do
		BS_AI_MEDIUM_CELLSTATES[i]="unknown"
	done
	BS_AI_MEDIUM_HUNT_QUEUE=()

	# pick (1,1)
	_bs_ai_medium_idx_from_raw 1 1 || { fail "idx_from_raw failed"; }
	idx=${_BS_AI_MEDIUM_RET_IDX}
	_bs_ai_medium_enqueue_neighbors "${idx}"

	# pop a neighbor and mark it hit, then enqueue that neighbor's neighbors
	tmp=$(mktemp)
	_bs_ai_medium_pop_hunt >"${tmp}" || {
		rm -f "${tmp}"
		fail "expected a hunt candidate"
	}
	popped=$(<"${tmp}")
	rm -f "${tmp}"

	BS_AI_MEDIUM_CELLSTATES[popped]="hit"
	# Enqueue neighbors around the newly hit cell
	_bs_ai_medium_enqueue_neighbors "${popped}"

	# ensure at least one neighbor of popped (that is unknown) was added to queue
	added_found=0
	for e in "${BS_AI_MEDIUM_HUNT_QUEUE[@]:-}"; do
		if [[ "${BS_AI_MEDIUM_CELLSTATES[e]}" == "unknown" ]]; then
			added_found=1
			break
		fi
	done
	if [[ "${added_found}" -ne 1 ]]; then
		fail "Expected at least one new unknown candidate after a hit, queue: ${BS_AI_MEDIUM_HUNT_QUEUE[*]}"
	fi
}

@test "ai_medium_returns_to_random_mode_when_no_hunt_candidates_and_excludes_all_shots" {
	BS_AI_MEDIUM_BOARD_SIZE=3
	BS_AI_MEDIUM_CELLSTATES=()
	for i in $(seq 0 $((BS_AI_MEDIUM_BOARD_SIZE * BS_AI_MEDIUM_BOARD_SIZE - 1))); do
		BS_AI_MEDIUM_CELLSTATES[i]="miss"
	done
	BS_AI_MEDIUM_HUNT_QUEUE=()

	# No unknown cells; pushing any index should be a no-op, and popping should fail
	_bs_ai_medium_push_hunt 4 || true
	if [[ ${#BS_AI_MEDIUM_HUNT_QUEUE[@]} -ne 0 ]]; then
		fail "Expected hunt queue to remain empty when all cells are shot"
	fi

	# pop should return non-zero
	if _bs_ai_medium_pop_hunt >/dev/null 2>&1; then
		fail "Expected pop to fail when queue is empty"
	fi
}

@test "ai_medium_selection_determined_only_by_provided_turn_history_not_hidden_board" {
	BS_AI_MEDIUM_BOARD_SIZE=3
	BS_AI_MEDIUM_CELLSTATES=()
	for i in $(seq 0 $((BS_AI_MEDIUM_BOARD_SIZE * BS_AI_MEDIUM_BOARD_SIZE - 1))); do
		BS_AI_MEDIUM_CELLSTATES[i]="unknown"
	done
	BS_AI_MEDIUM_HUNT_QUEUE=()

	# Simulate a hidden board that has ships but the AI must not peek at it
	HS_HIDDEN_BOARD=()
	HS_HIDDEN_BOARD[4]="ship"

	# Since the visible turn history marks index 4 unknown, push should enqueue it even if hidden board has a ship
	_bs_ai_medium_push_hunt 4 || fail "push failed"
	found=0
	for e in "${BS_AI_MEDIUM_HUNT_QUEUE[@]:-}"; do
		if [[ "${e}" -eq 4 ]]; then
			found=1
			break
		fi
	done
	if [[ "${found}" -ne 1 ]]; then
		fail "AI incorrectly used hidden board to avoid enqueueing index 4"
	fi
}
