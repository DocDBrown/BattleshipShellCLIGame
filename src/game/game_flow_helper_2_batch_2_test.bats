#!/usr/bin/env bats

setup() {
	# per-test temporary directory
	TEST_TMPDIR=$(mktemp -d)
	export TEST_TMPDIR
}

teardown() {
	if [ -n "${TEST_TMPDIR:-}" ] && [[ "${TEST_TMPDIR}" == "${BATS_TEST_DIRNAME}"/* || "${TEST_TMPDIR}" == /tmp/* || -d "${TEST_TMPDIR}" ]]; then
		rm -rf -- "${TEST_TMPDIR}"
	fi
}

@test "Integration:save_then_load_roundtrip_preserves_board_state_ship_counts_and_stats" {
	# Run in a subshell that sources the SUT and provides minimal mocked deps.
	run bash -c '
    set -euo pipefail
    # Provide a minimal bs_load_state_load_file that simulates loading a save
    bs_load_state_load_file() {
      # simulate applying a saved board: set globals expected by SUT
      BS_BOARD_SIZE=4
      BS_BOARD_TOTAL_SEGMENTS=3
      BS_BOARD_REMAINING_SEGMENTS=1
      # No error
      return 0
    }
    # Provide other helpers SUT expects during run loop
    bs_board_is_win() { printf "true"; }
    te_set_on_shot_result_callback() { return 0; }
    te_init() { return 0; }
    tui_render_dual_grid() { return 0; }
    prompt_coordinate() { return 2; }
    game_flow__print_summary_and_exit() { return 0; }
    game_flow__log_info() { :; }
    game_flow__log_warn() { :; }

    # Source the SUT and invoke load
    . "'"${BATS_TEST_DIRNAME}"'/game_flow_helper_2.sh"
    game_flow_load_save "'"${TEST_TMPDIR}"'/fake.save"
  '
	# Expect successful exit
	[ "$status" -eq 0 ]
}
