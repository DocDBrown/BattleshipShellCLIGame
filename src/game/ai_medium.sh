#!/usr/bin/env bash
set -euo pipefail
LC_ALL=C

# ai_medium.sh - Medium AI for Battleship (public API)
# Purpose: Public entry points for a medium-difficulty Battleship AI.
# This file provides the public functions and sources focused helpers
# that implement internal utilities. Callers may source this file to
# obtain the API; the helpers are sourced from the same directory if
# present, but functions are written defensively so tests can provide
# implementations before calling init.

# Load helper modules from the same directory when available.
_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${_script_dir}/ai_medium_helper_1.sh" ]]; then
	# shellcheck source=/dev/null
	source "${_script_dir}/ai_medium_helper_1.sh"
fi
if [[ -f "${_script_dir}/ai_medium_helper_2.sh" ]]; then
	# shellcheck source=/dev/null
	source "${_script_dir}/ai_medium_helper_2.sh"
fi
if [[ -f "${_script_dir}/ai_medium_helper_3.sh" ]]; then
	# shellcheck source=/dev/null
	source "${_script_dir}/ai_medium_helper_3.sh"
fi

# Internal return variable for index
_BS_AI_MEDIUM_RET_IDX=0

# Public globals documented for callers/tests
# BS_AI_MEDIUM_BOARD_SIZE (int)
# BS_AI_MEDIUM_CELLSTATES (indexed array: unknown|miss|hit|sunk)
# BS_AI_MEDIUM_HUNT_QUEUE (indexed array of integer indices)
# BS_AI_MEDIUM_SEEN_SHOTS (indexed array of integer indices)

# Initialize or reinitialize the AI internal structures.
# Usage: bs_ai_medium_init <board_size> [seed]
bs_ai_medium_init() {
	local size
	size="${1:-}"
	if [[ -z "${size}" ]]; then
		if [[ -n "${BS_BOARD_SIZE:-}" && "${BS_BOARD_SIZE}" =~ ^[0-9]+$ && "${BS_BOARD_SIZE}" -ge 1 ]]; then
			size="${BS_BOARD_SIZE}"
		else
			size=10
		fi
	fi

	if [[ ! "${size}" =~ ^[1-9][0-9]*$ ]]; then
		printf "Invalid board size: %s\n" "${size}" >&2
		return 2
	fi

	if ! type bs_rng_int_range >/dev/null 2>&1; then
		printf "Required RNG helper bs_rng_int_range not found; provide rng.sh before init\n" >&2
		return 3
	fi

	BS_AI_MEDIUM_BOARD_SIZE=$((size))
	local total=$((BS_AI_MEDIUM_BOARD_SIZE * BS_AI_MEDIUM_BOARD_SIZE))

	declare -g -a BS_AI_MEDIUM_CELLSTATES
	BS_AI_MEDIUM_CELLSTATES=()
	local i
	for ((i = 0; i < total; i++)); do
		BS_AI_MEDIUM_CELLSTATES[i]="unknown"
	done

	declare -g -a BS_AI_MEDIUM_HUNT_QUEUE
	BS_AI_MEDIUM_HUNT_QUEUE=()
	declare -g -a BS_AI_MEDIUM_SEEN_SHOTS
	BS_AI_MEDIUM_SEEN_SHOTS=()

	if [[ ${#} -ge 2 ]]; then
		if type bs_rng_init_from_seed >/dev/null 2>&1; then
			bs_rng_init_from_seed "${2}" || return 4
		else
			printf "RNG seed requested but bs_rng_init_from_seed not found; continuing without seed\n" >&2
		fi
	else
		if type bs_rng_init_auto >/dev/null 2>&1; then
			bs_rng_init_auto || true
		fi
	fi

	return 0
}

# Reset optionally with a new board size
bs_ai_medium_reset() {
	local new_size="${1:-}"
	if [[ -n "${new_size}" ]]; then
		bs_ai_medium_init "${new_size}" || return $?
		return 0
	fi

	if [[ -z "${BS_AI_MEDIUM_BOARD_SIZE:-}" || "${BS_AI_MEDIUM_BOARD_SIZE}" -le 0 ]]; then
		printf "AI not initialized; call bs_ai_medium_init first or provide a size to reset\n" >&2
		return 2
	fi

	bs_ai_medium_init "${BS_AI_MEDIUM_BOARD_SIZE}" || return $?
	return 0
}

# Record the result of a shot. Idempotent for repeated calls with same args.
# Usage: bs_ai_medium_record_result <row_zero_based> <col_zero_based> <result>
bs_ai_medium_record_result() {
	if [[ ${#} -ne 3 ]]; then
		printf "Usage: bs_ai_medium_record_result <r> <c> <result>\n" >&2
		return 2
	fi
	local raw_r="${1}" raw_c="${2}" result="${3}"
	if [[ ! "${result}" =~ ^(hit|miss|sunk)$ ]]; then
		printf "Invalid result value: %s\n" "${result}" >&2
		return 3
	fi

	if ! _bs_ai_medium_idx_from_raw "${raw_r}" "${raw_c}"; then
		printf "Coordinates out of bounds or invalid: %s %s\n" "${raw_r}" "${raw_c}" >&2
		return 4
	fi
	local idx="${_BS_AI_MEDIUM_RET_IDX}"

	# Idempotent: if the state is already this result, do nothing.
	if [[ "${BS_AI_MEDIUM_CELLSTATES[idx]:-unknown}" == "${result}" ]]; then
		return 0
	fi

	BS_AI_MEDIUM_CELLSTATES[idx]="${result}"

	_bs_ai_medium_mark_seen "${idx}"

	if [[ "${result}" == "hit" ]]; then
		_bs_ai_medium_enqueue_neighbors "${idx}" || true
	elif [[ "${result}" == "sunk" ]]; then
		# Clear hunt queue when a ship is sunk; the next target will come from random mode.
		BS_AI_MEDIUM_HUNT_QUEUE=()
	fi

	return 0
}

# Choose the next shot. Prints two integers (row col) zero-based to stdout.
bs_ai_medium_choose_shot() {
	if [[ -z "${BS_AI_MEDIUM_BOARD_SIZE:-}" || "${BS_AI_MEDIUM_BOARD_SIZE}" -le 0 ]]; then
		printf "AI not initialized; call bs_ai_medium_init first\n" >&2
		return 2
	fi

	local candidate_idx_raw candidate_idx rr cc

	# Try hunt queue if helper is available or if default provided
	if type _bs_ai_medium_pop_hunt >/dev/null 2>&1; then
		while :; do
			if ! candidate_idx_raw=$(_bs_ai_medium_pop_hunt 2>/dev/null); then
				break
			fi
			candidate_idx="${candidate_idx_raw}"
			if [[ "${BS_AI_MEDIUM_CELLSTATES[candidate_idx]:-unknown}" == "unknown" ]]; then
				rr=$((candidate_idx / BS_AI_MEDIUM_BOARD_SIZE))
				cc=$((candidate_idx % BS_AI_MEDIUM_BOARD_SIZE))
				printf "%d %d\n" "${rr}" "${cc}"
				return 0
			fi
		done
	fi

	# Fallback to random unknown selection
	if ! _bs_ai_medium_pick_random_unknown; then
		# No available unknowns
		return 1
	fi
	candidate_idx="${_BS_AI_MEDIUM_RET_IDX}"
	rr=$((candidate_idx / BS_AI_MEDIUM_BOARD_SIZE))
	cc=$((candidate_idx % BS_AI_MEDIUM_BOARD_SIZE))
	printf "%d %d\n" "${rr}" "${cc}"
	return 0
}

# --- Default helper implementations (only if not provided by helpers) ---
# These are intentionally minimal and defensive so tests can override by
# sourcing helper files prior to using the public API.

if ! type _bs_ai_medium_idx_from_raw >/dev/null 2>&1; then
	_bs_ai_medium_idx_from_raw() {
		local raw_r="${1:-}" raw_c="${2:-}"
		if [[ -z "${raw_r}" || -z "${raw_c}" ]]; then
			return 1
		fi
		if [[ ! "${raw_r}" =~ ^[0-9]+$ ]] || [[ ! "${raw_c}" =~ ^[0-9]+$ ]]; then
			return 1
		fi
		if [[ -z "${BS_AI_MEDIUM_BOARD_SIZE:-}" || "${BS_AI_MEDIUM_BOARD_SIZE}" -le 0 ]]; then
			return 2
		fi
		local r=${raw_r} c=${raw_c}
		if ((r < 0 || r >= BS_AI_MEDIUM_BOARD_SIZE || c < 0 || c >= BS_AI_MEDIUM_BOARD_SIZE)); then
			return 2
		fi
		_BS_AI_MEDIUM_RET_IDX=$((r * BS_AI_MEDIUM_BOARD_SIZE + c))
		return 0
	}
fi

if ! type _bs_ai_medium_mark_seen >/dev/null 2>&1; then
	_bs_ai_medium_mark_seen() {
		local idx="${1:-}"
		if [[ -z "${idx}" ]]; then
			return 1
		fi
		# Avoid duplicates
		local s
		for s in "${BS_AI_MEDIUM_SEEN_SHOTS[@]:-}"; do
			if [[ "${s}" == "${idx}" ]]; then
				return 0
			fi
		done
		BS_AI_MEDIUM_SEEN_SHOTS+=("${idx}")
		return 0
	}
fi

if ! type _bs_ai_medium_enqueue_neighbors >/dev/null 2>&1; then
	_bs_ai_medium_enqueue_neighbors() {
		local idx="${1:-}"
		if [[ -z "${idx}" ]]; then
			return 1
		fi
		if [[ -z "${BS_AI_MEDIUM_BOARD_SIZE:-}" ]]; then
			return 2
		fi
		local r=$((idx / BS_AI_MEDIUM_BOARD_SIZE))
		local c=$((idx % BS_AI_MEDIUM_BOARD_SIZE))
		local nr nc nidx
		# neighbors: up, down, left, right
		for nr in $((r - 1)) $((r + 1)); do
			if ((nr >= 0 && nr < BS_AI_MEDIUM_BOARD_SIZE)); then
				nidx=$((nr * BS_AI_MEDIUM_BOARD_SIZE + c))
				# skip if already shot/known
				if [[ "${BS_AI_MEDIUM_CELLSTATES[nidx]:-unknown}" != "unknown" ]]; then
					: # skip
				else
					local _local_already=0 _x
					for _x in "${BS_AI_MEDIUM_HUNT_QUEUE[@]:-}"; do
						if [[ "${_x}" == "${nidx}" ]]; then
							_local_already=1
							break
						fi
					done
					if [[ "${_local_already}" -eq 0 ]]; then
						BS_AI_MEDIUM_HUNT_QUEUE+=("${nidx}")
					fi
				fi
			fi
		done
		for nc in $((c - 1)) $((c + 1)); do
			if ((nc >= 0 && nc < BS_AI_MEDIUM_BOARD_SIZE)); then
				nidx=$((r * BS_AI_MEDIUM_BOARD_SIZE + nc))
				if [[ "${BS_AI_MEDIUM_CELLSTATES[nidx]:-unknown}" != "unknown" ]]; then
					: # skip
				else
					local _local_already=0 _x
					for _x in "${BS_AI_MEDIUM_HUNT_QUEUE[@]:-}"; do
						if [[ "${_x}" == "${nidx}" ]]; then
							_local_already=1
							break
						fi
					done
					if [[ "${_local_already}" -eq 0 ]]; then
						BS_AI_MEDIUM_HUNT_QUEUE+=("${nidx}")
					fi
				fi
			fi
		done
		return 0
	}
fi

if ! type _bs_ai_medium_pop_hunt >/dev/null 2>&1; then
	_bs_ai_medium_pop_hunt() {
		if [[ ${#BS_AI_MEDIUM_HUNT_QUEUE[@]:-0} -eq 0 ]]; then
			return 1
		fi
		local first="${BS_AI_MEDIUM_HUNT_QUEUE[0]}"
		# remove the first element
		if ((${#BS_AI_MEDIUM_HUNT_QUEUE[@]} > 1)); then
			BS_AI_MEDIUM_HUNT_QUEUE=("${BS_AI_MEDIUM_HUNT_QUEUE[@]:1}")
		else
			BS_AI_MEDIUM_HUNT_QUEUE=()
		fi
		printf "%s\n" "${first}"
		return 0
	}
fi

# Always override _bs_ai_medium_pick_random_unknown for the public AI.
# This implementation:
#   - Builds a list of indices whose state is "unknown"
#   - Returns 1 (non-zero) if there are no such cells (board fully targeted)
#   - Otherwise uses bs_rng_int_range to pick one uniformly at random
_bs_ai_medium_pick_random_unknown() {
	if [[ -z "${BS_AI_MEDIUM_BOARD_SIZE:-}" || "${BS_AI_MEDIUM_BOARD_SIZE}" -le 0 ]]; then
		return 2
	fi

	local total=$((BS_AI_MEDIUM_BOARD_SIZE * BS_AI_MEDIUM_BOARD_SIZE))
	local -a unknowns=()
	local i
	for ((i = 0; i < total; i++)); do
		if [[ "${BS_AI_MEDIUM_CELLSTATES[i]:-unknown}" == "unknown" ]]; then
			unknowns+=("${i}")
		fi
	done

	local count=${#unknowns[@]}
	if ((count == 0)); then
		# No available unknown cells left.
		return 1
	fi

	# Choose a random index into unknowns using the provided RNG helper.
	local pick
	pick="$(bs_rng_int_range 0 "$((count - 1))")" || return 3
	_BS_AI_MEDIUM_RET_IDX=${unknowns[pick]}
	return 0
}