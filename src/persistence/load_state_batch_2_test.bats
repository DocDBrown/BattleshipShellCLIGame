#!/usr/bin/env bats

# Batch 2: footer / checksum tool failure, footer format validation,
# idempotency of load, inconsistent ship counts vs rules, and parse error reporting.

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

@test "load_state_handles_checksum_tool_failure_or_unavailable_backend_and_returns_clear_error" {
  savefile="$TMP_TEST_DIR/save_tool_failure.sav"

  {
    printf 'SAVE_VERSION: 1\n'
    printf '[CONFIG]\n'
    printf 'board_size=5\n'
    printf '[BOARD]\n'
    printf '[SHIPS]\n'
    printf '[TURNS]\n'
    printf '[STATS]\n'
    printf 'CHECKSUM: 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\n'
  } >"$savefile"

  cat <<'EOF' > "$MOCK_FILE"
bs_log_info() { printf 'INFO: %s\n' "$1" >&2; }
bs_log_warn() { printf 'WARN: %s\n' "$1" >&2; }
bs_log_error() { printf 'ERROR: %s\n' "$1" >&2; }
bs_checksum_verify() { return 127; }
bs__sanitize_type() { printf '%s' "$1"; return 0; }
bs_ship_length() { printf '1'; return 0; }
bs_total_segments() { printf '0'; return 0; }
bs_board_new() { return 0; }
bs_board_set_ship() { return 0; }
bs_board_set_hit() { return 0; }
bs_board_set_miss() { return 0; }
stats_init() { return 0; }
stats_on_shot() { return 0; }
EOF

  # shellcheck source=/dev/null
  run bash -c "source '$MOCK_FILE'; source '${BATS_TEST_DIRNAME}/load_state.sh'; bs_load_state_load_file '$savefile'"

  [ "$status" -eq 3 ]
  [[ "$output" == *"Checksum verification failed with code 127"* ]]
}

@test "load_state_validates_footer_digest_format_and_errors_on_non_hex_or_multiline_footer" {
  savefile="$TMP_TEST_DIR/save_bad_footer.sav"

  {
    printf 'SAVE_VERSION: 1\n'
    printf '[CONFIG]\n'
    printf 'board_size=5\n'
    printf '[BOARD]\n'
    printf '[SHIPS]\n'
    printf '[TURNS]\n'
    printf '[STATS]\n'
    # Not 64 hex chars.
    printf 'CHECKSUM: not-a-valid-digest\n'
  } >"$savefile"

  cat <<'EOF' > "$MOCK_FILE"
bs_log_info() { printf 'INFO: %s\n' "$1" >&2; }
bs_log_warn() { printf 'WARN: %s\n' "$1" >&2; }
bs_log_error() { printf 'ERROR: %s\n' "$1" >&2; }
bs_checksum_verify() {
  printf 'UNEXPECTED_CHECKSUM_CALL\n' >&2
  return 0
}
bs__sanitize_type() { printf '%s' "$1"; return 0; }
bs_ship_length() { printf '1'; return 0; }
bs_total_segments() { printf '0'; return 0; }
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
  [[ "$output" == *"Invalid checksum footer"* ]]
  [[ "$output" != *"UNEXPECTED_CHECKSUM_CALL"* ]]
}

@test "load_state_is_idempotent_for_same_valid_file" {
  savefile="$TMP_TEST_DIR/save_idempotent.sav"
  load_calls_file="$TMP_TEST_DIR/load_calls"

  {
    printf 'SAVE_VERSION: 1\n'
    printf '[CONFIG]\n'
    printf 'board_size=6\n'
    printf '[BOARD]\n'
    printf '0,0,ship,destroyer\n'
    printf '0,1,ship,destroyer\n'
    printf '[SHIPS]\n'
    printf '[TURNS]\n'
    printf 'player,hit\n'
    printf '[STATS]\n'
    printf 'CHECKSUM: ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\n'
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
bs_board_new() { echo "called" >> "$load_calls_file"; return 0; }
bs_board_set_ship() { return 0; }
bs_board_set_hit() { return 0; }
bs_board_set_miss() { return 0; }
stats_init() { return 0; }
stats_on_shot() { return 0; }
EOF

  # First load
  # shellcheck source=/dev/null
  run bash -c "source '$MOCK_FILE'; source '${BATS_TEST_DIRNAME}/load_state.sh'; bs_load_state_load_file '$savefile'"
  [ "$status" -eq 0 ]
  out1="$output"

  # Second load of the same file
  # shellcheck source=/dev/null
  run bash -c "source '$MOCK_FILE'; source '${BATS_TEST_DIRNAME}/load_state.sh'; bs_load_state_load_file '$savefile'"
  [ "$status" -eq 0 ]
  out2="$output"

  # We allow bs_board_new to be called twice (rebuild board both times),
  # but it must not fail or accumulate inconsistent state.
  count=$(grep -c "called" "$load_calls_file" || true)
  [ "$count" -eq 2 ]
  [[ "$out1" != *"Inconsistent"* ]]
  [[ "$out2" != *"Inconsistent"* ]]
}

@test "load_state_rejects_save_with_inconsistent_ship_segment_counts_against_ship_rules" {
  savefile="$TMP_TEST_DIR/save_inconsistent_segments.sav"

  {
    printf 'SAVE_VERSION: 1\n'
    printf '[CONFIG]\n'
    printf 'board_size=5\n'
    printf '[BOARD]\n'
    printf '0,0,ship,destroyer\n'
    printf '[SHIPS]\n'
    printf '[TURNS]\n'
    printf '[STATS]\n'
    printf 'CHECKSUM: 2222222222222222222222222222222222222222222222222222222222222222\n'
  } >"$savefile"

  cat <<'EOF' > "$MOCK_FILE"
bs_log_info() { printf 'INFO: %s\n' "$1" >&2; }
bs_log_warn() { printf 'WARN: %s\n' "$1" >&2; }
bs_log_error() { printf 'ERROR: %s\n' "$1" >&2; }
bs_checksum_verify() { return 0; }
bs__sanitize_type() { printf '%s' "$1"; return 0; }
bs_ship_length() {
  if [[ "${1:-}" == "destroyer" ]]; then
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
stats_init() { return 0; }
stats_on_shot() { return 0; }
EOF

  # shellcheck source=/dev/null
  run bash -c "source '$MOCK_FILE'; source '${BATS_TEST_DIRNAME}/load_state.sh'; bs_load_state_load_file '$savefile'"

  [ "$status" -eq 4 ]
  [[ "$output" == *"Inconsistent segment count for destroyer"* ]]
}

@test "load_state_reports_parsing_errors_with_contextual_messages_indicating_faulty_section" {
  savefile="$TMP_TEST_DIR/save_parse_error.sav"

  {
    printf 'SAVE_VERSION: 1\n'
    printf '[CONFIG]\n'
    printf 'board_size=not-a-number\n'
    printf '[BOARD]\n'
    printf '[SHIPS]\n'
    printf '[TURNS]\n'
    printf '[STATS]\n'
    printf 'CHECKSUM: 3333333333333333333333333333333333333333333333333333333333333333\n'
  } >"$savefile"

  cat <<'EOF' > "$MOCK_FILE"
bs_log_info() { printf 'INFO: %s\n' "$1" >&2; }
bs_log_warn() { printf 'WARN: %s\n' "$1" >&2; }
bs_log_error() { printf 'ERROR: %s\n' "$1" >&2; }
bs_checksum_verify() { return 0; }
bs__sanitize_type() { printf '%s' "$1"; return 0; }
bs_ship_length() { printf '1'; return 0; }
bs_total_segments() { printf '0'; return 0; }
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
  [[ "$output" == *"Invalid board_size in config"* ]]
}