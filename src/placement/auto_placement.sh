#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# auto_placement.sh - library for automatic fleet placement
# Purpose: Provide deterministic, bounded, RNG-driven automatic placement of the
# canonical fleet onto an in-memory board. This file defines functions only and
# performs no work when sourced. Callers must source dependencies in the
# following order before invoking functions here:
#   ship_rules.sh, board_state.sh, placement_validator.sh, rng.sh
# External dependencies (checked at runtime): bs_rng_int_range, bs_placement_validate,
# bs_board_set_ship, bs_ship_list, bs_ship_length, BS_BOARD_SIZE.
# Usage: bs_auto_place_fleet [--verbose] [MAX_ATTEMPTS_PER_SHIP]
# Returns: 0 on success (all ships placed or already present), non-zero on error.

# Return codes used by this library:
# 0 - success
# 1 - invalid usage or arguments
# 2 - missing dependency
# 3 - failed to place one or more ships (max attempts exceeded)
# 4 - internal placement failure (partial placement detected)

# Helper: print usage to stderr
bs_auto_place_help() {
	printf "%s\n" "Usage: bs_auto_place_fleet [--verbose] [MAX_ATTEMPTS_PER_SHIP]" >&2
	printf "%s\n" "If MAX_ATTEMPTS_PER_SHIP is omitted, a reasonable default is used." >&2
}

# Internal: check required commands and global variables. Returns 0 on success.
_bs_auto__check_deps() {
	local miss=0
	local -a reqs=(bs_rng_int_range bs_placement_validate bs_board_set_ship bs_board_ship_remaining_segments bs_ship_list bs_ship_length)
	local cmd
	for cmd in "${reqs[@]}"; do
		if ! command -v "$cmd" >/dev/null 2>&1; then
			printf "%s\n" "Missing required function: $cmd" >&2
			miss=1
		fi
	done
	if [[ -z "${BS_BOARD_SIZE:-}" ]]; then
		printf "%s\n" "Missing or unset BS_BOARD_SIZE (run bs_board_new first)" >&2
		miss=1
	fi
	if ((miss)); then
		return 2
	fi
	return 0
}

# Internal: normalize orientation to dr,dc; returns 0 on success.
_bs_auto__orient_to_delta() {
	local orient_raw="${1:-}"
	case "${orient_raw,,}" in
	h | horizontal)
		printf "%d %d\n" 0 1
		return 0
		;;
	v | vertical)
		printf "%d %d\n" 1 0
		return 0
		;;
	*)
		return 1
		;;
	esac
}

# Public: bs_auto_place_fleet [--verbose] [MAX_ATTEMPTS_PER_SHIP]
# Places the canonical fleet defined by bs_ship_list/bs_ship_length onto the
# current board using bs_rng_int_range and bs_placement_validate. If a ship has
# already been placed (non-zero placed segments), it is skipped to maintain
# idempotency. When --verbose is provided, prints a brief placement summary that
# never exposes coordinates. Does not print or log secret/PII information.
bs_auto_place_fleet() {
	local verbose=0
	local max_attempts_per_ship_default=200
	local max_attempts_per_ship
	# Parse args
	if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
		bs_auto_place_help
		return 0
	fi
	if [[ "${1:-}" == "--verbose" ]]; then
		verbose=1
		shift || true
	fi
	if [[ "${1:-}" =~ ^[0-9]+$ ]]; then
		max_attempts_per_ship=$1
	else
		max_attempts_per_ship=$max_attempts_per_ship_default
	fi

	# Dependency check
	if ! _bs_auto__check_deps; then
		return 2
	fi

	local any_failed=0
	local ship

	# Iterate canonical ship list.
	while IFS= read -r ship; do
		if [[ -z "${ship}" ]]; then
			continue
		fi

		# Skip ships that already have placed segments (idempotent behavior)
		local rem
		if ! rem="$(bs_board_ship_remaining_segments "${ship}" 2>/dev/null || true)"; then
			rem=0
		fi
		if [[ "${rem}" != "0" ]]; then
			if ((verbose)); then
				printf "skipped:%s:remaining_segments=%s\n" "${ship}" "${rem}"
			fi
			continue
		fi

		local attempts=0
		local placed_ok=0
		local orient_idx r c orient length dr dc i

		# Per-ship bounded retry loop
		while ((attempts < max_attempts_per_ship)); do
			attempts=$((attempts + 1))

			# choose orientation uniformly: 0 -> h, 1 -> v
			orient_idx=$(bs_rng_int_range 0 1)
			if [[ "${orient_idx}" -eq 0 ]]; then
				orient="h"
			else
				orient="v"
			fi

			# choose start uniformly across full board to avoid sub-region bias
			r=$(bs_rng_int_range 0 $((BS_BOARD_SIZE - 1)))
			c=$(bs_rng_int_range 0 $((BS_BOARD_SIZE - 1)))

			# Validate proposed placement with placement validator (no state changes)
			# Use if/else to capture exit code safely without triggering set -e
			local vrc
			if bs_placement_validate "${r}" "${c}" "${orient}" "${ship}" >/dev/null 2>&1; then
				vrc=0
			else
				vrc=$?
			fi

			if ((vrc != 0)); then
				# Propagate certain validation errors as fatal so callers/tests can handle them.
				# For example: 2 = invalid/unknown ship type, 5 = invalid orientation.
				if ((vrc == 2 || vrc == 5)); then
					return $vrc
				fi
				# For other non-fatal validation failures (overlap/out-of-bounds) continue retrying.
			else
				# place segments; placement validator guarantees in-bounds and no overlap
				if ! length="$(bs_ship_length "${ship}" 2>/dev/null)"; then
					# unexpected: could not determine length
					printf "%s\n" "Internal error: could not determine length for ${ship}" >&2
					return 4
				fi

				if [[ ! "${length}" =~ ^[0-9]+$ ]]; then
					printf "%s\n" "Internal error: invalid length for ${ship}: ${length}" >&2
					return 4
				fi

				if ! _bs_auto__orient_to_delta "${orient}" >/dev/null 2>&1; then
					printf "%s\n" "Internal error: invalid orientation mapping: ${orient}" >&2
					return 4
				fi
				# read dr dc
				# Use here-string with command substitution to ensure function visibility and newline
				IFS=' ' read -r dr dc <<<"$(_bs_auto__orient_to_delta "${orient}")"

				local failed_segment=0
				for ((i = 0; i < length; i++)); do
					local rr=$((r + dr * i))
					local cc=$((c + dc * i))
					if ! bs_board_set_ship "${rr}" "${cc}" "${ship}" >/dev/null 2>&1; then
						failed_segment=1
						break
					fi
				done

				if ((failed_segment)); then
					# Partial placement is unexpected because placement validator passed.
					printf "%s\n" "Internal error: partial placement for ${ship} (attempt ${attempts})" >&2
					return 4
				fi

				# Success for this ship
				placed_ok=1
				if ((verbose)); then
					printf "placed:%s:length=%s:attempts=%d\n" "${ship}" "${length}" "${attempts}"
				fi
				break
			fi
			# else try again
		done

		if ((placed_ok == 0)); then
			any_failed=1
			if ((verbose)); then
				printf "failed_to_place:%s:attempts=%d\n" "${ship}" "${attempts}"
			fi
			# continue attempting to place other ships, but ultimately return failure
		fi

	done < <(bs_ship_list)

	if ((any_failed)); then
		return 3
	fi
	return 0
}
