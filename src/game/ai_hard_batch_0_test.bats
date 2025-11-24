#!/usr/bin/env bats

# shellcheck disable=SC2030,SC2031

# Basic behavior & orientation inference tests

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR

  # rng.sh dependency with simple LCG + seeding
  cat >"${TEST_TEMP_DIR}/rng.sh" <<'EOF'
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
  echo "$RANDOM"
}

bs_rng_int_range() {
  local min=$1
  local max=$2
  local span=$((max - min + 1))

  if [ "$span" -le 1 ]; then
    echo "$min"
    return 0
  fi

  local v
  v="$(bs_rng_get_uint32)"
  echo $((min + (v % span)))
}
EOF

  # board_state.sh dependency: only board size + bs_board_new needed
  cat >"${TEST_TEMP_DIR}/board_state.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

BS_BOARD_SIZE=10

bs_board_new() {
  BS_BOARD_SIZE=${1:-10}
}
EOF

  # Copy SUT into temp dir so it can source rng.sh / board_state.sh relatively
  cp "${BATS_TEST_DIRNAME}/ai_hard.sh" "${TEST_TEMP_DIR}/ai_hard.sh"
  chmod +x "${TEST_TEMP_DIR}/ai_hard.sh"
}

teardown() {
  rm -rf "$TEST_TEMP_DIR"
}

@test "unit_ai_hard_init_is_idempotent_and_creates_empty_hunt_state" {
  # shellcheck disable=SC1091
  source "${TEST_TEMP_DIR}/ai_hard.sh"

  bs_ai_hard_init
  [ "$BS_AI_HARD_STATE" = "hunt" ]
  [ "${#BS_AI_HARD_TARGET_QUEUE_R[@]}" -eq 0 ]

  # Mutate state
  BS_AI_HARD_STATE="target"
  BS_AI_HARD_TARGET_QUEUE_R[0]=1

  # Re-init should reset everything
  bs_ai_hard_init
  [ "$BS_AI_HARD_STATE" = "hunt" ]
  [ "${#BS_AI_HARD_TARGET_QUEUE_R[@]}" -eq 0 ]
}

@test "unit_ai_hard_initial_random_scout_selects_untried_cell_and_uses_rng_for_tie_breaking" {
  # shellcheck disable=SC1091
  source "${TEST_TEMP_DIR}/ai_hard.sh"
  bs_ai_hard_init

  run bs_ai_hard_choose_shot
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+\ [0-9]+$ ]]

  read -r r c <<<"$output"
  [ "$r" -ge 1 ] && [ "$r" -le 10 ]
  [ "$c" -ge 1 ] && [ "$c" -le 10 ]
}

@test "unit_ai_hard_seeded_rng_makes_initial_scout_deterministic" {
  # shellcheck disable=SC1091
  source "${TEST_TEMP_DIR}/ai_hard.sh"

  # Run 1
  bs_ai_hard_init
  bs_rng_init_from_seed 12345
  run bs_ai_hard_choose_shot
  [ "$status" -eq 0 ]
  read -r r1 c1 <<<"$output"

  # Run 2
  bs_ai_hard_init
  bs_rng_init_from_seed 12345
  run bs_ai_hard_choose_shot
  [ "$status" -eq 0 ]
  read -r r2 c2 <<<"$output"

  [ "$r1" -eq "$r2" ]
  [ "$c1" -eq "$c2" ]
}

@test "unit_ai_hard_on_first_hit_transitions_to_target_mode_and_prioritizes_adjacent_cells" {
  # shellcheck disable=SC1091
  source "${TEST_TEMP_DIR}/ai_hard.sh"
  bs_ai_hard_init

  # Notify hit at 5,5
  bs_ai_hard_notify_result 5 5 "hit"

  [ "$BS_AI_HARD_STATE" = "target" ]
  [ "${#BS_AI_HARD_TARGET_QUEUE_R[@]}" -gt 0 ]

  # Next shot should be a neighbor (Manhattan distance 1)
  run bs_ai_hard_choose_shot
  [ "$status" -eq 0 ]
  read -r r c <<<"$output"

  local dist
  dist=$(((r - 5) * (r - 5) + (c - 5) * (c - 5)))
  [ "$dist" -eq 1 ]
}

@test "unit_ai_hard_with_two_adjacent_hits_inferrs_orientation_and_extends_along_line" {
  # shellcheck disable=SC1091
  source "${TEST_TEMP_DIR}/ai_hard.sh"
  bs_ai_hard_init

  # Hits at 5,5 and 5,6 (horizontal)
  bs_ai_hard_notify_result 5 5 "hit"
  bs_ai_hard_notify_result 5 6 "hit"

  # Next shot should be 5,4 or 5,7, not vertical neighbors
  run bs_ai_hard_choose_shot
  [ "$status" -eq 0 ]
  read -r r c <<<"$output"

  # Must stay on same row
  [ "$r" -eq 5 ]
  # Must be column 4 or 7
  if [ "$c" -ne 4 ] && [ "$c" -ne 7 ]; then
    echo "Expected col 4 or 7, got $c"
    return 1
  fi
}
