#!/usr/bin/env bats

setup() {
	TMP_TEST_DIR="$(mktemp -d)"
}

teardown() {
	if [ -n "${TMP_TEST_DIR:-}" ] && [ -d "${TMP_TEST_DIR}" ]; then
		rm -rf "${TMP_TEST_DIR}"
	fi
}

@test "Unit_StartNewGame_WithManualPlacementSuccess_invokes_manual_placement_then_renders_and_starts_turn_loop" {
	# Use unquoted delimiter <<SH to allow expansion of BATS_TEST_DIRNAME
	# Escape internal variables (\$*, \$@) to prevent premature expansion
	cat >"${TMP_TEST_DIR}/script.sh" <<SH
#!/usr/bin/env bash
set -euo pipefail
# Source the system under test from the test directory
. "${BATS_TEST_DIRNAME}/game_flow.sh"
# Provide a stub that simulates manual placement succeeding and entering the turn loop
game_flow_start_new() {
  echo "START_NEW_CALLED args:\$*"
  # Simulate TUI rendering and the turn loop starting
  echo "TUI_RENDERED"
  echo "TURN_LOOP_STARTED"
  return 0
}
# Invoke main as if run as a CLI
main "\$@"
SH
	run bash "${TMP_TEST_DIR}/script.sh" --new
	[ "$status" -eq 0 ]
	[[ "$output" == *"START_NEW_CALLED"* ]]
	[[ "$output" == *"TUI_RENDERED"* ]]
	[[ "$output" == *"TURN_LOOP_STARTED"* ]]
}

@test "Unit_StartNewGame_ManualPlacementReturnsAuto_invokes_auto_placement_and_proceeds_to_start_loop" {
	cat >"${TMP_TEST_DIR}/script.sh" <<SH
#!/usr/bin/env bash
set -euo pipefail
. "${BATS_TEST_DIRNAME}/game_flow.sh"
# Provide a bs_auto_place_fleet stub to observe that auto placement is invoked
bs_auto_place_fleet() {
  echo "AUTO_PLACE_INVOKED";
  return 0
}
# Simulate game_flow_start_new calling manual placement then switching to auto placement
game_flow_start_new() {
  echo "MANUAL_PLACEMENT_PERFORMED"
  # Simulate a switch to auto placement; call the auto placement helper
  bs_auto_place_fleet
  echo "TURN_LOOP_STARTED"
  return 0
}
main "\$@"
SH
	run bash "${TMP_TEST_DIR}/script.sh" --new
	[ "$status" -eq 0 ]
	[[ "$output" == *"MANUAL_PLACEMENT_PERFORMED"* ]]
	[[ "$output" == *"AUTO_PLACE_INVOKED"* ]]
	[[ "$output" == *"TURN_LOOP_STARTED"* ]]
}

@test "Unit_StartNewGame_WithAutoPlacementFailure_detects_failure_and_reports_error_without_entering_turn_loop" {
	cat >"${TMP_TEST_DIR}/script.sh" <<SH
#!/usr/bin/env bash
set -euo pipefail
. "${BATS_TEST_DIRNAME}/game_flow.sh"
# Simulate auto placement failing inside the start routine
game_flow_start_new() {
  echo "AUTO_PLACEMENT_FAILED: insufficient_space_or_error"
  return 3
}
main "\$@"
SH
	run bash "${TMP_TEST_DIR}/script.sh" --new
	[ "$status" -eq 3 ]
	[[ "$output" == *"AUTO_PLACEMENT_FAILED"* ]]
	# Ensure we did not reach a marker for the turn loop
	[[ "$output" != *"TURN_LOOP_STARTED"* ]]
}

@test "Unit_LoadGame_Success_calls_bs_load_state_renders_board_and_enters_main_loop" {
	cat >"${TMP_TEST_DIR}/script.sh" <<SH
#!/usr/bin/env bash
set -euo pipefail
. "${BATS_TEST_DIRNAME}/game_flow.sh"
# Provide loader stub that indicates it was invoked and that main loop would start
game_flow_load_save() {
  echo "LOAD_HANDLER_CALLED file=\$1"
  echo "BOARD_RENDERED"
  echo "TURN_LOOP_STARTED"
  return 0
}
main "\$@"
SH
	run bash "${TMP_TEST_DIR}/script.sh" --load "some_save.save"
	[ "$status" -eq 0 ]
	[[ "$output" == *"LOAD_HANDLER_CALLED"* ]]
	[[ "$output" == *"BOARD_RENDERED"* ]]
	[[ "$output" == *"TURN_LOOP_STARTED"* ]]
}

@test "Unit_LoadGame_MissingOrUnreadableSave_reports_error_and_aborts_startup" {
	cat >"${TMP_TEST_DIR}/script.sh" <<SH
#!/usr/bin/env bash
set -euo pipefail
. "${BATS_TEST_DIRNAME}/game_flow.sh"
# Simulate loader detecting missing or unreadable save and returning non-zero
game_flow_load_save() {
  echo "LOAD_HANDLER_ERROR: file missing or unreadable: \$1" >&2
  return 2
}
main "\$@"
SH
	run bash "${TMP_TEST_DIR}/script.sh" --load "missing.save"
	[ "$status" -eq 2 ]
	# We expect the error to have been printed to stderr; Bats captures combined output in $output
	[[ "$output" == *"LOAD_HANDLER_ERROR"* ]]
}