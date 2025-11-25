#!/usr/bin/env bash
IFS=$'\n\t'
LC_ALL=C

# ai_medium_helper_2.sh - unknown-cell collection and random selection

# Enable strict mode only when executed directly, not when sourced as a library.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	set -euo pipefail
fi

# Internal: pick a random unknown cell index and set _BS_AI_MEDIUM_RET_IDX
# Returns 0 on success, non-zero if no unknowns or RNG failure
_bs_ai_medium_pick_random_unknown() {
	if [[ -z "${BS_AI_MEDIUM_BOARD_SIZE:-}" || "${BS_AI_MEDIUM_BOARD_SIZE}" -le 0 ]]; then
		return 2
	fi
	local total=$((BS_AI_MEDIUM_BOARD_SIZE * BS_AI_MEDIUM_BOARD_SIZE))
	local -a unknown_indices
	local i
	for ((i = 0; i < total; i++)); do
		if [[ "${BS_AI_MEDIUM_CELLSTATES[i]:-unknown}" == "unknown" ]]; then
			unknown_indices+=("${i}")
		fi
	done
	if [[ ${#unknown_indices[@]} -eq 0 ]]; then
		return 1
	fi
	local max_index=$((${#unknown_indices[@]} - 1))
	local choice_pos
	choice_pos=$(bs_rng_int_range 0 "${max_index}") || return 3
	if [[ ! "${choice_pos}" =~ ^-?[0-9]+$ ]]; then
		return 4
	fi
	_BS_AI_MEDIUM_RET_IDX=${unknown_indices[choice_pos]}
	return 0
}

# Public: Pick an adjacent unknown cell for hunt mode around a hit index.
# Arguments: center_idx (0-based index into BS_AI_MEDIUM_CELLSTATES)
# Returns: 0 and sets _BS_AI_MEDIUM_RET_IDX to an adjacent unknown index following
# the order up, down, left, right; returns 1 if no adjacent unknowns; returns >1 on error.
bs_ai_medium_pick_hunt_adjacent() {
	local center_idx="${1:-}"
	if [[ -z "${BS_AI_MEDIUM_BOARD_SIZE:-}" || "${BS_AI_MEDIUM_BOARD_SIZE}" -le 0 ]]; then
		return 2
	fi
	if [[ -z "${center_idx}" || ! "${center_idx}" =~ ^[0-9]+$ ]]; then
		return 3
	fi
	local size=$BS_AI_MEDIUM_BOARD_SIZE
	local r=$((center_idx / size))
	local c=$((center_idx % size))
	local nr nc nidx
	# Check up
	nr=$((r - 1))
	nc=$c
	if ((nr >= 0)); then
		nidx=$((nr * size + nc))
		if [[ "${BS_AI_MEDIUM_CELLSTATES[nidx]:-unknown}" == "unknown" ]]; then
			_BS_AI_MEDIUM_RET_IDX=$nidx
			return 0
		fi
	fi
	# Check down
	nr=$((r + 1))
	nc=$c
	if ((nr < size)); then
		nidx=$((nr * size + nc))
		if [[ "${BS_AI_MEDIUM_CELLSTATES[nidx]:-unknown}" == "unknown" ]]; then
			_BS_AI_MEDIUM_RET_IDX=$nidx
			return 0
		fi
	fi
	# Check left
	nr=$r
	nc=$((c - 1))
	if ((nc >= 0)); then
		nidx=$((nr * size + nc))
		if [[ "${BS_AI_MEDIUM_CELLSTATES[nidx]:-unknown}" == "unknown" ]]; then
			_BS_AI_MEDIUM_RET_IDX=$nidx
			return 0
		fi
	fi
	# Check right
	nr=$r
	nc=$((c + 1))
	if ((nc < size)); then
		nidx=$((nr * size + nc))
		if [[ "${BS_AI_MEDIUM_CELLSTATES[nidx]:-unknown}" == "unknown" ]]; then
			_BS_AI_MEDIUM_RET_IDX=$nidx
			return 0
		fi
	fi
	# No adjacent unknowns
	return 1
}
