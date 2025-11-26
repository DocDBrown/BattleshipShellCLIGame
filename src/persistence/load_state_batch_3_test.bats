#!/usr/bin/env bats

# Batch 3: integration tests for load_state.sh against its real helpers
# (or realistic stubs) including success and missing/unreadable file paths.

setup() {
  TMP_TEST_DIR="$(mktemp -d)"
  export TMP_TEST_DIR
  MOCK_FILE="$TMP_TEST_DIR/mocks.sh"
  export MOCK_FILE
}

teardown() {
  if [[ -n "${TMP_TEST_DIR:-}" && -d "$TMP_TEST_DIR" ]]; then
    rm -rf -- "$TMP_TEST_DIR"
  fi
}

@test "Integration: load_state_accepts_valid_save_file_with_matching_checksum_and_restores_config_boards_ships_turns_and_stats" {
  f="$TMP_TEST_DIR/good.sav"
  board_new_file="$TMP_TEST_DIR/board_new_called"
  segments_file="$TMP_TEST_DIR/segments_set"
  stats_init_file="$TMP_TEST_DIR/stats_init_called"
  shots_file="$TMP_TEST_DIR/shots_applied"

  {
    printf 'SAVE_VERSION: 1\n'
    printf '[CONFIG]\n'
    printf 'board_size=5\n'
    printf '[BOARD]\n'
    printf '0,0,ship,destroyer\n'
    printf '0,1,ship,destroyer\n'
    printf '[SHIPS]\n'
    printf '[TURNS]\n'
    printf 'player,hit\n'
    printf '[STATS]\n'
    printf 'total_shots_player=1\n'
    printf 'total_shots_ai=0\n'
    printf 'hits_player=1\n'
    printf 'hits_ai=0\n'
    printf 'misses_player=0\n'
    printf 'misses_ai=0\n'
    printf 'sunk_player=0\n'
    printf 'sunk_ai=0\n'
    printf 'CHECKSUM: 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\n'
  } >"$f"

  cat <<EOF > "$MOCK_FILE"
bs_log_info() { printf 'INFO: %s\n' "\$1" >&2; }
bs_log_warn() { printf 'WARN: %s\n' "\$1" >&2; }
bs_log_error() { printf 'ERROR: %s\n' "\$1" >&2; }
bs_checksum_verify() { return 0; }
bs__sanitize_type() {
  local t="\${1:-}"
  t="\${t,,}"
  if [[ ! "\$t" =~ ^[a-z0-9_]+$ ]]; then
    return 1
  fi
  printf '%s' "\$t"
  return 0
}
bs_ship_length() {
  if [[ "\${1:-}" == "destroyer" ]]; then
    printf '2'
    return 0
  fi
  return 1
}
bs_total_segments() { printf '2'; return 0; }
bs_board_new() { touch "$board_new_file"; return 0; }
bs_board_set_ship() { echo "set" >> "$segments_file"; return 0; }
bs_board_set_hit() { return 0; }
bs_board_set_miss() { return 0; }
stats_init() { touch "$stats_init_file"; return 0; }
stats_on_shot() {
  echo "shot" >> "$shots_file"
  return 0
}
EOF

  # shellcheck source=/dev/null
  run bash -c "source '$MOCK_FILE'; source '${BATS_TEST_DIRNAME}/load_state.sh'; bs_load_state_load_file '$f'"

  [ "$status" -eq 0 ]
  [ -f "$board_new_file" ]
  
  count_seg=$(grep -c "set" "$segments_file" || true)
  [ "$count_seg" -eq 2 ]
  
  [ -f "$stats_init_file" ]
  
  count_shot=$(grep -c "shot" "$shots_file" || true)
  [ "$count_shot" -eq 1 ]
  
  [[ "$output" != *"ERROR:"* ]]
}

@test "Integration: load_state_handles_missing_or_unreadable_save_file_and_returns_clear_error" {
  missing="$TMP_TEST_DIR/missing.sav"

  # shellcheck source=/dev/null
  run bash -c "source '${BATS_TEST_DIRNAME}/load_state.sh'; bs_load_state_load_file '$missing'"

  [ "$status" -eq 2 ]
  [[ "$output" == *"File does not exist"* ]]
}