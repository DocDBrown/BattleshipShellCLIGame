#!/usr/bin/env bash
# ship_rules.sh - canonical ship definitions and helpers for battleship_shell_script
# Library designed to be sourced by other modules. Provides canonical fleet composition,
# length lookup, name lookup, simple validation and helper calculations.
# No logging or external I/O performed.

# Idempotent load guard: make it safe to source this file multiple times
if [[ ${BS_SHIP_RULES_LOADED:-0} -eq 1 ]]; then
	return 0
fi
BS_SHIP_RULES_LOADED=1

set -o nounset
set -o pipefail

# Canonical ship definitions (modifiable in one place for variants)
readonly BS_SHIP_ORDER=("carrier" "battleship" "cruiser" "submarine" "destroyer")
declare -A BS_SHIP_LENGTHS=(["carrier"]=5 ["battleship"]=4 ["cruiser"]=3 ["submarine"]=3 ["destroyer"]=2)
declare -A BS_SHIP_NAMES=(["carrier"]="Carrier" ["battleship"]="Battleship" ["cruiser"]="Cruiser" ["submarine"]="Submarine" ["destroyer"]="Destroyer")

# Internal: sanitize and normalize ship type (lowercase, allow a-z0-9_)
bs__sanitize_type() {
	local t="${1:-}"
	if [[ -z "$t" ]]; then
		return 1
	fi
	t="${t,,}"
	if [[ ! "$t" =~ ^[a-z0-9_]+$ ]]; then
		return 2
	fi
	printf "%s" "$t"
}

# Public: list all canonical ship types (one per line)
bs_ship_list() {
	printf "%s\n" "${BS_SHIP_ORDER[@]}"
}

# Public: get canonical length for a ship type. Prints length on success.
bs_ship_length() {
	local raw="${1:-}"
	local t
	t="$(bs__sanitize_type "$raw")" || {
		printf "Invalid ship type: %s\n" "$raw" >&2
		return 2
	}
	if [[ -n "${BS_SHIP_LENGTHS[$t]:-}" ]]; then
		printf "%d\n" "${BS_SHIP_LENGTHS[$t]}"
		return 0
	fi
	printf "Unknown ship type: %s\n" "$t" >&2
	return 3
}

# Public: get human-readable name for display
bs_ship_name() {
	local raw="${1:-}"
	local t
	t="$(bs__sanitize_type "$raw")" || {
		printf "Invalid ship type: %s\n" "$raw" >&2
		return 2
	}
	if [[ -n "${BS_SHIP_NAMES[$t]:-}" ]]; then
		printf "%s\n" "${BS_SHIP_NAMES[$t]}"
		return 0
	fi
	printf "%s\n" "$t"
}

# Public: calculate total number of ship segments in the canonical fleet
bs_total_segments() {
	local sum=0
	local k
	for k in "${BS_SHIP_ORDER[@]}"; do
		sum=$((sum + ${BS_SHIP_LENGTHS[$k]}))
	done
	printf "%d\n" "$sum"
}

# Public: validate fleet composition and lengths; returns 0 on success
bs_validate_fleet() {
	local k
	declare -A seen=()
	for k in "${BS_SHIP_ORDER[@]}"; do
		if [[ -z "${BS_SHIP_LENGTHS[$k]:-}" ]]; then
			printf "Missing length for ship: %s\n" "$k" >&2
			return 2
		fi
		if [[ ! "${BS_SHIP_LENGTHS[$k]}" =~ ^[1-9][0-9]*$ ]]; then
			printf "Invalid length for ship %s: %s\n" "$k" "${BS_SHIP_LENGTHS[$k]}" >&2
			return 3
		fi
		if [[ -n "${seen[$k]:-}" ]]; then
			printf "Duplicate ship in order: %s\n" "$k" >&2
			return 4
		fi
		seen[$k]=1
	done
	return 0
}

# Public: determine if a ship is sunk given number of hits; prints "true" or "false"
bs_ship_is_sunk() {
	local raw="${1:-}"
	local hits="${2:-}"
	local t
	t="$(bs__sanitize_type "$raw")" || {
		printf "Invalid ship type: %s\n" "$raw" >&2
		return 2
	}
	if [[ ! "$hits" =~ ^[0-9]+$ ]]; then
		printf "Invalid hits value: %s\n" "$hits" >&2
		return 3
	fi
	local length="${BS_SHIP_LENGTHS[$t]:-}"
	if [[ -z "$length" ]]; then
		printf "Unknown ship type: %s\n" "$t" >&2
		return 4
	fi
	if ((hits >= length)); then
		printf "true\n"
	else
		printf "false\n"
	fi
	return 0
}

# Public: remaining segments for a ship given hits (non-negative integer)
bs_ship_remaining_segments() {
	local raw="${1:-}"
	local hits="${2:-}"
	local t
	t="$(bs__sanitize_type "$raw")" || {
		printf "Invalid ship type: %s\n" "$raw" >&2
		return 2
	}
	if [[ ! "$hits" =~ ^[0-9]+$ ]]; then
		printf "Invalid hits value: %s\n" "$hits" >&2
		return 3
	fi
	local length="${BS_SHIP_LENGTHS[$t]:-}"
	if [[ -z "$length" ]]; then
		printf "Unknown ship type: %s\n" "$t" >&2
		return 4
	fi
	local rem=$((length - hits))
	if ((rem < 0)); then rem=0; fi
	printf "%d\n" "$rem"
}
