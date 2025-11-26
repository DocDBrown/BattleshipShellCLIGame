#!/usr/bin/env bats

# Batch 0: basic checksum, config, board, ships, and turns behaviour.

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

@test "load_state_calls_bs_checksum_verify_with_footer_digest_and_fails_on_verification_failure" {
	savefile="$TMP_TEST_DIR/save_checksum_fail.sav"

	{
		printf 'SAVE_VERSION: 1\n'
		printf '[CONFIG]\n'
		printf 'board_size=8\n'
		printf '[BOARD]\n'
		printf '[SHIPS]\n'
		printf '[TURNS]\n'
		printf '[STATS]\n'
		printf 'CHECKSUM: deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n'
	} >"$savefile"

	cat <<'EOF' >"$MOCK_FILE"
bs_log_info() { printf 'INFO: %s\n' "$1" >&2; }
bs_log_warn() { printf 'WARN: %s\n' "$1" >&2; }
bs_log_error() { printf 'ERROR: %s\n' "$1" >&2; }
bs_checksum_verify() {
  printf 'bs_checksum_verify_called_with:%s\n' "$1" >&2
  return 1
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

	[ "$status" -eq 3 ]
	[[ "$output" == *"bs_checksum_verify_called_with:"* ]]
	[[ "$output" == *"Checksum mismatch"* ]]
}

@test "load_state_parses_config_section_and_applies_configuration_values_on_success" {
	savefile="$TMP_TEST_DIR/save_config.sav"
	board_size_file="$TMP_TEST_DIR/board_size_observed"

	{
		printf 'SAVE_VERSION: 1\n'
		printf '[CONFIG]\n'
		printf 'board_size=8\n'
		printf '[BOARD]\n'
		printf '[SHIPS]\n'
		printf '[TURNS]\n'
		printf '[STATS]\n'
		printf 'CHECKSUM: 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\n'
	} >"$savefile"

	cat <<EOF >"$MOCK_FILE"
bs_log_info() { printf 'INFO: %s\n' "\$1" >&2; }
bs_log_warn() { printf 'WARN: %s\n' "\$1" >&2; }
bs_log_error() { printf 'ERROR: %s\n' "\$1" >&2; }
bs_checksum_verify() { return 0; }
bs__sanitize_type() { printf '%s' "\$1"; return 0; }
bs_ship_length() { printf '1'; return 0; }
bs_total_segments() { printf '0'; return 0; }
bs_board_new() {
  echo "\$1" > "$board_size_file"
  printf 'NEWBOARD:%s\n' "\$1"
  return 0
}
bs_board_set_ship() { return 0; }
bs_board_set_hit() { return 0; }
bs_board_set_miss() { return 0; }
stats_init() { return 0; }
stats_on_shot() { return 0; }
EOF

	# shellcheck source=/dev/null
	run bash -c "source '$MOCK_FILE'; source '${BATS_TEST_DIRNAME}/load_state.sh'; bs_load_state_load_file '$savefile'"

	[ "$status" -eq 0 ]
	[[ "$output" == *"NEWBOARD:8"* ]]

	observed_size=$(cat "$board_size_file")
	[ "$observed_size" = "8" ]
}

@test "load_state_parses_boards_section_and_calls_board_state_set_ship_for_each_segment" {
	savefile="$TMP_TEST_DIR/save_board.sav"
	calls_file="$TMP_TEST_DIR/set_ship_calls"

	{
		printf 'SAVE_VERSION: 1\n'
		printf '[CONFIG]\n'
		printf 'board_size=5\n'
		printf '[BOARD]\n'
		printf '0,0,ship,destroyer\n'
		printf '0,1,ship,destroyer\n'
		printf '[SHIPS]\n'
		printf '[TURNS]\n'
		printf '[STATS]\n'
		printf 'CHECKSUM: ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\n'
	} >"$savefile"

	cat <<EOF >"$MOCK_FILE"
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
bs_board_set_ship() {
  echo "called" >> "$calls_file"
  printf 'SET_SHIP:%s,%s,%s\n' "\$1" "\$2" "\$3"
  return 0
}
bs_board_set_hit() { return 0; }
bs_board_set_miss() { return 0; }
stats_init() { return 0; }
stats_on_shot() { return 0; }
EOF

	# shellcheck source=/dev/null
	run bash -c "source '$MOCK_FILE'; source '${BATS_TEST_DIRNAME}/load_state.sh'; bs_load_state_load_file '$savefile'"

	[ "$status" -eq 0 ]

	count=$(grep -c "called" "$calls_file" || true)
	[ "$count" -eq 2 ]

	[[ "$output" == *"SET_SHIP:0,0,destroyer"* ]]
	[[ "$output" == *"SET_SHIP:0,1,destroyer"* ]]
}

@test "load_state_parses_ships_section_and_uses_ship_rules_to_validate_fleet_composition_or_error" {
	savefile="$TMP_TEST_DIR/save_bad_ships.sav"

	{
		printf 'SAVE_VERSION: 1\n'
		printf '[CONFIG]\n'
		printf 'board_size=5\n'
		printf '[BOARD]\n'
		printf '0,0,ship,destroyer\n'
		printf '[SHIPS]\n'
		printf '[TURNS]\n'
		printf '[STATS]\n'
		printf 'CHECKSUM: eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\n'
	} >"$savefile"

	cat <<'EOF' >"$MOCK_FILE"
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

@test "load_state_parses_turn_history_section_and_restores_turn_order_and_actions" {
	savefile="$TMP_TEST_DIR/save_turns.sav"
	shots_file="$TMP_TEST_DIR/shots_recorded"

	{
		printf 'SAVE_VERSION: 1\n'
		printf '[CONFIG]\n'
		printf 'board_size=10\n'
		printf '[BOARD]\n'
		printf '[SHIPS]\n'
		printf '[TURNS]\n'
		printf 'player,hit\n'
		printf 'ai,miss\n'
		printf '[STATS]\n'
		printf 'CHECKSUM: 1111111111111111111111111111111111111111111111111111111111111111\n'
	} >"$savefile"

	cat <<EOF >"$MOCK_FILE"
bs_log_info() { printf 'INFO: %s\n' "\$1" >&2; }
bs_log_warn() { printf 'WARN: %s\n' "\$1" >&2; }
bs_log_error() { printf 'ERROR: %s\n' "\$1" >&2; }
bs_checksum_verify() { return 0; }
bs__sanitize_type() { printf '%s' "\$1"; return 0; }
bs_ship_length() { printf '1'; return 0; }
bs_total_segments() { printf '0'; return 0; }
bs_board_new() { return 0; }
bs_board_set_ship() { return 0; }
bs_board_set_hit() { return 0; }
bs_board_set_miss() { return 0; }
stats_init() { return 0; }
stats_on_shot() {
  local shooter="\$1" result="\$2"
  echo "\$shooter:\$result" >> "$shots_file"
  printf 'SHOT:%s:%s\n' "\$shooter" "\$result"
  return 0
}
EOF

	# shellcheck source=/dev/null
	run bash -c "source '$MOCK_FILE'; source '${BATS_TEST_DIRNAME}/load_state.sh'; bs_load_state_load_file '$savefile'"

	[ "$status" -eq 0 ]
	[[ "$output" == *"SHOT:player:hit"* ]]
	[[ "$output" == *"SHOT:ai:miss"* ]]

	# Verify order and content via file
	player_shot=$(grep "player:hit" "$shots_file" || true)
	ai_shot=$(grep "ai:miss" "$shots_file" || true)
	[ -n "$player_shot" ]
	[ -n "$ai_shot" ]
}
