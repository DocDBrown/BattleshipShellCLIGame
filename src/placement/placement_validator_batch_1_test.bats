#!/usr/bin/env bats

@test "placement_validator_rejects_ship_extending_beyond_board_vertical_returns_failure_and_hint" {
	tmpdir="${BATS_TEST_DIRNAME}/tmp.$$.${RANDOM}"
	mkdir -p "${tmpdir}"

	cat >"${tmpdir}/stub_ship_rules.sh" <<'SH'
#!/usr/bin/env bash
bs_ship_length() {
  local raw="${1:-}"
  case "${raw,,}" in
    carrier) printf "5"; return 0;;
    battleship) printf "4"; return 0;;
    cruiser) printf "3"; return 0;;
    submarine) printf "3"; return 0;;
    destroyer) printf "2"; return 0;;
    *) printf "Unknown ship type: %s\n" "$raw" >&2; return 2;;
  esac
}
SH

	cat >"${tmpdir}/stub_board_state.sh" <<'SH'
#!/usr/bin/env bash
: "${BS_BOARD_SIZE:=10}"
# Marker format: "r_c:owner,..." stored in BS_TEST_SHIP_MARKER
bs_board_get_state() {
  local r="${1:-}" c="${2:-}"
  if [[ ! "$r" =~ ^[0-9]+$ ]] || [[ ! "$c" =~ ^[0-9]+$ ]]; then
    printf "Coordinates out of bounds: %s %s\n" "$r" "$c" >&2
    return 2
  fi
  if (( r+1 < 1 || r+1 > BS_BOARD_SIZE || c+1 < 1 || c+1 > BS_BOARD_SIZE )); then
    printf "Coordinates out of bounds: %s %s\n" "$r" "$c" >&2
    return 2
  fi
  if [[ -n "${BS_TEST_SHIP_MARKER:-}" ]] && [[ "${BS_TEST_SHIP_MARKER}" == *"${r}_${c}:"* ]]; then
    printf "ship"
    return 0
  fi
  printf "unknown"
  return 0
}
bs_board_get_owner() {
  local r="${1:-}" c="${2:-}"
  if [[ -n "${BS_TEST_SHIP_MARKER:-}" ]] && [[ "${BS_TEST_SHIP_MARKER}" == *"${r}_${c}:"* ]]; then
    local prefix="${r}_${c}:"
    local tmp="${BS_TEST_SHIP_MARKER#*${prefix}}"
    local owner="${tmp%%,*}"
    printf "%s" "$owner"
    return 0
  fi
  printf ""
  return 0
}
SH

	run bash -c "BS_BOARD_SIZE=4; . \"${tmpdir}/stub_ship_rules.sh\"; . \"${tmpdir}/stub_board_state.sh\"; . \"${BATS_TEST_DIRNAME}/placement_validator.sh\"; bs_placement_validate 1 0 v battleship"
	[ "$status" -eq 3 ]
	[[ "$output" == *"Ship would be out of bounds at: 4 0"* ]]

	if [[ "${tmpdir}" == "${BATS_TEST_DIRNAME}"* ]]; then rm -rf "${tmpdir}"; else
		echo "Refusing to delete ${tmpdir}" >&2
		false
	fi
}

@test "placement_validator_rejects_overlap_with_existing_ship_returns_failure_and_hint_and_preserves_board_state" {
	tmpdir="${BATS_TEST_DIRNAME}/tmp.$$.${RANDOM}"
	mkdir -p "${tmpdir}"

	cat >"${tmpdir}/stub_ship_rules.sh" <<'SH'
#!/usr/bin/env bash
bs_ship_length() {
  local raw="${1:-}"
  case "${raw,,}" in
    carrier) printf "5"; return 0;;
    battleship) printf "4"; return 0;;
    cruiser) printf "3"; return 0;;
    submarine) printf "3"; return 0;;
    destroyer) printf "2"; return 0;;
    *) printf "Unknown ship type: %s\n" "$raw" >&2; return 2;;
  esac
}
SH

	cat >"${tmpdir}/stub_board_state.sh" <<'SH'
#!/usr/bin/env bash
: "${BS_BOARD_SIZE:=10}"
bs_board_get_state() {
  local r="${1:-}" c="${2:-}"
  if [[ ! "$r" =~ ^[0-9]+$ ]] || [[ ! "$c" =~ ^[0-9]+$ ]]; then
    printf "Coordinates out of bounds: %s %s\n" "$r" "$c" >&2
    return 2
  fi
  if (( r+1 < 1 || r+1 > BS_BOARD_SIZE || c+1 < 1 || c+1 > BS_BOARD_SIZE )); then
    printf "Coordinates out of bounds: %s %s\n" "$r" "$c" >&2
    return 2
  fi
  if [[ -n "${BS_TEST_SHIP_MARKER:-}" ]] && [[ "${BS_TEST_SHIP_MARKER}" == *"${r}_${c}:"* ]]; then
    printf "ship"
    return 0
  fi
  printf "unknown"
  return 0
}
bs_board_get_owner() {
  local r="${1:-}" c="${2:-}"
  if [[ -n "${BS_TEST_SHIP_MARKER:-}" ]] && [[ "${BS_TEST_SHIP_MARKER}" == *"${r}_${c}:"* ]]; then
    local prefix="${r}_${c}:"
    local tmp="${BS_TEST_SHIP_MARKER#*${prefix}}"
    local owner="${tmp%%,*}"
    printf "%s" "$owner"
    return 0
  fi
  printf ""
  return 0
}
SH

	# Mark a ship at 2,3 owned by carrier
	run bash -c "BS_BOARD_SIZE=10 BS_TEST_SHIP_MARKER=\"2_3:carrier\"; . \"${tmpdir}/stub_ship_rules.sh\"; . \"${tmpdir}/stub_board_state.sh\"; . \"${BATS_TEST_DIRNAME}/placement_validator.sh\"; bs_placement_validate 2 3 h cruiser"
	[ "$status" -eq 4 ]
	[[ "$output" == *"Overlap with existing ship 'carrier' at 2 3"* ]]

	if [[ "${tmpdir}" == "${BATS_TEST_DIRNAME}"* ]]; then rm -rf "${tmpdir}"; else
		echo "Refusing to delete ${tmpdir}" >&2
		false
	fi
}

@test "placement_validator_rejects_invalid_ship_type_or_length_returns_failure_and_hint" {
	tmpdir="${BATS_TEST_DIRNAME}/tmp.$$.${RANDOM}"
	mkdir -p "${tmpdir}"

	cat >"${tmpdir}/stub_ship_rules.sh" <<'SH'
#!/usr/bin/env bash
bs_ship_length() {
  local raw="${1:-}"
  case "${raw,,}" in
    carrier) printf "5"; return 0;;
    battleship) printf "4"; return 0;;
    cruiser) printf "3"; return 0;;
    submarine) printf "3"; return 0;;
    destroyer) printf "2"; return 0;;
    *) printf "Unknown ship type: %s\n" "$raw" >&2; return 2;;
  esac
}
SH

	cat >"${tmpdir}/stub_board_state.sh" <<'SH'
#!/usr/bin/env bash
: "${BS_BOARD_SIZE:=10}"
bs_board_get_state() { printf "unknown"; return 0; }
bs_board_get_owner() { printf ""; return 0; }
SH

	run bash -c ". \"${tmpdir}/stub_ship_rules.sh\"; . \"${tmpdir}/stub_board_state.sh\"; . \"${BATS_TEST_DIRNAME}/placement_validator.sh\"; bs_placement_validate 0 0 h unknownship"
	[ "$status" -eq 2 ]
	[[ "$output" == *"Invalid ship type: unknownship"* ]]

	if [[ "${tmpdir}" == "${BATS_TEST_DIRNAME}"* ]]; then rm -rf "${tmpdir}"; else
		echo "Refusing to delete ${tmpdir}" >&2
		false
	fi
}

@test "placement_validator_rejects_non_numeric_coordinates_returns_failure_and_hint" {
	tmpdir="${BATS_TEST_DIRNAME}/tmp.$$.${RANDOM}"
	mkdir -p "${tmpdir}"

	cat >"${tmpdir}/stub_ship_rules.sh" <<'SH'
#!/usr/bin/env bash
bs_ship_length() { printf "3"; return 0; }
SH

	cat >"${tmpdir}/stub_board_state.sh" <<'SH'
#!/usr/bin/env bash
: "${BS_BOARD_SIZE:=10}"
bs_board_get_state() { printf "unknown"; return 0; }
bs_board_get_owner() { printf ""; return 0; }
SH

	run bash -c ". \"${tmpdir}/stub_ship_rules.sh\"; . \"${tmpdir}/stub_board_state.sh\"; . \"${BATS_TEST_DIRNAME}/placement_validator.sh\"; bs_placement_validate a 0 h carrier"
	[ "$status" -eq 1 ]
	[[ "$output" == *"Invalid coordinates: a 0"* ]]

	if [[ "${tmpdir}" == "${BATS_TEST_DIRNAME}"* ]]; then rm -rf "${tmpdir}"; else
		echo "Refusing to delete ${tmpdir}" >&2
		false
	fi
}

@test "placement_validator_rejects_invalid_orientation_returns_failure_and_hint" {
	tmpdir="${BATS_TEST_DIRNAME}/tmp.$$.${RANDOM}"
	mkdir -p "${tmpdir}"

	cat >"${tmpdir}/stub_ship_rules.sh" <<'SH'
#!/usr/bin/env bash
bs_ship_length() { printf "2"; return 0; }
SH

	cat >"${tmpdir}/stub_board_state.sh" <<'SH'
#!/usr/bin/env bash
: "${BS_BOARD_SIZE:=10}"
bs_board_get_state() { printf "unknown"; return 0; }
bs_board_get_owner() { printf ""; return 0; }
SH

	run bash -c ". \"${tmpdir}/stub_ship_rules.sh\"; . \"${tmpdir}/stub_board_state.sh\"; . \"${BATS_TEST_DIRNAME}/placement_validator.sh\"; bs_placement_validate 0 0 x carrier"
	[ "$status" -eq 5 ]
	[[ "$output" == *"Invalid orientation: x (allowed: h, horizontal, v, vertical)"* ]]

	if [[ "${tmpdir}" == "${BATS_TEST_DIRNAME}"* ]]; then rm -rf "${tmpdir}"; else
		echo "Refusing to delete ${tmpdir}" >&2
		false
	fi
}
