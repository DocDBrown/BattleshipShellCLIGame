#!/usr/bin/env bats

# Batch 1: stats restoration, malformed structure, checksum vs parse errors,
# input sanitisation, and preservation of pre-existing state.

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

@test "load_state_restores_stats_by_invoking_stats_init_and_populating_counters" {
  savefile="$TMP_TEST_DIR/save_stats.sav"
  shots_file="$TMP_TEST_DIR/shots_recorded"
  init_file="$TMP_TEST_DIR/stats_init_called"

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
    printf 'ai,miss\n'
    printf '[STATS]\n'
    printf 'total_shots_player=1\n'
    printf 'total_shots_ai=1\n'
    printf 'hits_player=1\n'
    printf 'hits_ai=0\n'
    printf 'misses_player=0\n'
    printf 'misses_ai=1\n'
    printf 'sunk_player=0\n'
    printf 'sunk_ai=0\n'
    printf 'CHECKSUM: aaaabbbbccccddddeeeeffff0000111122223333444455556666777788889999\n'
  } >"$savefile"

  cat <<EOF > "$MOCK_FILE"
bs_log_info() { printf 'INFO: %s\n' "\$1" >&2; }
bs_log_warn() { printf 'WARN: %s\n' "\$1" >&2; }
bs_log_error() { printf 'ERROR: %s\n' "\$1" >&2; }
bs_checksum_verify() { return 0; }
bs__sanitize_type() { printf '%s' "\$1"; return 0; }
bs_ship_length() {
  if [[ "\${1:-}" == "destroyer" ]]; then
    printf '2'
    return 0
  fi
  return 1
}
bs_total_segments() { printf '2'; return 0; }
bs_board_new() { return 0; }
bs_board_set_ship() { return 0; }
bs_board_set_hit() { return 0; }
bs_board_set_miss() { return 0; }
stats_init() {
  touch "$init_file"
  return 0
}
stats_on_shot() {
  local shooter="\$1" result="\$2"
  echo "\$shooter,\$result" >> "$shots_file"
  return 0
}
EOF

  # shellcheck source=/dev/null
  run bash -c "source '$MOCK_FILE'; source '${BATS_TEST_DIRNAME}/load_state.sh'; bs_load_state_load_file '$savefile'"

  [ "$status" -eq 0 ]
  [ -f "$init_file" ]
  [ -f "$shots_file" ]
  
  # Verify content of shots
  run cat "$shots_file"
  [[ "$output" == *"player,hit"* ]]
  [[ "$output" == *"ai,miss"* ]]
}

@test "load_state_detects_malformed_section_structure_and_aborts_without_applying_partial_state" {
  savefile="$TMP_TEST_DIR/save_malformed.sav"
  board_new_file="$TMP_TEST_DIR/board_new_called"
  stats_init_file="$TMP_TEST_DIR/stats_init_called"

  {
    printf 'SAVE_VERSION: 1\n'
    printf '[CONFIG]\n'
    printf 'board_size=5\n'
    printf '[BOARD]\n'
    # Malformed: missing owner field
    printf '0,0,ship\n'
    printf '[SHIPS]\n'
    printf '[TURNS]\n'
    printf '[STATS]\n'
    printf 'CHECKSUM: 9999888877776666555544443333222211110000aaaabbbbccccddddeeeeffff\n'
  } >"$savefile"

  cat <<EOF > "$MOCK_FILE"
bs_log_info() { printf 'INFO: %s\n' "\$1" >&2; }
bs_log_warn() { printf 'WARN: %s\n' "\$1" >&2; }
bs_log_error() { printf 'ERROR: %s\n' "\$1" >&2; }
bs_checksum_verify() { return 0; }
bs__sanitize_type() { printf '%s' "\$1"; return 0; }
bs_ship_length() { printf '1'; return 0; }
bs_total_segments() { printf '1'; return 0; }
bs_board_new() { touch "$board_new_file"; return 0; }
bs_board_set_ship() { return 0; }
bs_board_set_hit() { return 0; }
bs_board_set_miss() { return 0; }
stats_init() { touch "$stats_init_file"; return 0; }
stats_on_shot() { return 0; }
EOF

  # shellcheck source=/dev/null
  run bash -c "source '$MOCK_FILE'; source '${BATS_TEST_DIRNAME}/load_state.sh'; bs_load_state_load_file '$savefile'"

  [ "$status" -eq 4 ]
  [[ "$output" == *"Missing owner for ship"* ]]

  # No application should have happened on parse failure.
  [ ! -f "$board_new_file" ]
  [ ! -f "$stats_init_file" ]
}

@test "load_state_distinguishes_checksum_mismatch_from_parse_errors_and_returns_distinct_error_codes" {
  savefile="$TMP_TEST_DIR/save_checksum_vs_parse.sav"
  board_new_file="$TMP_TEST_DIR/board_new_called"

  {
    printf 'SAVE_VERSION: 1\n'
    printf '[CONFIG]\n'
    printf 'board_size=5\n'
    printf '[BOARD]\n'
    printf '0,0,empty,none\n'
    printf '[SHIPS]\n'
    printf '[TURNS]\n'
    printf '[STATS]\n'
    printf 'CHECKSUM: 1234123412341234123412341234123412341234123412341234123412341234\n'
  } >"$savefile"

  cat <<EOF > "$MOCK_FILE"
bs_log_info() { printf 'INFO: %s\n' "\$1" >&2; }
bs_log_warn() { printf 'WARN: %s\n' "\$1" >&2; }
bs_log_error() { printf 'ERROR: %s\n' "\$1" >&2; }
bs_checksum_verify() { return 1; }
bs__sanitize_type() { printf '%s' "\$1"; return 0; }
bs_ship_length() { printf '1'; return 0; }
bs_total_segments() { printf '0'; return 0; }
bs_board_new() { touch "$board_new_file"; return 0; }
bs_board_set_ship() { return 0; }
bs_board_set_hit() { return 0; }
bs_board_set_miss() { return 0; }
stats_init() { return 0; }
stats_on_shot() { return 0; }
EOF

  # shellcheck source=/dev/null
  run bash -c "source '$MOCK_FILE'; source '${BATS_TEST_DIRNAME}/load_state.sh'; bs_load_state_load_file '$savefile'"

  [ "$status" -eq 3 ]
  [[ "$output" == *"Checksum mismatch"* ]]

  # State must not have been mutated due to checksum failure.
  [ ! -f "$board_new_file" ]
}

@test "load_state_does_not_execute_arbitrary_content_from_save_file_no_shell_eval_or_command_execution" {
  savefile="$TMP_TEST_DIR/save_injection.sav"
  marker="$TMP_TEST_DIR/external_marker"

  {
    printf 'SAVE_VERSION: 1\n'
    printf '[CONFIG]\n'
    printf 'board_size=5\n'
    printf '[BOARD]\n'
    # Attempt to smuggle a command into the owner field.
    # shellcheck disable=SC2016
    printf '0,0,ship,$(touch "%s")\n' "$marker"
    printf '[SHIPS]\n'
    printf '[TURNS]\n'
    printf '[STATS]\n'
    printf 'CHECKSUM: abcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcd\n'
  } >"$savefile"

  cat <<'EOF' > "$MOCK_FILE"
bs_log_info() { printf 'INFO: %s\n' "$1" >&2; }
bs_log_warn() { printf 'WARN: %s\n' "$1" >&2; }
bs_log_error() { printf 'ERROR: %s\n' "$1" >&2; }
bs_checksum_verify() { return 0; }
bs__sanitize_type() {
  local t="${1:-}"
  t="${t,,}"
  if [[ ! "$t" =~ ^[a-z0-9_]+$ ]]; then
    return 1
  fi
  printf '%s' "$t"
  return 0
}
bs_ship_length() { printf '1'; return 0; }
bs_total_segments() { printf '1'; return 0; }
bs_board_new() { return 0; }
bs_board_set_ship() { return 0; }
bs_board_set_hit() { return 0; }
bs_board_set_miss() { return 0; }
stats_init() { return 0; }
stats_on_shot() { return 0; }
EOF

  # shellcheck source=/dev/null
  run bash -c "source '$MOCK_FILE'; source '${BATS_TEST_DIRNAME}/load_state.sh'; bs_load_state_load_file '$savefile'"

  [ "$status" -eq 4 ]
  [[ "$output" == *"Invalid ship owner name"* ]]

  # No external side-effect should have happened.
  [ ! -e "$marker" ]
}

@test "load_state_preserves_existing_in_memory_state_on_any_fatal_error_in_checksum_or_parsing" {
  savefile="$TMP_TEST_DIR/save_preserve_state.sav"
  stats_init_file="$TMP_TEST_DIR/stats_init_called"

  {
    printf 'SAVE_VERSION: 1\n'
    printf '[CONFIG]\n'
    printf 'board_size=7\n'
    printf '[BOARD]\n'
    printf '0,0,unknown,none\n'
    printf '[SHIPS]\n'
    printf '[TURNS]\n'
    printf '[STATS]\n'
    printf 'CHECKSUM: f00df00df00df00df00df00df00df00df00df00df00df00df00df00df00df00d\n'
  } >"$savefile"

  cat <<EOF > "$MOCK_FILE"
bs_log_info() { printf 'INFO: %s\n' "\$1" >&2; }
bs_log_warn() { printf 'WARN: %s\n' "\$1" >&2; }
bs_log_error() { printf 'ERROR: %s\n' "\$1" >&2; }
bs_checksum_verify() { return 1; }
bs__sanitize_type() { printf '%s' "\$1"; return 0; }
bs_ship_length() { printf '1'; return 0; }
bs_total_segments() { printf '0'; return 0; }
bs_board_new() { return 0; }
bs_board_set_ship() { return 0; }
bs_board_set_hit() { return 0; }
bs_board_set_miss() { return 0; }
stats_init() { touch "$stats_init_file"; return 0; }
stats_on_shot() { return 0; }
EOF

  # shellcheck source=/dev/null
  run bash -c "source '$MOCK_FILE'; source '${BATS_TEST_DIRNAME}/load_state.sh'; bs_load_state_load_file '$savefile'"

  [ "$status" -eq 3 ]
  [[ "$output" == *"Checksum mismatch"* ]]

  # Stats init must remain untouched.
  [ ! -f "$stats_init_file" ]
}