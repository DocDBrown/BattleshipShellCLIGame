#!/usr/bin/env bash
IFS=$'\n\t'
LC_ALL=C

# ai_medium_helper_1.sh - coordinate and hunt-queue utilities
# Library only: defines helper functions for medium AI. No execution at source.
# Globals expected (set by caller):
# - BS_AI_MEDIUM_BOARD_SIZE : integer board side length
# - BS_AI_MEDIUM_CELLSTATES : indexed array of cell states ("unknown","miss","hit","ship", ...)
# - BS_AI_MEDIUM_HUNT_QUEUE  : indexed array (managed here) of integer linear indices
#
# Functions are idempotent where appropriate and return meaningful exit codes.

# Enable strict mode only when executed directly, not when sourced.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	set -euo pipefail
fi

# Ensure the hunt queue array exists in the current shell (do not overwrite if present).
if ! declare -p BS_AI_MEDIUM_HUNT_QUEUE >/dev/null 2>&1; then
	BS_AI_MEDIUM_HUNT_QUEUE=()
fi

_bs_ai_medium_idx_from_raw() {
	local raw_r="${1:-}" raw_c="${2:-}"
	if [[ -z "${raw_r}" || -z "${raw_c}" ]]; then
		return 2
	fi
	if [[ ! "${raw_r}" =~ ^[0-9]+$ ]] || [[ ! "${raw_c}" =~ ^[0-9]+$ ]]; then
		return 2
	fi
	if [[ -z "${BS_AI_MEDIUM_BOARD_SIZE:-}" || "${BS_AI_MEDIUM_BOARD_SIZE}" -le 0 ]]; then
		return 3
	fi
	if (( raw_r < 0 || raw_r >= BS_AI_MEDIUM_BOARD_SIZE || raw_c < 0 || raw_c >= BS_AI_MEDIUM_BOARD_SIZE )); then
		return 4
	fi
	_BS_AI_MEDIUM_RET_IDX=$((raw_r * BS_AI_MEDIUM_BOARD_SIZE + raw_c))
	return 0
}

_bs_ai_medium_push_hunt() {
	local idx="${1:-}" existing
	if [[ -z "${idx}" || ! "${idx}" =~ ^[0-9]+$ ]]; then
		return 2
	fi
	# If cell already shot/known, do not enqueue
	if [[ "${BS_AI_MEDIUM_CELLSTATES[idx]:-unknown}" != "unknown" ]]; then
		return 0
	fi
	# Ensure hunt queue is an array; iterate defensively
	for existing in "${BS_AI_MEDIUM_HUNT_QUEUE[@]:-}"; do
		if [[ "${existing}" -eq "${idx}" ]]; then
			return 0
		fi
	done
	BS_AI_MEDIUM_HUNT_QUEUE+=("${idx}")
	return 0
}

_bs_ai_medium_pop_hunt() {
	# Treat an unset or empty queue as having no elements.
	if [[ ${#BS_AI_MEDIUM_HUNT_QUEUE[@]} -eq 0 ]]; then
		return 1
	fi
	local idx="${BS_AI_MEDIUM_HUNT_QUEUE[0]}"
	if [[ ${#BS_AI_MEDIUM_HUNT_QUEUE[@]} -gt 1 ]]; then
		BS_AI_MEDIUM_HUNT_QUEUE=("${BS_AI_MEDIUM_HUNT_QUEUE[@]:1}")
	else
		BS_AI_MEDIUM_HUNT_QUEUE=()
	fi
	printf "%s" "${idx}"
	return 0
}

_bs_ai_medium_enqueue_neighbors() {
	local idx="${1:-}" r c nr nc nidx
	if [[ -z "${idx}" || ! "${idx}" =~ ^[0-9]+$ ]]; then
		return 2
	fi
	r=$((idx / BS_AI_MEDIUM_BOARD_SIZE))
	c=$((idx % BS_AI_MEDIUM_BOARD_SIZE))
	if (( r - 1 >= 0 )); then
		nr=$((r - 1)); nc=$c
		nidx=$((nr * BS_AI_MEDIUM_BOARD_SIZE + nc))
		_bs_ai_medium_push_hunt "${nidx}" || true
	fi
	if (( r + 1 < BS_AI_MEDIUM_BOARD_SIZE )); then
		nr=$((r + 1)); nc=$c
		nidx=$((nr * BS_AI_MEDIUM_BOARD_SIZE + nc))
		_bs_ai_medium_push_hunt "${nidx}" || true
	fi
	if (( c - 1 >= 0 )); then
		nr=$r; nc=$((c - 1))
		nidx=$((nr * BS_AI_MEDIUM_BOARD_SIZE + nc))
		_bs_ai_medium_push_hunt "${nidx}" || true
	fi
	if (( c + 1 < BS_AI_MEDIUM_BOARD_SIZE )); then
		nr=$r; nc=$((c + 1))
		nidx=$((nr * BS_AI_MEDIUM_BOARD_SIZE + nc))
		_bs_ai_medium_push_hunt "${nidx}" || true
	fi
	return 0
}
