#!/usr/bin/env bats

setup() {
	TMPDIR_TEST_ROOT="$(mktemp -d)"
	export TMPDIR_TEST_ROOT
	# Copy the SUT into the test-owned temporary directory
	cp "${BATS_TEST_DIRNAME}/battleship_helper_3.sh" "${TMPDIR_TEST_ROOT}/battleship_helper_3.sh"

	# Create minimal helper implementations under the temporary repository layout
	mkdir -p "${TMPDIR_TEST_ROOT}/src/cli" "${TMPDIR_TEST_ROOT}/src/runtime" "${TMPDIR_TEST_ROOT}/src/game" "${TMPDIR_TEST_ROOT}/src/diagnostics"

	# Minimal arg_parser: export a default state dir based on HOME if not provided, and set no explicit action
	cat >"${TMPDIR_TEST_ROOT}/src/cli/arg_parser.sh" <<'ARGP'
#!/usr/bin/env bash
# Minimal arg parser for tests - do not parse args, just set sensible defaults for env vars
export BATTLESHIP_ACTION=""
# The test harness may set BATTLESHIP_STATE_DIR in the environment; honour that, otherwise provide a sane default
export BATTLESHIP_STATE_DIR="${BATTLESHIP_STATE_DIR:-${HOME}/.local/state/battleship}"
export BATTLESHIP_NEW=${BATTLESHIP_NEW:-0}
export BATTLESHIP_LOAD_FILE="${BATTLESHIP_LOAD_FILE:-}"
ARGP

	# Minimal env_safety: provide bs_env_init no-op and pretend mktemp exists
	cat >"${TMPDIR_TEST_ROOT}/src/runtime/env_safety.sh" <<'ENV'
#!/usr/bin/env bash
bs_env_init() { return 0; }
ENV

	# Minimal exit_traps: provide no-op functions used by the SUT
	cat >"${TMPDIR_TEST_ROOT}/src/runtime/exit_traps.sh" <<'EXIT'
#!/usr/bin/env bash
exit_traps_capture_tty_state() { return 0; }
exit_traps_setup() { return 0; }
EXIT

	# Minimal paths implementation: create requested state dir and set 0700
	cat >"${TMPDIR_TEST_ROOT}/src/runtime/paths.sh" <<'PATHS'
#!/usr/bin/env bash
set -euo pipefail
bs_path_state_dir_from_cli() {
  local override="${1-}"
  local dir
  if [[ -n "${override}" ]]; then
    dir="${override}"
  else
    dir="${HOME%/}/.local/state/battleship"
  fi
  mkdir -p -- "$dir"
  chmod 0700 -- "$dir"
  printf '%s' "$dir"
}
PATHS

	# Minimal game_flow to simulate exit codes when invoked with --new or --load
	# Must define functions, not exit at top level, because it is sourced.
	cat >"${TMPDIR_TEST_ROOT}/src/game/game_flow.sh" <<'GF'
#!/usr/bin/env bash
game_flow_start_new() {
  return 7
}
game_flow_load_save() {
  return 5
}
GF

	chmod +x "${TMPDIR_TEST_ROOT}/src/game/game_flow.sh"

	# Runner script used by tests to source the copied helper and either print resolved path or dispatch
	cat >"${TMPDIR_TEST_ROOT}/runner.sh" <<'RUN'
#!/usr/bin/env bash
set -euo pipefail
SCRIPTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# source the helper from the same tempdir
. "$SCRIPTDIR/battleship_helper_3.sh"
if [ "${TEST_ACTION:-}" = "dispatch" ]; then
  dispatch_game_flow
  exit $?
else
  printf '%s' "${BATTLESHIP_STATE_DIR_RESOLVED:-}"
  exit 0
fi
RUN
	chmod +x "${TMPDIR_TEST_ROOT}/runner.sh"

	# Make sure all helper files are readable/executable in temp workspace
	chmod +r "${TMPDIR_TEST_ROOT}/battleship_helper_3.sh"
	chmod +r "${TMPDIR_TEST_ROOT}/src/cli/arg_parser.sh"
	chmod +r "${TMPDIR_TEST_ROOT}/src/runtime/env_safety.sh"
	chmod +r "${TMPDIR_TEST_ROOT}/src/runtime/exit_traps.sh"
	chmod +r "${TMPDIR_TEST_ROOT}/src/runtime/paths.sh"
}

teardown() {
	# Safety: only remove the directory we created and ensure it is an absolute tempdir
	if [ -n "${TMPDIR_TEST_ROOT:-}" ] && [[ "${TMPDIR_TEST_ROOT}" == /tmp/* || "${TMPDIR_TEST_ROOT}" == /var/tmp/* || -d "${TMPDIR_TEST_ROOT}" ]]; then
		rm -rf -- "${TMPDIR_TEST_ROOT}"
	fi
}

@test "launcher_Integration_creates_default_state_directory_with_secure_permissions" {
	# Use an isolated HOME to ensure defaults are placed in test-owned location
	mkdir -p "${TMPDIR_TEST_ROOT}/home_default"
	run timeout 5s env HOME="${TMPDIR_TEST_ROOT}/home_default" PATH="/usr/bin:/bin" bash "${TMPDIR_TEST_ROOT}/runner.sh"
	[ "$status" -eq 0 ]
	expected_dir="${TMPDIR_TEST_ROOT}/home_default/.local/state/battleship"
	[ "$output" = "$expected_dir" ]
	[ -d "$expected_dir" ]
	# Verify permissions are 700 (owner read/write/execute)
	perms="$(stat -c %a "$expected_dir")"
	[ "$perms" = "700" ]
}

@test "launcher_Integration_creates_custom_state_directory_with_secure_permissions_from_cli" {
	custom_dir="${TMPDIR_TEST_ROOT}/custom_state_dir"
	mkdir -p "${TMPDIR_TEST_ROOT}/home2"
	run timeout 5s env HOME="${TMPDIR_TEST_ROOT}/home2" BATTLESHIP_STATE_DIR="$custom_dir" PATH="/usr/bin:/bin" bash "${TMPDIR_TEST_ROOT}/runner.sh"
	[ "$status" -eq 0 ]
	[ "$output" = "$custom_dir" ]
	[ -d "$custom_dir" ]
	perms="$(stat -c %a "$custom_dir")"
	[ "$perms" = "700" ]
}

@test "launcher_Integration_propagates_non_zero_exit_from_game_flow_submodule" {
	# Ensure dispatch_game_flow triggers the test game_flow and we observe its exit status
	run timeout 5s env TEST_ACTION=dispatch BATTLESHIP_NEW=1 HOME="${TMPDIR_TEST_ROOT}/home3" PATH="/usr/bin:/bin" bash "${TMPDIR_TEST_ROOT}/runner.sh"
	# The minimal game_flow returns 7 when invoked with --new
	[ "$status" -eq 7 ]
}