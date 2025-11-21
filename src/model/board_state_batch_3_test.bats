#!/usr/bin/env bats

setup() {
  BOARD_STATE_SCRIPT="${BATS_TEST_DIRNAME}/board_state.sh"
}

@test "unit: total remaining segments decreases only on unique new hits and win condition triggers when remaining segments reach zero" {
  run bash -c ". \"$BOARD_STATE_SCRIPT\"; \
bs_board_new 2 >/dev/null; \
bs_board_set_ship 0 0 carrier >/dev/null; \
bs_board_set_ship 0 1 carrier >/dev/null; \
echo BEFORE:\$(bs_board_total_remaining_segments); \
bs_board_set_hit 0 0 >/dev/null; \
echo AFTER1:\$(bs_board_total_remaining_segments); \
bs_board_set_hit 0 0 >/dev/null; \
echo AFTER2:\$(bs_board_total_remaining_segments); \
bs_board_set_hit 0 1 >/dev/null; \
echo AFTER_FINAL:\$(bs_board_total_remaining_segments); \
echo WIN:\$(bs_board_is_win)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BEFORE:2"* ]]
  [[ "$output" == *"AFTER1:1"* ]]
  [[ "$output" == *"AFTER2:1"* ]]
  [[ "$output" == *"AFTER_FINAL:0"* ]]
  [[ "$output" == *"WIN:true"* ]]
}

@test "unit: querying or updating out-of-bounds coordinates returns an error and leaves board state unchanged" {
  run bash -c ". \"$BOARD_STATE_SCRIPT\"; \
bs_board_new 3 >/dev/null; \
bs_board_set_ship 1 1 destroyer >/dev/null; \
echo RC:\$(bs_board_get_state 1 1); \
bs_board_set_ship 99 99 carrier 2>/dev/null || echo OOB_ERR; \
bs_board_get_state 99 99 >/dev/null 2>&1 || echo GET_ERR; \
echo RC_AFTER:\$(bs_board_get_state 1 1)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RC:ship"* ]]
  [[ "$output" == *"OOB_ERR"* ]]
  [[ "$output" == *"GET_ERR"* ]]
  [[ "$output" == *"RC_AFTER:ship"* ]]
}

@test "unit: repeated hits on the same coordinate count only once toward ship damage (idempotent hit counting)" {
  run bash -c ". \"$BOARD_STATE_SCRIPT\"; \
bs_board_new 3 >/dev/null; \
bs_board_set_ship 1 1 destroyer >/dev/null; \
bs_board_set_ship 1 2 destroyer >/dev/null; \
echo INIT:\$(bs_board_ship_remaining_segments destroyer); \
bs_board_set_hit 1 1 >/dev/null; \
echo AFTER1:\$(bs_board_ship_remaining_segments destroyer); \
bs_board_set_hit 1 1 >/dev/null; \
echo AFTER2:\$(bs_board_ship_remaining_segments destroyer); \
echo SUNK1:\$(bs_board_ship_is_sunk destroyer); \
bs_board_set_hit 1 2 >/dev/null; \
echo FINAL:\$(bs_board_ship_remaining_segments destroyer); \
echo SUNK2:\$(bs_board_ship_is_sunk destroyer)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"INIT:2"* ]]
  [[ "$output" == *"AFTER1:1"* ]]
  [[ "$output" == *"AFTER2:1"* ]]
  [[ "$output" == *"SUNK1:false"* ]]
  [[ "$output" == *"FINAL:0"* ]]
  [[ "$output" == *"SUNK2:true"* ]]
}
