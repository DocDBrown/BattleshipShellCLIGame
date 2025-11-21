#!/usr/bin/env bash
# board_state.sh - canonical in-memory Battleship board representation
# Library designed to be sourced by other modules. Provides constructors for an
# empty NxN grid, cell state operations and ship-segment bookkeeping. No
# rendering or placement logic is performed here.

set -o nounset
set -o pipefail

# Attempt to source ship_rules.sh if colocated; tolerate absence for isolated tests
_src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 || echo ".")"
if [[ -f "${_src_dir}/ship_rules.sh" ]]; then
	# shellcheck source=ship_rules.sh
	# shellcheck disable=SC1090
	source "${_src_dir}/ship_rules.sh"
fi

# Global board state (single board instance per process):
# BS_BOARD_SIZE - numeric size
# BS_BOARD_CELLS - associative array keyed as "r,c" -> unknown|ship|hit|miss
# BS_BOARD_SHIPMAP - associative array keyed "r,c" -> ship_type
# BS_BOARD_SHIP_HITS - associative array keyed ship_type -> integer hits
# BS_BOARD_SHIP_SEGMENTS - associative array keyed ship_type -> number segments placed

declare -g BS_BOARD_SIZE=0
declare -g -A BS_BOARD_CELLS=()
declare -g -A BS_BOARD_SHIPMAP=()
declare -g -A BS_BOARD_SHIP_HITS=()
declare -g -A BS_BOARD_SHIP_SEGMENTS=()

# Internal helpers
bs_board__valid_size() { [[ "$1" =~ ^[1-9][0-9]*$ ]]; }
bs_board__in_bounds() {
	local r="$1"
	local c="$2"
	((r >= 0 && c >= 0 && r < BS_BOARD_SIZE && c < BS_BOARD_SIZE))
}

# Public: create a new NxN board. Usage: bs_board_new <size>
bs_board_new() {
	local n="${1:-}"
	if ! bs_board__valid_size "$n"; then
		printf "Invalid board size: %s\n" "$n" >&2
		return 2
	fi
	BS_BOARD_SIZE=$n
	declare -g -A BS_BOARD_CELLS=()
	declare -g -A BS_BOARD_SHIPMAP=()
	declare -g -A BS_BOARD_SHIP_HITS=()
	declare -g -A BS_BOARD_SHIP_SEGMENTS=()
	local r c
	for ((r = 0; r < BS_BOARD_SIZE; r++)); do
		for ((c = 0; c < BS_BOARD_SIZE; c++)); do
			BS_BOARD_CELLS["$r,$c"]="unknown"
		done
	done
	return 0
}

# Public: get cell state. Prints one of: unknown, ship, hit, miss
bs_board_get_cell() {
	local r="${1:-}"
	local c="${2:-}"
	if ! [[ "$r" =~ ^[0-9]+$ && "$c" =~ ^[0-9]+$ ]]; then
		printf "Invalid coordinates\n" >&2
		return 2
	fi
	if ! bs_board__in_bounds "$r" "$c"; then
		printf "Out of bounds\n" >&2
		return 3
	fi
	printf "%s\n" "${BS_BOARD_CELLS["$r,$c"]:-unknown}"
}

# Public: set cell state explicitly (unknown|ship|hit|miss)
bs_board_set_cell() {
	local r="${1:-}"
	local c="${2:-}"
	local state="${3:-}"
	case "$state" in
	unknown | ship | hit | miss) ;;
	*)
		printf "Invalid state: %s\n" "$state" >&2
		return 2
		;;
	esac
	if ! [[ "$r" =~ ^[0-9]+$ && "$c" =~ ^[0-9]+$ ]]; then
		printf "Invalid coordinates\n" >&2
		return 3
	fi
	if ! bs_board__in_bounds "$r" "$c"; then
		printf "Out of bounds\n" >&2
		return 4
	fi
	BS_BOARD_CELLS["$r,$c"]="$state"
	return 0
}

# Public: associate a ship segment with a cell. Usage: bs_board_associate_ship_segment <r> <c> <ship_type>
# Sets cell state to 'ship', records mapping and increments the ship's placed-segment count.
bs_board_associate_ship_segment() {
	local r="${1:-}"
	local c="${2:-}"
	local raw="${3:-}"
	if ! [[ "$r" =~ ^[0-9]+$ && "$c" =~ ^[0-9]+$ ]]; then
		printf "Invalid coordinates\n" >&2
		return 2
	fi
	if ! bs_board__in_bounds "$r" "$c"; then
		printf "Out of bounds\n" >&2
		return 3
	fi
	local t
	if command -v bs_ship_length >/dev/null 2>&1; then
		# Validate via ship_rules if available; bs_ship_length prints length or errors
		if ! bs_ship_length "$raw" >/dev/null 2>&1; then
			printf "Invalid ship type: %s\n" "$raw" >&2
			return 4
		fi
		t="${raw,,}"
		if [[ ! "$t" =~ ^[a-z0-9_]+$ ]]; then
			printf "Invalid ship type: %s\n" "$raw" >&2
			return 4
		fi
	else
		t="${raw,,}"
	fi
	BS_BOARD_CELLS["$r,$c"]="ship"
	BS_BOARD_SHIPMAP["$r,$c"]="$t"
	if [[ -z "${BS_BOARD_SHIP_HITS[$t]:-}" ]]; then
		BS_BOARD_SHIP_HITS["$t"]=0
	fi
	local prev="${BS_BOARD_SHIP_SEGMENTS[$t]:-0}"
	BS_BOARD_SHIP_SEGMENTS["$t"]=$((prev + 1))
	return 0
}

# Public: register a shot at <r> <c>. Prints 'hit' or 'miss'. Idempotent: repeated shots do not double-count.
bs_board_register_shot() {
	local r="${1:-}"
	local c="${2:-}"
	if ! [[ "$r" =~ ^[0-9]+$ && "$c" =~ ^[0-9]+$ ]]; then
		printf "Invalid coordinates\n" >&2
		return 2
	fi
	if ! bs_board__in_bounds "$r" "$c"; then
		printf "Out of bounds\n" >&2
		return 3
	fi
	local key="$r,$c"
	local state="${BS_BOARD_CELLS[$key]:-unknown}"
	if [[ "$state" == "unknown" ]]; then
		BS_BOARD_CELLS[$key]="miss"
		printf "miss\n"
		return 0
	elif [[ "$state" == "miss" ]]; then
		printf "miss\n"
		return 0
	elif [[ "$state" == "ship" ]]; then
		# If not yet recorded as hit, record and increment ship hits
		BS_BOARD_CELLS[$key]="hit"
		local ship="${BS_BOARD_SHIPMAP[$key]}"
		if [[ -z "${BS_BOARD_SHIP_HITS[$ship]:-}" ]]; then
			BS_BOARD_SHIP_HITS[$ship]=1
		else
			BS_BOARD_SHIP_HITS[$ship]=$((BS_BOARD_SHIP_HITS[$ship] + 1))
		fi
		printf "hit\n"
		return 0
	elif [[ "$state" == "hit" ]]; then
		printf "hit\n"
		return 0
	else
		printf "Unknown cell state\n" >&2
		return 4
	fi
}

# Public: report hits recorded for a ship (prints integer)
bs_board_ship_hits() {
	local raw="${1:-}"
	if [[ -z "$raw" ]]; then
		printf "Invalid ship type\n" >&2
		return 2
	fi
	local t="${raw,,}"
	local val="${BS_BOARD_SHIP_HITS[$t]:-0}"
	printf "%d\n" "$val"
}

# Public: determine if a ship is sunk; delegates to bs_ship_is_sunk when available
bs_board_ship_is_sunk() {
	local raw="${1:-}"
	if [[ -z "$raw" ]]; then
		printf "Invalid ship type\n" >&2
		return 2
	fi
	local t="${raw,,}"
	local hits="${BS_BOARD_SHIP_HITS[$t]:-0}"
	if command -v bs_ship_is_sunk >/dev/null 2>&1; then
		bs_ship_is_sunk "$t" "$hits"
		return $?
	fi
	local length="${BS_BOARD_SHIP_SEGMENTS[$t]:-}"
	if [[ -n "$length" ]]; then
		if ((hits >= length)); then printf "true\n"; else printf "false\n"; fi
		return 0
	fi
	printf "Unknown ship: %s\n" "$t" >&2
	return 3
}

# Public: remaining segments for a ship; delegates to bs_ship_remaining_segments when available
bs_board_remaining_segments() {
	local raw="${1:-}"
	if [[ -z "$raw" ]]; then
		printf "Invalid ship type\n" >&2
		return 2
	fi
	local t="${raw,,}"
	local hits="${BS_BOARD_SHIP_HITS[$t]:-0}"
	if command -v bs_ship_remaining_segments >/dev/null 2>&1; then
		bs_ship_remaining_segments "$t" "$hits"
		return 0
	fi
	local length="${BS_BOARD_SHIP_SEGMENTS[$t]:-0}"
	local rem=$((length - hits))
	if ((rem < 0)); then rem=0; fi
	printf "%d\n" "$rem"
}

# Public: game over if all placed ship segments have been hit (true|false)
bs_board_game_over() {
	local total=0
	local k
	for k in "${!BS_BOARD_SHIP_SEGMENTS[@]}"; do
		total=$((total + ${BS_BOARD_SHIP_SEGMENTS[$k]}))
	done
	if ((total == 0)); then
		printf "false\n"
		return 0
	fi
	local hits=0
	for k in "${!BS_BOARD_SHIP_HITS[@]}"; do
		hits=$((hits + ${BS_BOARD_SHIP_HITS[$k]}))
	done
	if ((hits >= total)); then
		printf "true\n"
	else
		printf "false\n"
	fi
	return 0
}
