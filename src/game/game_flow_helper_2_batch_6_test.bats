#!/usr/bin/env bats

setup() {
	TMP_TEST_DIR="$(mktemp -d)"
	SAVE_SCRIPT="${TMP_TEST_DIR}/fake_save_state.sh"
	RUNNER="${TMP_TEST_DIR}/runner.sh"
}

teardown() {
	if [[ -n "${TMP_TEST_DIR:-}" && -d "${TMP_TEST_DIR}" ]]; then
		rm -rf -- "${TMP_TEST_DIR}"
	fi
}

@test "Integration: game_flow_calls_exit_traps_on_early_termination_and_persists_state_before_exit" {
	cat >"${SAVE_SCRIPT}" <<'SH'
#!/usr/bin/env bash
OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out)
      shift
      OUT="$1"
      ;;
    *) shift ;;
  esac
done
if [[ -n "$OUT" ]]; then
  echo "SAVED" >"$OUT"
  exit 0
else
  echo "MISSING_OUT" >&2
  exit 1
fi
SH
	chmod +x "${SAVE_SCRIPT}"

	cat >"${RUNNER}" <<SH
#!/usr/bin/env bash
set -euo pipefail

bs_board_new() {
  BS_BOARD_SIZE=\$1
  BS_BOARD_TOTAL_SEGMENTS=1
  BS_BOARD_REMAINING_SEGMENTS=1
  return 0
}

bs_auto_place_fleet() {
  return 0
}

tui_render_dual_grid() { return 0; }
prompt_coordinate() { return 1; }
bs_board_is_win() { printf 'false'; return 0; }

stats_init() { :; }
stats_start() { :; }
game_flow__log_info() { :; }
game_flow__log_warn() { :; }

source "${BATS_TEST_DIRNAME}/game_flow_helper_2.sh"
game_flow_start_new 8 1 "\$1"
SH
	chmod +x "${RUNNER}"

	run bash "${RUNNER}" "${SAVE_SCRIPT}"

	saved_out_file="${SAVE_SCRIPT}.out"
	[ -f "${saved_out_file}" ]
	run cat "${saved_out_file}"
	[ "$status" -eq 0 ]
	[ "${output}" = "SAVED" ]
}
