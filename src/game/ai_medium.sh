#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# bs_ai_medium.sh - medium difficulty AI for Battleship (library)
# Purpose: Provide a non-cheating medium AI that fires randomly until a hit,
# then probes adjacent cells (up/down/left/right) in a local "hunt" mode.
# Usage: source this file and call bs_ai_medium_init [seed]; then repeatedly
# call bs_ai_medium_next_shot to obtain a target (prints "r c" zero-based)
# and call bs_ai_medium_notify_result r c result where result is hit|miss|sunk.
# This file defines functions only and performs no actions when sourced.
# Dependencies: board_state.sh (bs_board_get_state, bs_board_in_bounds, BS_BOARD_SIZE)
#               rng.sh (bs_rng_init_from_seed, bs_rng_init_auto, bs_rng_int_range)
# This library treats global state as process-local and is idempotent where sensible.

# Initialize the AI. Accepts optional numeric seed to initialize deterministic RNG.
# Returns: 0 on success, non-zero on error.
bs_ai_medium_init() {
  local seed="${1:-}"
  if ! type bs_board_get_state >/dev/null 2>&1; then
    printf "bs_ai_medium: missing dependency bs_board_get_state\n" >&2
    return 2
  fi
  if ! type bs_board_in_bounds >/dev/null 2>&1; then
    printf "bs_ai_medium: missing dependency bs_board_in_bounds\n" >&2
    return 2
  fi
  if ! type bs_rng_int_range >/dev/null 2>&1; then
    printf "bs_ai_medium: missing dependency bs_rng_int_range\n" >&2
    return 2
  fi
  if [[ -n "${seed:-}" ]]; then
    bs_rng_init_from_seed "$seed" || return 3
  else
    bs_rng_init_auto || return 3
  fi
  BS_AI_MEDIUM_HUNT_QUEUE=()
  BS_AI_MEDIUM_HUNT_SEEN=()
  return 0
}

# Internal: check if a key ("r_c") is already marked seen
bs_ai_medium__seen_contains() {
  local key="$1"
  local s
  for s in "${BS_AI_MEDIUM_HUNT_SEEN[@]:-}"; do
    if [[ "$s" == "$key" ]]; then
      return 0
    fi
  done
  return 1
}

# Internal: add a key to the hunt queue if not seen
bs_ai_medium__add_to_queue() {
  local key="$1"
  bs_ai_medium__seen_contains "$key" && return 0
  BS_AI_MEDIUM_HUNT_QUEUE+=("$key")
  BS_AI_MEDIUM_HUNT_SEEN+=("$key")
  return 0
}

# Internal: enqueue unknown orthogonal neighbors of a coordinate (zero-based)
bs_ai_medium__add_neighbors() {
  local r="$1" c="$2"
  local nr nc state
  # up
  nr=$((r - 1)); nc=$c
  if ((nr >= 0 && nr < BS_BOARD_SIZE && nc >= 0 && nc < BS_BOARD_SIZE)); then
    if state=$(bs_board_get_state "$nr" "$nc" 2>/dev/null); then
      if [[ "$state" == "unknown" ]]; then
        bs_ai_medium__add_to_queue "${nr}_${nc}"
      fi
    fi
  fi
  # down
  nr=$((r + 1)); nc=$c
  if ((nr >= 0 && nr < BS_BOARD_SIZE && nc >= 0 && nc < BS_BOARD_SIZE)); then
    if state=$(bs_board_get_state "$nr" "$nc" 2>/dev/null); then
      if [[ "$state" == "unknown" ]]; then
        bs_ai_medium__add_to_queue "${nr}_${nc}"
      fi
    fi
  fi
  # left
  nr=$r; nc=$((c - 1))
  if ((nr >= 0 && nr < BS_BOARD_SIZE && nc >= 0 && nc < BS_BOARD_SIZE)); then
    if state=$(bs_board_get_state "$nr" "$nc" 2>/dev/null); then
      if [[ "$state" == "unknown" ]]; then
        bs_ai_medium__add_to_queue "${nr}_${nc}"
      fi
    fi
  fi
  # right
  nr=$r; nc=$((c + 1))
  if ((nr >= 0 && nr < BS_BOARD_SIZE && nc >= 0 && nc < BS_BOARD_SIZE)); then
    if state=$(bs_board_get_state "$nr" "$nc" 2>/dev/null); then
      if [[ "$state" == "unknown" ]]; then
        bs_ai_medium__add_to_queue "${nr}_${nc}"
      fi
    fi
  fi
  return 0
}

# Notify the AI of the result of a shot. r c are zero-based integers.
# result must be one of: hit, miss, sunk
# Idempotent for repeated identical notifications.
bs_ai_medium_notify_result() {
  local raw_r="${1:-}" raw_c="${2:-}" result="${3:-}"
  if [[ -z "$raw_r" || -z "$raw_c" || -z "$result" ]]; then
    printf "bs_ai_medium_notify_result: requires r c result\n" >&2
    return 2
  fi
  if [[ ! "$raw_r" =~ ^[0-9]+$ || ! "$raw_c" =~ ^[0-9]+$ ]]; then
    printf "bs_ai_medium_notify_result: r and c must be non-negative integers\n" >&2
    return 3
  fi
  if [[ "$result" != "hit" && "$result" != "miss" && "$result" != "sunk" ]]; then
    printf "bs_ai_medium_notify_result: result must be one of hit|miss|sunk\n" >&2
    return 4
  fi
  local r="$raw_r" c="$raw_c"
  if [[ "$result" == "hit" ]]; then
    bs_ai_medium__add_neighbors "$r" "$c"
  elif [[ "$result" == "sunk" ]]; then
    # Clear local hunt context; sunk may remove ambiguity for ship placement
    BS_AI_MEDIUM_HUNT_QUEUE=()
    BS_AI_MEDIUM_HUNT_SEEN=()
  fi
  return 0
}

# Select the next shot. Prints "r c" (zero-based) to stdout. Returns 0 on success,
# 1 if no available targets.
bs_ai_medium_next_shot() {
  local coord r c state chosen chosen_idx candidates_len
  # Try hunt queue first
  while (( ${#BS_AI_MEDIUM_HUNT_QUEUE[@]:-0} > 0 )); do
    coord="${BS_AI_MEDIUM_HUNT_QUEUE[0]}"
    BS_AI_MEDIUM_HUNT_QUEUE=( "${BS_AI_MEDIUM_HUNT_QUEUE[@]:1}" )
    r="${coord%%_*}"
    c="${coord#*_}"
    if [[ ! "$r" =~ ^[0-9]+$ || ! "$c" =~ ^[0-9]+$ ]]; then
      continue
    fi
    if state=$(bs_board_get_state "$r" "$c" 2>/dev/null); then
      if [[ "$state" == "unknown" ]]; then
        printf "%d %d\n" "$r" "$c"
        return 0
      fi
    fi
  done

  # Otherwise choose a random unknown cell
  local candidates=()
  local rr cc
  for ((rr=0; rr<BS_BOARD_SIZE; rr++)); do
    for ((cc=0; cc<BS_BOARD_SIZE; cc++)); do
      if state=$(bs_board_get_state "$rr" "$cc" 2>/dev/null); then
        if [[ "$state" == "unknown" ]]; then
          candidates+=("${rr}_${cc}")
        fi
      fi
    done
  done

  candidates_len=${#candidates[@]:-0}
  if ((candidates_len == 0)); then
    return 1
  fi
  chosen_idx=$(bs_rng_int_range 0 $((candidates_len - 1)))
  chosen_idx="${chosen_idx##*$'\n'}"
  chosen="${candidates[chosen_idx]}"
  r="${chosen%%_*}"
  c="${chosen#*_}"
  printf "%d %d\n" "$r" "$c"
  return 0
}

# Return the number of queued coordinates in hunt mode (integer printed)
bs_ai_medium_get_queue_len() {
  printf "%d\n" "${#BS_AI_MEDIUM_HUNT_QUEUE[@]:-0}"
  return 0
}
