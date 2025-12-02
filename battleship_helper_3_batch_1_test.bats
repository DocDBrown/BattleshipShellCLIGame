#!/usr/bin/env bats

# setup() is run before each test
setup() {
	# Create a temporary directory for this test
	TMP_DIR="$(mktemp -d)"
	export REPO_ROOT="$TMP_DIR" # Set REPO_ROOT for the SUT to point to the temporary directory

	# Define path to the SUT within the temporary directory
	SUT_PATH="$TMP_DIR/battleship_helper_3.sh"

	# Create necessary directory structure for dependencies relative to REPO_ROOT
	mkdir -p "$TMP_DIR/src/cli"
	mkdir -p "$TMP_DIR/src/runtime"
	mkdir -p "$TMP_DIR/src/diagnostics"
	mkdir -p "$TMP_DIR/src/game"

	# Copy the SUT into the temporary directory
	cp "${BATS_TEST_DIRNAME}/battleship_helper_3.sh" "$SUT_PATH"

	# Copy real dependency files from the source directory into the temporary REPO_ROOT structure
	# This ensures integration tests use the actual code for dependencies where possible.
	cp "${BATS_TEST_DIRNAME}/src/runtime/env_safety.sh" "$TMP_DIR/src/runtime/env_safety.sh"
	cp "${BATS_TEST_DIRNAME}/src/runtime/exit_traps.sh" "$TMP_DIR/src/runtime/exit_traps.sh"
	cp "${BATS_TEST_DIRNAME}/src/runtime/paths.sh" "$TMP_DIR/src/runtime/paths.sh"
	cp "${BATS_TEST_DIRNAME}/src/cli/help_text.sh" "$TMP_DIR/src/cli/help_text.sh"
	cp "${BATS_TEST_DIRNAME}/src/diagnostics/self_check.sh" "$TMP_DIR/src/diagnostics/self_check.sh"

	# Create a mock arg_parser.sh to ensure deterministic argument parsing in the test environment.
	# This avoids issues where the real arg_parser might behave unexpectedly or consume args differently.
	cat >"$TMP_DIR/src/cli/arg_parser.sh" <<'EOF'
#!/usr/bin/env bash
# Mock arg_parser for integration tests
while [[ $# -gt 0 ]]; do
  case "$1" in
    --new) export BATTLESHIP_NEW=1 ;;
    --load) export BATTLESHIP_LOAD_FILE="$2"; shift ;;
    --size) export BATTLESHIP_SIZE="$2"; shift ;;
    --ai) export BATTLESHIP_AI="$2"; shift ;;
    --help) export BATTLESHIP_ACTION="help" ;;
    --version) export BATTLESHIP_ACTION="version" ;;
    --doctor|--self-check) export BATTLESHIP_ACTION="doctor" ;;
  esac
  shift
done
EOF

	# Create a mock game_flow.sh that defines the expected functions.
	# We replace the real one completely to avoid side effects from top-level code in the real file.
	cat >"$TMP_DIR/src/game/game_flow.sh" <<'EOF'
#!/usr/bin/env bash
game_flow_start_new() {
  printf "MOCK: game_flow_start_new called with board_size=%s, autosave=%s\n" "$1" "$2" >&2
  return 0
}
game_flow_load_save() {
  printf "MOCK: game_flow_load_save called with savefile=%s\n" "$1" >&2
  return 0
}
EOF
	chmod +x "$TMP_DIR/src/game/game_flow.sh"
}

# teardown() is run after each test
teardown() {
	# Clean up the temporary directory
	rm -rf "$TMP_DIR"
}

@test "launcher_Integration_dispatches_to_help_text_for_help_flag_and_exits_zero" {
	run bash "$SUT_PATH" --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"Battleship - Detailed Help"* ]]
	[[ "$output" == *"Usage: battleship.sh <command> [options]"* ]]
	[[ "$output" == *"Commands: new, load, play, help, version"* ]]
}

@test "launcher_Integration_dispatches_to_help_text_for_version_flag_and_exits_zero" {
	run bash "$SUT_PATH" --version
	[ "$status" -eq 0 ]
	[[ "$output" == *"battleship_shell_script 0.0.0"* ]]
}

@test "launcher_Integration_dispatches_to_self_check_for_doctor_flag_and_propagates_exit_code" {
	# For this test, we assume standard system tools like mktemp are in PATH for self_check.sh to pass.
	run bash "$SUT_PATH" --doctor
	[ "$status" -eq 0 ]
	[[ "$output" == *"Self-check mode: --doctor"* ]]
	[[ "$output" == *"SUMMARY: All required checks passed."* ]]
}

@test "launcher_Integration_no_flags_shows_help_and_exits_zero" {
	run bash "$SUT_PATH"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Battleship - Detailed Help"* ]]
	[[ "$output" == *"Usage: battleship.sh <command> [options]"* ]]
}

@test "launcher_Integration_dispatches_to_game_flow_for_new_game" {
	run bash "$SUT_PATH" --new --size 10 --ai easy
	[ "$status" -eq 0 ]
	[[ "$output" == *"MOCK: game_flow_start_new called with board_size=10, autosave=0"* ]]
}

@test "launcher_Integration_dispatches_to_game_flow_for_load_game" {
	local save_file_path="$TMP_DIR/my_game.sav"
	touch "$save_file_path" # Create a dummy save file for the load operation
	run bash "$SUT_PATH" --load "$save_file_path"
	[ "$status" -eq 0 ]
	[[ "$output" == *"MOCK: game_flow_load_save called with savefile=$save_file_path"* ]]
}