#!/usr/bin/env bash
# board_state.sh - canonical in-memory representation of a Battleship board
# Provides constructors for an empty NxN grid and operations to query/update
# cell states and ownership. Deterministic and idempotent. No external I/O
# other than simple error messages on stderr for invalid usage.

# COMPATIBILITY NOTE: Refactored for Bash 3.2+ (removes declare -A).
# USAGE NOTE: Internal logic uses global return variables to avoid subshell scoping issues.

set -o nounset
set -o pipefail

# Try to source ship_rules.sh if colocated to reuse canonical ship names/lengths
BS__THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
if [[ -f "${BS__THIS_DIR}/ship_rules.sh" ]]; then
  # shellcheck disable=SC1091
  . "${BS__THIS_DIR}/ship_rules.sh"
fi

# Global State Variables
BS_BOARD_SIZE=0
BS_BOARD_TOTAL_SEGMENTS=0
BS_BOARD_REMAINING_SEGMENTS=0

# Internal list of ships to help cleanup dynamic variables
_BS_BOARD_SEEN_SHIPS=""

# Internal Return Variables (to avoid subshells in internal calls)
_BS_RET_R=0
_BS_RET_C=0

# Internal helper: sanitize a string for use in a variable name
_bs_board__sanitize_for_var() {
  printf "%s" "${1//[^a-zA-Z0-9]/_}"
}

# Internal: normalize coordinates to 1..N
# Sets _BS_RET_R and _BS_RET_C globals. Returns 0 on success, non-zero on error.
bs_board__normalize_coord() {
  local raw_r="${1:-}"
  local raw_c="${2:-}"

  if [[ -z "$raw_r" || -z "$raw_c" ]]; then
    return 1
  fi

  # ensure numeric (non-negative integers)
  if [[ ! "$raw_r" =~ ^[0-9]+$ ]] || [[ ! "$raw_c" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  # Convert 0-based input to 1-based internal representation
  local r=$((raw_r + 1))
  local c=$((raw_c + 1))

  # BS_BOARD_SIZE is accessed directly (no subshell)
  if (( r < 1 || r > BS_BOARD_SIZE || c < 1 || c > BS_BOARD_SIZE )); then
    return 2
  fi

  _BS_RET_R=$r
  _BS_RET_C=$c
  return 0
}

# Create a new empty board of size N (N must be positive integer). Default N=10 when omitted.
bs_board_new() {
  local n=${1:-10}
  # Portable regex check
  if [[ ! "$n" =~ ^[1-9][0-9]*$ ]]; then
    printf "Invalid board size: %s\n" "$n" >&2
    return 1
  fi

  BS_BOARD_SIZE=$n
  BS_BOARD_TOTAL_SEGMENTS=0
  BS_BOARD_REMAINING_SEGMENTS=0

  # Clean up ship-specific variables from any previous game state
  local ship sanitized_ship
  for ship in $_BS_BOARD_SEEN_SHIPS; do
    sanitized_ship=$(_bs_board__sanitize_for_var "$ship")
    unset "BS_BOARD_SHIP_SEGMENTS_${sanitized_ship}" || true
    unset "BS_BOARD_HITS_BY_SHIP_${sanitized_ship}" || true
  done
  _BS_BOARD_SEEN_SHIPS=""

  # Initialize cells to unknown using dynamic variables
  local r c key var_name_state var_name_owner
  for (( r = 1; r <= BS_BOARD_SIZE; r++ )); do
    for (( c = 1; c <= BS_BOARD_SIZE; c++ )); do
      key="${r}_${c}"
      var_name_state="BS_BOARD_CELLSTATE_${key}"
      var_name_owner="BS_BOARD_OWNER_${key}"
      eval "${var_name_state}='unknown'"
      eval "${var_name_owner}=''"
    done
  done

  return 0
}

# Check if coordinates are within bounds; prints normalized coords on success
bs_board_in_bounds() {
  bs_board__normalize_coord "$1" "$2" || return 1
  printf "%d %d" "$_BS_RET_R" "$_BS_RET_C"
}

# Get cell state: prints state on success
bs_board_get_state() {
  bs_board__normalize_coord "$1" "$2" || {
    printf "Coordinates out of bounds: %s %s\n" "$1" "$2" >&2
    return 2
  }
  
  local key="${_BS_RET_R}_${_BS_RET_C}"
  local var_name="BS_BOARD_CELLSTATE_${key}"
  
  # Indirection compatible with Bash 3.2+
  if [[ -n "${!var_name+x}" ]]; then
    printf "%s" "${!var_name}"
  else
    printf "unknown"
  fi
}

# Get cell owner (sanitized ship type) or empty string
bs_board_get_owner() {
  bs_board__normalize_coord "$1" "$2" || {
    printf "Coordinates out of bounds: %s %s\n" "$1" "$2" >&2
    return 2
  }

  local key="${_BS_RET_R}_${_BS_RET_C}"
  local var_name="BS_BOARD_OWNER_${key}"
  
  if [[ -n "${!var_name+x}" ]]; then
    printf "%s" "${!var_name}"
  else
    printf ""
  fi
}

# Internal: register that a ship has an additional placed segment
bs_board__inc_ship_segment() {
  local ship="$1"
  # Add ship to seen list if not already there
  if [[ ! " $_BS_BOARD_SEEN_SHIPS " =~ " ${ship} " ]]; then
    _BS_BOARD_SEEN_SHIPS="${_BS_BOARD_SEEN_SHIPS} ${ship}"
  fi

  local sanitized_ship=$(_bs_board__sanitize_for_var "$ship")
  local seg_var="BS_BOARD_SHIP_SEGMENTS_${sanitized_ship}"
  local cur_segs="${!seg_var:-0}"
  
  eval "${seg_var}=$(( cur_segs + 1 ))"
  BS_BOARD_TOTAL_SEGMENTS=$(( BS_BOARD_TOTAL_SEGMENTS + 1 ))
  BS_BOARD_REMAINING_SEGMENTS=$(( BS_BOARD_REMAINING_SEGMENTS + 1 ))
}

# Place a ship segment at coordinates; idempotent for same ship
bs_board_set_ship() {
  local raw_r="$1" raw_c="$2" raw_ship="${3:-}"
  if [[ -z "$raw_ship" ]]; then
    printf "Missing ship type\n" >&2
    return 2
  fi

  local ship
  if type bs__sanitize_type >/dev/null 2>&1; then
    ship="$(bs__sanitize_type "$raw_ship")" || {
      printf "Invalid ship type: %s\n" "$raw_ship" >&2
      return 3
    }
  else
    ship="${raw_ship,,}"
  fi

  bs_board__normalize_coord "$raw_r" "$raw_c" || {
    printf "Coordinates out of bounds: %s %s\n" "$raw_r" "$raw_c" >&2
    return 4
  }

  local key="${_BS_RET_R}_${_BS_RET_C}"
  local state_var="BS_BOARD_CELLSTATE_${key}"
  local owner_var="BS_BOARD_OWNER_${key}"

  local cur_state="${!state_var:-unknown}"
  local cur_owner="${!owner_var:-}"

  # Idempotent check
  if [[ "$cur_state" == "ship" && "$cur_owner" == "$ship" ]]; then
    return 0
  fi

  # Decrement previous owner if overwriting
  if [[ "$cur_state" == "ship" && -n "$cur_owner" && "$cur_owner" != "$ship" ]]; then
    local sanitized_cur_owner=$(_bs_board__sanitize_for_var "$cur_owner")
    local seg_var="BS_BOARD_SHIP_SEGMENTS_${sanitized_cur_owner}"
    local cur_segs="${!seg_var:-0}"
    eval "${seg_var}=$(( cur_segs - 1 ))"
    
    BS_BOARD_TOTAL_SEGMENTS=$(( BS_BOARD_TOTAL_SEGMENTS - 1 ))
    BS_BOARD_REMAINING_SEGMENTS=$(( BS_BOARD_REMAINING_SEGMENTS - 1 ))
    if (( BS_BOARD_REMAINING_SEGMENTS < 0 )); then
      BS_BOARD_REMAINING_SEGMENTS=0
    fi
  fi

  bs_board__inc_ship_segment "$ship"

  eval "${state_var}='ship'"
  eval "${owner_var}='${ship}'"
  return 0
}

# Mark a coordinate as a hit.
bs_board_set_hit() {
  local raw_r="$1" raw_c="$2"
  
  bs_board__normalize_coord "$raw_r" "$raw_c" || {
    printf "Coordinates out of bounds: %s %s\n" "$raw_r" "$raw_c" >&2
    return 2
  }

  local key="${_BS_RET_R}_${_BS_RET_C}"
  local state_var="BS_BOARD_CELLSTATE_${key}"
  local owner_var="BS_BOARD_OWNER_${key}"

  local cur_state="${!state_var:-unknown}"
  local owner="${!owner_var:-}"

  if [[ "$cur_state" == "hit" ]]; then
    return 0
  fi

  eval "${state_var}='hit'"

  if [[ -n "$owner" && "$cur_state" == "ship" ]]; then
    local sanitized_owner=$(_bs_board__sanitize_for_var "$owner")
    local hit_var="BS_BOARD_HITS_BY_SHIP_${sanitized_owner}"
    local cur_hits="${!hit_var:-0}"
    eval "${hit_var}=$(( cur_hits + 1 ))"
    
    BS_BOARD_REMAINING_SEGMENTS=$(( BS_BOARD_REMAINING_SEGMENTS - 1 ))
    if (( BS_BOARD_REMAINING_SEGMENTS < 0 )); then
      BS_BOARD_REMAINING_SEGMENTS=0
    fi
  fi

  return 0
}

# Mark a coordinate as a miss and ensure owner is unset for that cell
bs_board_set_miss() {
  local raw_r="$1" raw_c="$2"
  
  bs_board__normalize_coord "$raw_r" "$raw_c" || {
    printf "Coordinates out of bounds: %s %s\n" "$raw_r" "$raw_c" >&2
    return 2
  }

  local key="${_BS_RET_R}_${_BS_RET_C}"
  eval "BS_BOARD_CELLSTATE_${key}='miss'"
  eval "BS_BOARD_OWNER_${key}=''"
  return 0
}

# Return total remaining segments across the board
bs_board_total_remaining_segments() {
  printf "%d" "$BS_BOARD_REMAINING_SEGMENTS"
}

# Determine if a specific ship (sanitized) is sunk: true/false printed
bs_board_ship_is_sunk() {
  local raw_ship="${1:-}"
  if [[ -z "$raw_ship" ]]; then
    printf "Invalid ship type: %s\n" "$raw_ship" >&2
    return 2
  fi

  local ship
  if type bs__sanitize_type >/dev/null 2>&1; then
    ship="$(bs__sanitize_type "$raw_ship")" || {
      printf "Invalid ship type: %s\n" "$raw_ship" >&2
      return 3
    }
  else
    ship="${raw_ship,,}"
  fi

  local sanitized_ship=$(_bs_board__sanitize_for_var "$ship")
  local placed_var="BS_BOARD_SHIP_SEGMENTS_${sanitized_ship}"
  local hits_var="BS_BOARD_HITS_BY_SHIP_${sanitized_ship}"
  local placed="${!placed_var:-0}"
  local hits="${!hits_var:-0}"

  if (( placed == 0 )); then
    printf "false"
    return 0
  fi

  if (( hits >= placed )); then
    printf "true"
  else
    printf "false"
  fi
  return 0
}

# Determine if all ship segments are destroyed (win condition)
bs_board_is_win() {
  if (( BS_BOARD_REMAINING_SEGMENTS == 0 )); then
    printf "true"
    return 0
  fi
  printf "false"
  return 0
}

# Utility: remaining segments for a given ship (placed - hits, floored at 0)
bs_board_ship_remaining_segments() {
  local raw_ship="${1:-}"
  if [[ -z "$raw_ship" ]]; then
    printf "Invalid ship type: %s\n" "$raw_ship" >&2
    return 2
  fi

  local ship
  if type bs__sanitize_type >/dev/null 2>&1; then
    ship="$(bs__sanitize_type "$raw_ship")" || {
      printf "Invalid ship type: %s\n" "$raw_ship" >&2
      return 3
    }
  else
    ship="${raw_ship,,}"
  fi

  local sanitized_ship=$(_bs_board__sanitize_for_var "$ship")
  local placed_var="BS_BOARD_SHIP_SEGMENTS_${sanitized_ship}"
  local hits_var="BS_BOARD_HITS_BY_SHIP_${sanitized_ship}"
  local placed="${!placed_var:-0}"
  local hits="${!hits_var:-0}"
  local rem=$(( placed - hits ))
  if (( rem < 0 )); then
    rem=0
  fi
  printf "%d" "$rem"
  return 0
}