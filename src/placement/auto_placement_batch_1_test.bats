#!/usr/bin/env bats

setup() {
	export SUT_DIR="${BATS_TEST_DIRNAME}"
}

teardown() {
	if [[ -n "${TMP_TEST_DIR:-}" && -d "${TMP_TEST_DIR}" ]]; then
		rm -rf -- "${TMP_TEST_DIR}"
	fi
}

@test "unit_auto_place_retries_on_validator_out_of_bounds_rejections_and_succeeds_within_bound" {
	TMP_TEST_DIR="$(mktemp -d)"
	export TMP_TEST_DIR
	helper="${TMP_TEST_DIR}/helper.sh"
	cat >"$helper" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
# runtime-local tmpdir provided by parent test
TMPDIR_PASS="$TMP_TEST_DIR"
BS_BOARD_SIZE=4
bs_ship_list(){ printf "destroyer\n"; }
bs_ship_length(){ printf "2"; }
bs_board_ship_remaining_segments(){ printf "0"; }
bs_rng_int_range(){ printf "0\n"; }
export -f bs_ship_list bs_ship_length bs_board_ship_remaining_segments bs_rng_int_range

# simulate two validator rejections, then success
# Use file for state to survive potential subshells
bs_placement_validate(){
  local f="${TMPDIR_PASS}/validate_calls"
  local c=0
  if [ -f "$f" ]; then
    c=$(<"$f")
  fi
  c=$((c+1))
  echo "$c" > "$f"

  if [ "$c" -le 2 ]; then
    return 3
  fi
  return 0
}
# record placed segments to a file (no coordinates printed to stdout/stderr)
bs_board_set_ship(){
  printf "%s,%s,%s\n" "$1" "$2" "$3" > "${TMPDIR_PASS}/placed_record"
  return 0
}
export -f bs_placement_validate bs_board_set_ship

# Source SUT using environment variable to ensure path is correct
. "${SUT_DIR}/auto_placement.sh"

# small max attempts to keep test bounded
bs_auto_place_fleet 10
SH
	chmod +x "$helper"
	run timeout 10s bash "$helper"
	[ "$status" -eq 0 ]
	[ -f "${TMP_TEST_DIR}/placed_record" ]
}

@test "unit_auto_place_fails_after_exhausting_retries_and_leaves_board_state_unchanged" {
	TMP_TEST_DIR="$(mktemp -d)"
	export TMP_TEST_DIR
	helper="${TMP_TEST_DIR}/helper.sh"
	cat >"$helper" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
TMPDIR_PASS="$TMP_TEST_DIR"
BS_BOARD_SIZE=4
bs_ship_list(){ printf "destroyer\n"; }
bs_ship_length(){ printf "2"; }
bs_board_ship_remaining_segments(){ printf "0"; }
bs_rng_int_range(){ printf "0\n"; }
export -f bs_ship_list bs_ship_length bs_board_ship_remaining_segments bs_rng_int_range

# always reject placements
bs_placement_validate(){
  return 3
}
# if placement attempted (should not be), record it
bs_board_set_ship(){
  printf "placed" > "${TMPDIR_PASS}/placed_record"
  return 0
}
export -f bs_placement_validate bs_board_set_ship

. "${SUT_DIR}/auto_placement.sh"

# limit attempts to 3 to force early exit
bs_auto_place_fleet 3
SH
	chmod +x "$helper"
	run timeout 10s bash "$helper"
	# Expect non-zero exit (failure to place)
	[ "$status" -ne 0 ]
	# No placed_record file must exist
	[ ! -f "${TMP_TEST_DIR}/placed_record" ]
}

@test "unit_auto_place_enforces_bounded_retries_on_small_boards_and_reports_failure_without_hanging" {
	TMP_TEST_DIR="$(mktemp -d)"
	export TMP_TEST_DIR
	helper="${TMP_TEST_DIR}/helper.sh"
	cat >"$helper" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
TMPDIR_PASS="$TMP_TEST_DIR"
# board too small for destroyer
BS_BOARD_SIZE=1
bs_ship_list(){ printf "destroyer\n"; }
bs_ship_length(){ printf "2"; }
bs_board_ship_remaining_segments(){ printf "0"; }
bs_rng_int_range(){ printf "0\n"; }
export -f bs_ship_list bs_ship_length bs_board_ship_remaining_segments bs_rng_int_range

# validator always returns out-of-bounds
bs_placement_validate(){
  return 3
}
bs_board_set_ship(){
  printf "placed" > "${TMPDIR_PASS}/placed_record"
  return 0
}
export -f bs_placement_validate bs_board_set_ship

. "${SUT_DIR}/auto_placement.sh"

# small attempt limit to ensure quick return
bs_auto_place_fleet 5
SH
	chmod +x "$helper"
	run timeout 5s bash "$helper"
	# should return non-zero quickly
	[ "$status" -ne 0 ]
	[ ! -f "${TMP_TEST_DIR}/placed_record" ]
}

@test "unit_auto_place_verbose_mode_returns_non_sensitive_summary_but_does_not_print_ship_positions" {
	TMP_TEST_DIR="$(mktemp -d)"
	export TMP_TEST_DIR
	helper="${TMP_TEST_DIR}/helper.sh"
	cat >"$helper" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
TMPDIR_PASS="$TMP_TEST_DIR"
BS_BOARD_SIZE=4
bs_ship_list(){ printf "destroyer\n"; }
bs_ship_length(){ printf "2"; }
bs_board_ship_remaining_segments(){ printf "0"; }
bs_rng_int_range(){ printf "0\n"; }
export -f bs_ship_list bs_ship_length bs_board_ship_remaining_segments bs_rng_int_range

# immediate success
bs_placement_validate(){ return 0; }
bs_board_set_ship(){ printf "%s,%s,%s\n" "$1" "$2" "$3" > "${TMPDIR_PASS}/placed_record"; return 0; }
export -f bs_placement_validate bs_board_set_ship

. "${SUT_DIR}/auto_placement.sh"

# verbose mode should emit summary but not coordinates
bs_auto_place_fleet --verbose 10
SH
	chmod +x "$helper"
	run timeout 10s bash "$helper"
	[ "$status" -eq 0 ]
	# output should include placed: and ship name and length and attempts
	[[ "$output" =~ placed:destroyer:length=2:attempts=[0-9]+ ]] || false
	# ensure no coordinate pair like "<num> <num>" appears in stdout
	if echo "$output" | grep -E "[0-9]+[[:space:]][0-9]+" >/dev/null 2>&1; then
		false
	fi
	# ensure placed record exists
	[ -f "${TMP_TEST_DIR}/placed_record" ]
}

@test "unit_auto_place_never_writes_explicit_ship_coordinates_to_stdout_or_stderr_during_gameplay" {
	TMP_TEST_DIR="$(mktemp -d)"
	export TMP_TEST_DIR
	helper="${TMP_TEST_DIR}/helper.sh"
	cat >"$helper" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
TMPDIR_PASS="$TMP_TEST_DIR"
BS_BOARD_SIZE=4
bs_ship_list(){ printf "destroyer\n"; }
bs_ship_length(){ printf "2"; }
bs_board_ship_remaining_segments(){ printf "0"; }
bs_rng_int_range(){ printf "0\n"; }
export -f bs_ship_list bs_ship_length bs_board_ship_remaining_segments bs_rng_int_range

bs_placement_validate(){ return 0; }
bs_board_set_ship(){ printf "%s,%s,%s\n" "$1" "$2" "$3" > "${TMPDIR_PASS}/placed_record"; return 0; }
export -f bs_placement_validate bs_board_set_ship

. "${SUT_DIR}/auto_placement.sh"

bs_auto_place_fleet --verbose 10
SH
	chmod +x "$helper"
	run timeout 10s bash "$helper"
	[ "$status" -eq 0 ]
	# stdout should not contain explicit coordinate pairs
	if echo "$output" | grep -E "[0-9]+[[:space:]][0-9]+" >/dev/null 2>&1; then
		false
	fi
	# stderr should be empty
	[ -z "$error" ]
	[ -f "${TMP_TEST_DIR}/placed_record" ]
}
