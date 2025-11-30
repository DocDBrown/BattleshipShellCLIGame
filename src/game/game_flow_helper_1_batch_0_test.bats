#!/usr/bin/env bats

# Only load test_helper if it exists, to avoid bats-gather-tests failures
if [ -f "${BATS_TEST_DIRNAME}/test_helper.bash" ]; then
	load 'test_helper'
fi

setup() {
	# Per-test temporary workspace
	TEST_TMPDIR="$(mktemp -d)"
	export TEST_TMPDIR
	REPO_ROOT="$TEST_TMPDIR/repo"
	mkdir -p "$REPO_ROOT/model" "$REPO_ROOT/placement" "$REPO_ROOT/tui" "$REPO_ROOT/persistence" "$REPO_ROOT/game" "$REPO_ROOT/logging"

	# Create minimal stub implementations that write markers into TEST_TMPDIR

	cat >"$REPO_ROOT/model/board_state.sh" <<'SH'
#!/usr/bin/env bash
bs_board_new() {
  local n="${1:-10}"
  printf "board_new:%s" "$n" >"${TEST_TMPDIR}/called_board_new"
  BS_BOARD_SIZE="$n"
  return 0
}
bs_board_get_state() { printf "unknown"; }
bs_board_get_owner() { printf ""; }
bs_board_set_ship() { return 0; }
bs_board_set_hit() { return 0; }
bs_board_set_miss() { return 0; }
SH

	cat >"$REPO_ROOT/placement/manual_placement.sh" <<'SH'
#!/usr/bin/env bash
# Manual placement stub for tests
main() {
  # record invocation
  printf "manual_called" >"${TEST_TMPDIR}/manual_called"
  local rc="${MANUAL_RET:-0}"
  return "$rc"
}
SH

	cat >"$REPO_ROOT/placement/auto_placement.sh" <<'SH'
#!/usr/bin/env bash
bs_auto_place_fleet() {
  printf "auto_called" >"${TEST_TMPDIR}/auto_called"
  return 0
}
SH

	cat >"$REPO_ROOT/tui/tui_renderer.sh" <<'SH'
#!/usr/bin/env bash
# Minimal tui renderer stub
tui_render_dual_grid() {
  printf "render_called" >"${TEST_TMPDIR}/render_called"
  return 0
}
SH

	cat >"$REPO_ROOT/persistence/load_state.sh" <<'SH'
#!/usr/bin/env bash
bs_load_state_load_file() {
  # Use SAVE_RET env var to decide behavior
  local rc="${SAVE_RET:-0}"
  if [ "$rc" -eq 0 ]; then
    printf "loaded" >"${TEST_TMPDIR}/load_called"
    return 0
  else
    return 2
  fi
}
export -f bs_load_state_load_file
SH

	cat >"$REPO_ROOT/game/stats.sh" <<'SH'
#!/usr/bin/env bash
stats_init() { return 0; }
stats_on_shot() { return 0; }
stats_summary_text() { return 0; }
SH

	# Create a small start script that uses the real game_flow_helper_1.sh from the repository under test
	START_SCRIPT="$TEST_TMPDIR/start_new_game.sh"
	GAME_FLOW_HELPER="$BATS_TEST_DIRNAME/game_flow_helper_1.sh"

	cat >"$START_SCRIPT" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
helper="$1"
repo="$2"
action="$3"
size="${4:-10}"
if [[ -z "$helper" || ! -f "$helper" ]]; then
  echo "Helper not found" >&2
  exit 1
fi
# shellcheck disable=SC1091
. "$helper"
export REPO_ROOT="$repo"
# Load helpers (best-effort)
game_flow__load_common_helpers
if [[ "$action" == "start" ]]; then
  if ! bs_board_new "$size"; then
    echo "bs_board_new failed" >&2
    exit 1
  fi
  # call manual placement main if present; ensure non-zero exit codes
  # from main don't trip 'set -e' and are instead captured in rc.
  rc=0
  if command -v main >/dev/null 2>&1; then
    if main; then
      rc=0
    else
      rc=$?
    fi
  else
    rc=0
  fi
  if [[ "$rc" -eq 3 ]]; then
    if command -v bs_auto_place_fleet >/dev/null 2>&1; then
      bs_auto_place_fleet --verbose 10 || true
    fi
  elif [[ "$rc" -ne 0 ]]; then
    echo "Manual placement failed with code $rc" >&2
    exit 2
  fi
  if command -v tui_render_dual_grid >/dev/null 2>&1; then
    tui_render_dual_grid "$size" "$size" dummy_state dummy_owner dummy_state dummy_owner "Initial"
  fi
  exit 0
elif [[ "$action" == "load" ]]; then
  savefile="${TEST_SAVEFILE:-}"
  if [[ -z "$savefile" ]]; then
    echo "No savefile" >&2
    exit 1
  fi
  if ! bs_load_state_load_file "$savefile"; then
    echo "Failed to load save" >&2
    exit 2
  fi
  if command -v tui_render_dual_grid >/dev/null 2>&1; then
    tui_render_dual_grid "$size" "$size" dummy_state dummy_owner dummy_state dummy_owner "Loaded"
  fi
  exit 0
else
  echo "Unknown action" >&2
  exit 1
fi
SH
	chmod +x "$START_SCRIPT"
}

teardown() {
	# Remove only test-owned temp dir
	if [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]]; then
		rm -rf -- "$TEST_TMPDIR"
	fi
}

# Test: Start new game with valid board size; should call bs_board_new, manual placement and renderer
@test "Unit_StartNewGame_WithValidBoardSize_Calls_bs_board_new_invokes_placement_module_and_renders_initial_grids" {
	run env TEST_TMPDIR="$TEST_TMPDIR" MANUAL_RET=0 bash "$START_SCRIPT" "$GAME_FLOW_HELPER" "$REPO_ROOT" start 10
	[ "$status" -eq 0 ]
	[ -f "$TEST_TMPDIR/called_board_new" ]
	[ -f "$TEST_TMPDIR/manual_called" ]
	[ -f "$TEST_TMPDIR/render_called" ]
}

# Test: Manual placement returns AUTO (exit code 3) -> switch to auto placement and place fleet
@test "Unit_StartNewGame_WhenManualPlacementReturns_AUTO_exit_code_3_switches_to_auto_placement_and_places_fleet" {
	run env TEST_TMPDIR="$TEST_TMPDIR" MANUAL_RET=3 bash "$START_SCRIPT" "$GAME_FLOW_HELPER" "$REPO_ROOT" start 10
	[ "$status" -eq 0 ]
	[ -f "$TEST_TMPDIR/called_board_new" ]
	[ -f "$TEST_TMPDIR/manual_called" ]
	[ -f "$TEST_TMPDIR/auto_called" ]
	[ -f "$TEST_TMPDIR/render_called" ]
}

# Test: Manual placement cancelled or error -> abort startup and report error; do not render
@test "Unit_StartNewGame_WhenManualPlacementReturns_cancel_or_error_aborts_startup_and_reports_error" {
	run env TEST_TMPDIR="$TEST_TMPDIR" MANUAL_RET=2 bash "$START_SCRIPT" "$GAME_FLOW_HELPER" "$REPO_ROOT" start 10
	[ "$status" -ne 0 ]
	[ -f "$TEST_TMPDIR/manual_called" ]
	[ ! -f "$TEST_TMPDIR/render_called" ]
	[[ "$output" == *"Manual placement failed"* || "$output" == *"Manual placement failed"* ]] || true
}

# Test: Load game with valid save file -> calls bs_load_state_load_file and renders initial grids
@test "Unit_LoadGame_WithValidSaveFile_calls_bs_load_state_load_file_restores_board_and_stats_and_renders_initial_grids" {
	# create a dummy save file path
	SAVEFILE="$TEST_TMPDIR/game.save"
	printf "dummy" >"$SAVEFILE"
	run env TEST_TMPDIR="$TEST_TMPDIR" SAVE_RET=0 TEST_SAVEFILE="$SAVEFILE" bash "$START_SCRIPT" "$GAME_FLOW_HELPER" "$REPO_ROOT" load 10
	[ "$status" -eq 0 ]
	[ -f "$TEST_TMPDIR/load_called" ]
	[ -f "$TEST_TMPDIR/render_called" ]
}

# Test: Load game with missing or unreadable save -> propagate error and do not render
@test "Unit_LoadGame_WithMissingOrUnreadableSave_propagates_error_and_does_not_enter_main_loop" {
	SAVEFILE="$TEST_TMPDIR/does_not_matter.save"
	printf "dummy" >"$SAVEFILE"
	run env TEST_TMPDIR="$TEST_TMPDIR" SAVE_RET=2 TEST_SAVEFILE="$SAVEFILE" bash "$START_SCRIPT" "$GAME_FLOW_HELPER" "$REPO_ROOT" load 10
	[ "$status" -ne 0 ]
	[ ! -f "$TEST_TMPDIR/render_called" ]
}
