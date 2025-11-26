#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# placement_validator.sh - library for validating proposed ship placements
# Purpose: Provide deterministic, idempotent validation of a proposed ship placement
# against an in-memory board representation and canonical ship rules.
# Usage (library): source this file, then call:
#   bs_placement_validate START_R START_C ORIENTATION SHIP_TYPE
# Where START_R and START_C are 0-based non-negative integers, ORIENTATION is
# one of: h, horizontal, v, vertical, and SHIP_TYPE is a canonical ship id
# (e.g. "carrier"). The caller must source ship_rules.sh and board_state.sh
# before invoking these functions. This library performs no I/O other than
# single-line diagnostics on failure and does not call exit().
# Return codes:
#  0  success (placement valid)
#  1  invalid usage or malformed arguments
#  2  invalid/unknown ship type (ship_rules failure)
#  3  placement would be out of bounds
#  4  placement overlaps an existing ship segment
#  5  invalid orientation
#  6  missing dependency (caller did not source required modules)

# Internal: normalize orientation into delta row/col. Sets globals:
# _BS_PL_DR and _BS_PL_DC on success. Returns 0 on success, non-zero on error.
_bs_placement__normalize_orientation() {
	local raw="${1:-}"
	case "${raw,,}" in
	h | horizontal)
		_BS_PL_DR=0
		_BS_PL_DC=1
		return 0
		;;
	v | vertical)
		_BS_PL_DR=1
		_BS_PL_DC=0
		return 0
		;;
	*)
		return 1
		;;
	esac
}

# Public: validate a proposed placement. Does not modify board state.
# Arguments: START_R START_C ORIENTATION SHIP_TYPE
bs_placement_validate() {
	local start_r="${1:-}" start_c="${2:-}" orient="${3:-}" ship="${4:-}"

	if [[ -z "${start_r}" || -z "${start_c}" || -z "${orient}" || -z "${ship}" ]]; then
		printf "Usage: bs_placement_validate START_R START_C ORIENTATION SHIP_TYPE\n" >&2
		return 1
	fi

	# Ensure required functions are available; caller must source dependencies.
	if ! command -v bs_ship_length >/dev/null 2>&1; then
		printf "Dependency missing: bs_ship_length (source ship_rules.sh)\n" >&2
		return 6
	fi
	if ! command -v bs_board_get_state >/dev/null 2>&1 || ! command -v bs_board_get_owner >/dev/null 2>&1; then
		printf "Dependency missing: board state functions (source board_state.sh)\n" >&2
		return 6
	fi

	# Validate numeric 0-based coordinates
	if [[ ! "${start_r}" =~ ^[0-9]+$ ]] || [[ ! "${start_c}" =~ ^[0-9]+$ ]]; then
		printf "Invalid coordinates: %s %s\n" "${start_r}" "${start_c}" >&2
		return 1
	fi

	# Resolve canonical length for ship type
	local length
	if ! length="$(bs_ship_length "${ship}" 2>/dev/null)"; then
		printf "Invalid ship type: %s\n" "${ship}" >&2
		return 2
	fi
	if [[ ! "${length}" =~ ^[0-9]+$ ]]; then
		printf "Invalid ship length returned for %s: %s\n" "${ship}" "${length}" >&2
		return 2
	fi

	# Normalize orientation
	if ! _bs_placement__normalize_orientation "${orient}"; then
		printf "Invalid orientation: %s (allowed: h, horizontal, v, vertical)\n" "${orient}" >&2
		return 5
	fi

	local i r c state owner
	for ((i = 0; i < length; i++)); do
		r=$((start_r + _BS_PL_DR * i))
		c=$((start_c + _BS_PL_DC * i))

		# bs_board_get_state prints the state on success, and returns non-zero on out-of-bounds.
		if ! state="$(bs_board_get_state "${r}" "${c}" 2>/dev/null)"; then
			printf "Ship would be out of bounds at: %s %s\n" "${r}" "${c}" >&2
			return 3
		fi

		if [[ "${state}" == "ship" ]]; then
			owner="$(bs_board_get_owner "${r}" "${c}" 2>/dev/null || true)"
			if [[ -n "${owner}" ]]; then
				printf "Overlap with existing ship '%s' at %s %s\n" "${owner}" "${r}" "${c}" >&2
			else
				printf "Overlap with existing ship at %s %s\n" "${r}" "${c}" >&2
			fi
			return 4
		fi
	done

	# All checks passed
	return 0
}
