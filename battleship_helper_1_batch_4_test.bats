#!/usr/bin/env bats

setup() {
	TMPDIR_TEST="$(mktemp -d)"
}

teardown() {
	if [ -n "${TMPDIR_TEST:-}" ] && [ -d "${TMPDIR_TEST}" ]; then
		rm -rf -- "${TMPDIR_TEST}"
	fi
}

@test "self_check reports state-dir WRITE test FAILED and exits non-zero when state directory is not writable" {
	# Create a state directory that is not writable by the test process
	mkdir -p "${TMPDIR_TEST}/state"
	chmod 500 "${TMPDIR_TEST}/state"

	cat >"${TMPDIR_TEST}/self_check.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
state_dir="${1:-}"
if [ -z "${state_dir}" ]; then
  echo "state-dir: WRITE test FAILED (cannot create files in )" >&2
  exit 2
fi
if ! touch "${state_dir}/.bself.$$" 2>/dev/null; then
  echo "state-dir: WRITE test FAILED (cannot create files in ${state_dir})" >&2
  exit 2
else
  rm -f -- "${state_dir}/.bself.$$"
  echo "state-dir: WRITE test succeeded"
  exit 0
fi
SH

	run timeout 5s bash "${TMPDIR_TEST}/self_check.sh" "${TMPDIR_TEST}/state"
	[ "$status" -eq 2 ]
	[[ "$output" == *"WRITE test FAILED"* ]]
}

@test "game_flow --load without loader helper returns code 2 and prints missing helper / missing function" {
	cat >"${TMPDIR_TEST}/game_flow.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

game_flow__require() {
  local f="$1"
  if [[ -f "$f" ]]; then
    return 0
  fi
  printf "Missing helper: %s\n" "$f" >&2
  return 2
}

main() {
  if [[ "$1" == "--load" ]]; then
    if [[ -z "${2:-}" ]]; then
      printf "Missing argument for --load\n" >&2
      exit 1
    fi
    savefile="$2"
    if type game_flow_load_save >/dev/null 2>&1; then
      game_flow_load_save "$savefile"
      exit $?
    fi
    game_flow__require "${REPO_ROOT}/persistence/load_state.sh" || exit 2
    if type game_flow_load_save >/dev/null 2>&1; then
      game_flow_load_save "$savefile"
      exit $?
    fi
    printf "Missing function: game_flow_load_save\n" >&2
    exit 2
  fi
  echo "noop"
  exit 0
}

main "$@"
SH

	run timeout 5s bash "${TMPDIR_TEST}/game_flow.sh" --load "some.sav"
	[ "$status" -eq 2 ]
	[[ "$output" == *"Missing helper"* || "$output" == *"Missing function"* ]]
}

@test "game_flow delegates to game_flow_start_new when provided and returns the delegated exit code" {
	# create a helper that provides game_flow_start_new
	cat >"${TMPDIR_TEST}/custom_helper.sh" <<'SH'
#!/usr/bin/env bash
game_flow_start_new() {
  echo "delegated-called"
  return 7
}
SH

	cat >"${TMPDIR_TEST}/game_flow.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${REPO_ROOT}/custom_helper.sh" ]; then
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/custom_helper.sh"
fi
main() {
  if type game_flow_start_new >/dev/null 2>&1; then
    game_flow_start_new "$@"
    exit $?
  fi
  echo "no delegate"
  exit 2
}
main "$@"
SH

	run timeout 5s bash "${TMPDIR_TEST}/game_flow.sh"
	[ "$status" -eq 7 ]
	[[ "$output" == *"delegated-called"* ]]
}
