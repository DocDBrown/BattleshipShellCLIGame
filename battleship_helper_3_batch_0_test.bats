#!/usr/bin/env bats

setup() {
	TMPDIR_TEST="$(mktemp -d)"
	repo="$TMPDIR_TEST/repo"
	mkdir -p "$repo/runtime" "$repo/cli"
	cat >"$repo/runtime/env_safety.sh" <<'EOF'
#!/usr/bin/env bash
bs_env_init() {
  export BS_ENV_INIT_CALLED=1
  return 0
}
EOF
	cat >"$repo/runtime/exit_traps.sh" <<'EOF'
#!/usr/bin/env bash
__EXIT_TRAPS_TTY_STATE=""
__EXIT_TRAPS_INITIALIZED=0
exit_traps_capture_tty_state(){ __EXIT_TRAPS_TTY_STATE="captured"; }
exit_traps_setup(){ __EXIT_TRAPS_INITIALIZED=1; }
EOF
	cat >"$repo/cli/arg_parser.sh" <<'EOF'
#!/usr/bin/env bash
export BATTLESHIP_NEW=1
export BATTLESHIP_LOAD_FILE=""
export BATTLESHIP_SIZE="11"
export BATTLESHIP_AI=""
export BATTLESHIP_SEED=""
export BATTLESHIP_NO_COLOR=1
export BATTLESHIP_HIGH_CONTRAST=0
export BATTLESHIP_MONOCHROME=0
export BATTLESHIP_STATE_DIR="/tmp/test-state-dir"
export BATTLESHIP_SAVE_FILE=""
export BATTLESHIP_VERSION=0
export BATTLESHIP_HELP=0
export BATTLESHIP_DOCTOR=0
export BATTLESHIP_SELF_CHECK=0
export BATTLESHIP_ACTION=""
export BATTLESHIP_COLOR_MODE="none"
EOF
	cat >"$repo/runtime/paths.sh" <<'EOF'
#!/usr/bin/env bash
bs_path_state_dir_from_cli(){ printf '%s' "$1"; }
EOF
}

teardown() {
	rm -rf "$TMPDIR_TEST"
}

@test "launcher_sources_env_safety_and_applies_strict_shell_options" {
	run bash -c "REPO_ROOT='$repo' . '${BATS_TEST_DIRNAME}/battleship_helper_3.sh' && printf '%s' \"\$BS_ENV_INIT_CALLED\""
	[ "$status" -eq 0 ]
	[ "$output" = "1" ]
}

@test "launcher_sources_exit_traps_and_initializes_cleanup_mechanism" {
	run bash -c "REPO_ROOT='$repo' . '${BATS_TEST_DIRNAME}/battleship_helper_3.sh' && printf '%s' \"\$__EXIT_TRAPS_INITIALIZED\""
	[ "$status" -eq 0 ]
	[ "$output" = "1" ]
}

@test "launcher_sources_arg_parser_and_exports_configuration_variables" {
	run bash -c "REPO_ROOT='$repo' . '${BATS_TEST_DIRNAME}/battleship_helper_3.sh' && printf '%s' \"\$BATTLESHIP_SIZE\""
	[ "$status" -eq 0 ]
	[ "$output" = "11" ]
}

@test "launcher_interprets_arg_parser_color_flags_into_canonical_mode" {
	run bash -c "REPO_ROOT='$repo' . '${BATS_TEST_DIRNAME}/battleship_helper_3.sh' && printf '%s' \"\$BATTLESHIP_COLOR_MODE\""
	[ "$status" -eq 0 ]
	[ "$output" = "none" ]
}

@test "launcher_uses_normalized_state_dir_from_arg_parser_for_paths_module" {
	run bash -c "REPO_ROOT='$repo' . '${BATS_TEST_DIRNAME}/battleship_helper_3.sh' && printf '%s' \"\$BATTLESHIP_STATE_DIR_RESOLVED\""
	[ "$status" -eq 0 ]
	[ "$output" = "/tmp/test-state-dir" ]
}
