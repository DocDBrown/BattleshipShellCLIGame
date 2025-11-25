#!/usr/bin/env bats

# Integration with a richer board_state / RNG, plus idempotence & exhaustion

setup() {
	BS_TMP_DIR="$(mktemp -d)"
	export BS_TMP_DIR

	# rng.sh with real seeding and uniform int_range
	cat >"${BS_TMP_DIR}/rng.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

BS_RNG_MODE="auto"
BS_RNG_STATE=0
BS_RNG_MODULO=4294967296

bs_rng_init_from_seed() {
  local seed=$1
  BS_RNG_MODE="lcg"
  BS_RNG_STATE=$((seed & 0xFFFFFFFF))
}

bs_rng_lcg_next() {
  BS_RNG_STATE=$(((BS_RNG_STATE * 1664525 + 1013904223) & 0xFFFFFFFF))
  printf "%u\n" "$BS_RNG_STATE"
}

bs_rng_get_uint32() {
  if [ "$BS_RNG_MODE" = "lcg" ]; then
    bs_rng_lcg_next
    return 0
  fi

  # Fallback: /dev/urandom
  od -An -tu4 -N4 /dev/urandom | tr -d ' \n'
}

bs_rng_int_range() {
  local min=$1
  local max=$2

  if [ "$min" -gt "$max" ]; then
    return 2
  fi

  local span=$((max - min + 1))

  if [ "$span" -le 0 ]; then
    printf "%s\n" "$min"
    return 0
  fi

  if [ "$span" -eq 1 ]; then
    printf "%s\n" "$min"
    return 0
  fi

  local threshold=$(((BS_RNG_MODULO / span) * span))

  while :; do
    local v
    v="$(bs_rng_get_uint32)"
    [ -n "$v" ] || continue
    if [ "$v" -lt "$threshold" ]; then
      local r=$((v % span))
      printf "%d\n" "$((min + r))"
      return 0
    fi
  done
}
EOF

	# Minimal but usable board_state.sh – only what these tests need:
	cat >"${BS_TMP_DIR}/board_state.sh" <<'EOF'
#!/usr/bin/env bash
set -o nounset
set -o pipefail

BS_BOARD_SIZE=0
BS_BOARD_TOTAL_SEGMENTS=0
BS_BOARD_REMAINING_SEGMENTS=0

# Simple board: track ships & hits with assoc variables.
bs_board_new() {
  local n=${1:-10}
  BS_BOARD_SIZE=$n
  BS_BOARD_TOTAL_SEGMENTS=0
  BS_BOARD_REMAINING_SEGMENTS=0
}

bs_board_set_ship() {
  local r=$1
  local c=$2
  local ship=${3:-}

  if [ -z "$ship" ]; then
    printf "Invalid ship type\n" >&2
    return 2
  fi

  if (( r < 0 || c < 0 || r >= BS_BOARD_SIZE || c >= BS_BOARD_SIZE )); then
    printf "Coordinates out of bounds: %s %s\n" "$r" "$c" >&2
    return 4
  fi

  local rr=$((r + 1))
  local cc=$((c + 1))
  local key="${rr}_${cc}"

  eval "BS_BOARD_CELLSTATE_${key}='ship'"
  eval "BS_BOARD_OWNER_${key}='${ship}'"

  BS_BOARD_TOTAL_SEGMENTS=$((BS_BOARD_TOTAL_SEGMENTS + 1))
  BS_BOARD_REMAINING_SEGMENTS=$((BS_BOARD_REMAINING_SEGMENTS + 1))
}

bs_board_set_hit() {
  local r=$1
  local c=$2

  if (( r < 0 || c < 0 || r >= BS_BOARD_SIZE || c >= BS_BOARD_SIZE )); then
    printf "Coordinates out of bounds: %s %s\n" "$r" "$c" >&2
    return 2
  fi

  local rr=$((r + 1))
  local cc=$((c + 1))
  local key="${rr}_${cc}"

  eval "BS_BOARD_CELLSTATE_${key}='hit'"
  return 0
}

bs_board_set_miss() {
  local r=$1
  local c=$2

  if (( r < 0 || c < 0 || r >= BS_BOARD_SIZE || c >= BS_BOARD_SIZE )); then
    printf "Coordinates out of bounds: %s %s\n" "$r" "$c" >&2
    return 2
  fi

  local rr=$((r + 1))
  local cc=$((c + 1))
  local key="${rr}_${cc}"

  eval "BS_BOARD_CELLSTATE_${key}='miss'"
  return 0
}
EOF

	cp "${BATS_TEST_DIRNAME}/ai_hard.sh" "${BS_TMP_DIR}/ai_hard.sh"

	# shellcheck disable=SC1091
	source "${BS_TMP_DIR}/rng.sh"
	# shellcheck disable=SC1091
	source "${BS_TMP_DIR}/board_state.sh"
	# shellcheck disable=SC1091
	source "${BS_TMP_DIR}/ai_hard.sh"

	bs_rng_init_from_seed 123
	bs_board_new 5
	bs_ai_hard_init
}

teardown() {
	if [ -n "${BS_TMP_DIR:-}" ]; then
		rm -rf "${BS_TMP_DIR}"
	fi
}

@test "unit_ai_hard_does_not_read_hidden_layout_and_uses_only_reported_outcomes" {
	# Place a ship, but AI must not peek at layout
	bs_board_set_ship 0 0 destroyer

	local visited_before=${BS_AI_HARD_VISITED_1_1:-}
	[ -z "$visited_before" ]

	local shot
	shot="$(bs_ai_hard_choose_shot)"
	[ -n "$shot" ]

	local r c
	r=${shot%% *}
	c=${shot##* }

	[ "$r" -ge 1 ]
	[ "$r" -le "$BS_BOARD_SIZE" ]
	[ "$c" -ge 1 ]
	[ "$c" -le "$BS_BOARD_SIZE" ]

	bs_ai_hard_notify_result "$r" "$c" "miss"
	local visited_after_var="BS_AI_HARD_VISITED_${r}_${c}"
	[ "${!visited_after_var:-}" = "1" ]
}

@test "unit_ai_hard_is_idempotent_when_receiving_duplicate_outcome_reports" {
	bs_rng_init_from_seed 42
	bs_board_new 4
	bs_ai_hard_init

	local shot
	shot="$(bs_ai_hard_choose_shot)"
	local r=${shot%% *}
	local c=${shot##* }

	bs_ai_hard_notify_result "$r" "$c" "hit"
	local queue_len1=${#BS_AI_HARD_TARGET_QUEUE_R[@]}
	local hits_len1=${#BS_AI_HARD_HITS_R[@]}

	# Repeat same report
	bs_ai_hard_notify_result "$r" "$c" "hit"
	local queue_len2=${#BS_AI_HARD_TARGET_QUEUE_R[@]}
	local hits_len2=${#BS_AI_HARD_HITS_R[@]}

	[ "$queue_len1" -eq "$queue_len2" ]
	[ "$hits_len1" -eq "$hits_len2" ]
}

@test "unit_ai_hard_prefers_continuing_existing_target_hunts_over_random_scouting" {
	bs_rng_init_from_seed 7
	bs_board_new 4
	bs_ai_hard_init

	bs_ai_hard_notify_result 2 2 "hit"

	local next
	next="$(bs_ai_hard_choose_shot)"
	local nr=${next%% *}
	local nc=${next##* }

	[ "$nr" -ge 1 ]
	[ "$nr" -le "$BS_BOARD_SIZE" ]
	[ "$nc" -ge 1 ]
	[ "$nc" -le "$BS_BOARD_SIZE" ]

	# Neighbor check: one of 4 orthogonal neighbors
	[ $((nr == 1 && nc == 2 || nr == 3 && nc == 2 || nr == 2 && nc == 1 || nr == 2 && nc == 3)) -eq 1 ]
}

@test "unit_ai_hard_selects_among_multiple_partial_hunts_consistently_using_priority_and_rng_ties" {
	bs_rng_init_from_seed 99
	bs_board_new 5
	bs_ai_hard_init

	# Two separate hits (no clear orientation)
	bs_ai_hard_notify_result 2 2 "hit"
	bs_ai_hard_notify_result 4 4 "hit"

	# Make sure some neighbors are visible to AI
	unset BS_AI_HARD_VISITED_3_2 || true
	unset BS_AI_HARD_VISITED_1_2 || true

	local choice1 choice2
	choice1="$(bs_ai_hard_choose_shot)"
	bs_ai_hard_notify_result "${choice1%% *}" "${choice1##* }" "miss"
	choice2="$(bs_ai_hard_choose_shot)"

	[ "$choice1" != "$choice2" ]
}

@test "unit_ai_hard_returns_no_move_when_all_board_cells_are_exhausted" {
	bs_rng_init_from_seed 5
	bs_board_new 3
	bs_ai_hard_init

	local r c
	for ((r = 1; r <= BS_BOARD_SIZE; r++)); do
		for ((c = 1; c <= BS_BOARD_SIZE; c++)); do
			local v="BS_AI_HARD_VISITED_${r}_${c}"
			eval "${v}=1"
		done
	done

	run bs_ai_hard_choose_shot
	[ "$status" -ne 0 ]
	[ -z "$output" ]
}
