#!/usr/bin/env bats

setup() {
	# Define fail helper since it is not a built-in BATS command
	# shellcheck disable=SC2317
	fail() {
		printf "%s\n" "$*" >&2
		return 1
	}

	TMPDIR_TEST_DIR="$(mktemp -d)"

	# ship_rules.sh: Avoid global arrays for export compatibility
	# Use a file to track calls to bs_ship_length since it runs in a subshell
	cat >"${TMPDIR_TEST_DIR}/ship_rules.sh" <<'SH'
#!/usr/bin/env bash
set -o nounset
set -o pipefail
BS_SHIP_LENGTH_CALLS_FILE="${TMPDIR_TEST_DIR}/ship_length_calls"
export BS_SHIP_LENGTH_CALLS_FILE

bs_ship_list(){ 
	printf "carrier\nbattleship\ncruiser\nsubmarine\ndestroyer\n"
}

bs_ship_length(){ 
	# Increment counter in file
	if [[ -f "$BS_SHIP_LENGTH_CALLS_FILE" ]]; then
		local c
		c=$(<"$BS_SHIP_LENGTH_CALLS_FILE")
		echo "$((c+1))" > "$BS_SHIP_LENGTH_CALLS_FILE"
	fi

	local t="${1:-}"
	t="${t,,}"
	case "$t" in
		carrier) printf 5 ;;
		battleship) printf 4 ;;
		cruiser) printf 3 ;;
		submarine) printf 3 ;;
		destroyer) printf 2 ;;
		*) return 1 ;;
	esac
}
bs_total_segments(){ 
	# Hardcoded sum for test simplicity: 5+4+3+3+2 = 17
	printf "17\n"
}
export -f bs_ship_list bs_ship_length bs_total_segments
SH

	cat >"${TMPDIR_TEST_DIR}/board_state.sh" <<'BS'
#!/usr/bin/env bash
set -o nounset
set -o pipefail
BS_BOARD_SIZE=0
BS_BOARD_TOTAL_SEGMENTS=0
BS_BOARD_REMAINING_SEGMENTS=0
_bs_board__sanitize_for_var(){ printf "%s" "${1//[^a-zA-Z0-9]/_}"; }
bs_board_new(){ local n=${1:-10}; BS_BOARD_SIZE=$n; BS_BOARD_TOTAL_SEGMENTS=0; BS_BOARD_REMAINING_SEGMENTS=0; return 0; }
bs_board_set_ship(){ local raw_r="$1" raw_c="$2" raw_ship="${3:-}"; local ship="${raw_ship,,}"; local r=$((raw_r+1)); local c=$((raw_c+1)); local key="${r}_${c}"; eval "BS_BOARD_CELLSTATE_${key}='ship'"; eval "BS_BOARD_OWNER_${key}='${ship}'"; local sanitized=$(_bs_board__sanitize_for_var "$ship"); local varname="BS_BOARD_SHIP_SEGMENTS_${sanitized}"; local cur=${!varname:-0}; eval "${varname}=$((cur+1))"; BS_BOARD_TOTAL_SEGMENTS=$((BS_BOARD_TOTAL_SEGMENTS+1)); BS_BOARD_REMAINING_SEGMENTS=$((BS_BOARD_REMAINING_SEGMENTS+1)); return 0; }
bs_board_get_state(){ local raw_r="$1" raw_c="$2"; local r=$((raw_r+1)); local c=$((raw_c+1)); if ((r<1||r>BS_BOARD_SIZE||c<1||c>BS_BOARD_SIZE)); then return 2; fi; local key="${r}_${c}"; local var="BS_BOARD_CELLSTATE_${key}"; if [[ -n "${!var+x}" ]]; then printf "%s" "${!var}"; else printf "unknown"; fi; }
bs_board_get_owner(){ local raw_r="$1" raw_c="$2"; local r=$((raw_r+1)); local c=$((raw_c+1)); if ((r<1||r>BS_BOARD_SIZE||c<1||c>BS_BOARD_SIZE)); then return 2; fi; local key="${r}_${c}"; local var="BS_BOARD_OWNER_${key}"; if [[ -n "${!var+x}" ]]; then printf "%s" "${!var}"; else printf ""; fi; }
bs_board_ship_remaining_segments(){ local raw_ship="${1:-}"; local ship="${raw_ship,,}"; local sanitized=$(_bs_board__sanitize_for_var "$ship"); local placed_var="BS_BOARD_SHIP_SEGMENTS_${sanitized}"; local placed="${!placed_var:-0}"; printf "%d" "$placed"; }
bs_board_total_remaining_segments(){ printf "%d" "$BS_BOARD_REMAINING_SEGMENTS"; }
export BS_BOARD_SIZE
export -f bs_board_new bs_board_set_ship bs_board_get_state bs_board_get_owner bs_board_ship_remaining_segments bs_board_total_remaining_segments _bs_board__sanitize_for_var
BS

	cat >"${TMPDIR_TEST_DIR}/placement_validator.sh" <<'PV'
#!/usr/bin/env bash
set -o nounset
set -o pipefail
_bs_placement__normalize_orientation(){ local raw="${1:-}"; case "${raw,,}" in h|horizontal) _BS_PL_DR=0; _BS_PL_DC=1; return 0;; v|vertical) _BS_PL_DR=1; _BS_PL_DC=0; return 0;; *) return 1;; esac }
BS_PL_VALIDATE_CALLS=0
bs_placement_validate(){ BS_PL_VALIDATE_CALLS=$((BS_PL_VALIDATE_CALLS+1)); local start_r="${1:-}" start_c="${2:-}" orient="${3:-}" ship="${4:-}"; if [[ -z "${start_r}" || -z "${start_c}" || -z "${orient}" || -z "${ship}" ]]; then printf "Usage\n" >&2; return 1; fi; if ! command -v bs_ship_length >/dev/null 2>&1; then printf "Missing\n" >&2; return 6; fi; if ! start_r=$(printf "%s" "$start_r") || [[ ! "$start_r" =~ ^[0-9]+$ ]]; then printf "Invalid coords\n" >&2; return 1; fi; local length; if ! length="$(bs_ship_length "${ship}" 2>/dev/null)"; then printf "Invalid ship\n" >&2; return 2; fi; if ! _bs_placement__normalize_orientation "${orient}"; then printf "Invalid orient\n" >&2; return 5; fi; local i r c state; for ((i=0;i<length;i++)); do r=$((start_r + _BS_PL_DR * i)); c=$((start_c + _BS_PL_DC * i)); if ! state="$(bs_board_get_state "${r}" "${c}" 2>/dev/null)"; then printf "Out\n" >&2; return 3; fi; if [[ "${state}" == "ship" ]]; then printf "Overlap\n" >&2; return 4; fi; done; return 0; }
export -f bs_placement_validate _bs_placement__normalize_orientation
PV

	# RNG mock that uses a file to persist state across subshells
	cat >"${TMPDIR_TEST_DIR}/rng.sh" <<'RG'
#!/usr/bin/env bash
set -o nounset
set -o pipefail
BS_RNG_MODE="auto"
BS_RNG_STATE_FILE="${TMPDIR_TEST_DIR}/rng_state"
BS_RNG_MODULO=4294967296
export BS_RNG_STATE_FILE
export BS_RNG_MODULO

bs_rng_init_from_seed(){ 
	if [ $# -lt 1 ]; then return 2; fi; 
	BS_RNG_MODE="lcg"; 
	# Initialize state file
	echo "$(( $1 & 0xFFFFFFFF ))" > "$BS_RNG_STATE_FILE"
	return 0; 
}

bs_rng_lcg_next(){ 
	local s
	if [ -f "$BS_RNG_STATE_FILE" ]; then
		s=$(<"$BS_RNG_STATE_FILE")
	else
		s=0
	fi
	s=$(((s * 1664525 + 1013904223) & 0xFFFFFFFF))
	echo "$s" > "$BS_RNG_STATE_FILE"
	printf "%u" "$s"
}

bs_rng_get_uint32(){ 
	if [ "$BS_RNG_MODE" = "lcg" ]; then 
		bs_rng_lcg_next; 
		return 0; 
	fi; 
	od -An -tu4 -N4 /dev/urandom | tr -d " \n"; 
}

bs_rng_int_range(){ 
	if [ $# -ne 2 ]; then return 2; fi; 
	local min=$1 max=$2; 
	if [ "$min" -gt "$max" ]; then return 2; fi; 
	local span=$((max - min + 1)); 
	if [ "$span" -le 0 ]; then printf "%d\n" "$min"; return 0; fi; 
	local threshold=$(((BS_RNG_MODULO / span) * span)); 
	while :; do 
		local v; 
		v=$(bs_rng_get_uint32); 
		if [ -z "$v" ]; then continue; fi; 
		if [ "$v" -lt "$threshold" ]; then 
			local r=$((v % span)); 
			printf "%d\n" "$((min + r))"; 
			return 0; 
		fi; 
	done; 
}
export -f bs_rng_init_from_seed bs_rng_lcg_next bs_rng_get_uint32 bs_rng_int_range
RG

	# Source helpers and SUT
	# shellcheck disable=SC1091
	. "${TMPDIR_TEST_DIR}/ship_rules.sh"
	# shellcheck disable=SC1091
	. "${TMPDIR_TEST_DIR}/board_state.sh"
	# shellcheck disable=SC1091
	. "${TMPDIR_TEST_DIR}/placement_validator.sh"
	# shellcheck disable=SC1091
	. "${TMPDIR_TEST_DIR}/rng.sh"
	# shellcheck disable=SC1091
	. "${BATS_TEST_DIRNAME}/auto_placement.sh"
}

teardown() {
	if [[ -n "${TMPDIR_TEST_DIR:-}" && -d "${TMPDIR_TEST_DIR}" ]]; then rm -rf "${TMPDIR_TEST_DIR}"; fi
}

@test "unit_auto_place_success_full_fleet_places_all_segments_and_updates_board_counts" {
	bs_board_new 10
	bs_rng_init_from_seed 42
	BS_PL_VALIDATE_CALLS=0
	bs_auto_place_fleet >/dev/null 2>&1 || fail "auto_place failed"
	expected=$(bs_total_segments)
	if [ "${BS_BOARD_TOTAL_SEGMENTS}" -ne "${expected}" ]; then fail "total segments ${BS_BOARD_TOTAL_SEGMENTS} != expected ${expected}"; fi
	if [ "$(bs_board_total_remaining_segments)" -ne "${expected}" ]; then fail "remaining segments mismatch"; fi
}

@test "unit_auto_place_uses_canonical_ship_lengths_from_ship_rules_for_each_proposed_placement" {
	bs_board_new 10
	# Initialize call counter file
	echo "0" > "${TMPDIR_TEST_DIR}/ship_length_calls"
	bs_rng_init_from_seed 99
	bs_auto_place_fleet >/dev/null 2>&1 || fail "auto_place failed"
	
	# Read count from file
	final_count=$(<"${TMPDIR_TEST_DIR}/ship_length_calls")
	num_ships=$(bs_ship_list | wc -l | tr -d '[:space:]')
	
	if [ "${final_count}" -lt "${num_ships}" ]; then 
		fail "bs_ship_length called only ${final_count} times, expected at least ${num_ships}"
	fi
}

@test "unit_auto_place_uses_bs_rng_int_range_for_coordinates_and_orientation_and_is_repeatable_with_seeded_rng" {
	bs_board_new 10
	bs_rng_init_from_seed 12345
	bs_auto_place_fleet >/dev/null 2>&1 || fail "first run failed"
	snap1=""
	for ((r = 0; r < BS_BOARD_SIZE; r++)); do
		for ((c = 0; c < BS_BOARD_SIZE; c++)); do
			o="$(bs_board_get_owner ${r} ${c})"
			if [ -z "${o}" ]; then snap1="${snap1}."; else snap1="${snap1}${o:0:1}"; fi
		done
	done

	bs_board_new 10
	bs_rng_init_from_seed 12345
	bs_auto_place_fleet >/dev/null 2>&1 || fail "second run failed"
	snap2=""
	for ((r = 0; r < BS_BOARD_SIZE; r++)); do
		for ((c = 0; c < BS_BOARD_SIZE; c++)); do
			o="$(bs_board_get_owner ${r} ${c})"
			if [ -z "${o}" ]; then snap2="${snap2}."; else snap2="${snap2}${o:0:1}"; fi
		done
	done

	if [ "${snap1}" != "${snap2}" ]; then fail "placements not repeatable with same seed"; fi
}

@test "unit_auto_place_calls_placement_validator_and_marks_cells_via_board_state_when_validator_accepts" {
	bs_board_new 10
	BS_PL_VALIDATE_CALLS=0
	bs_rng_init_from_seed 2020
	bs_auto_place_fleet >/dev/null 2>&1 || fail "placement failed"
	if [ "${BS_PL_VALIDATE_CALLS}" -le 0 ]; then fail "validator not called"; fi
	total=$(bs_total_segments)
	if [ "${BS_BOARD_TOTAL_SEGMENTS}" -ne "${total}" ]; then fail "board not marked correctly"; fi
}

@test "unit_auto_place_retries_on_validator_overlap_rejections_and_succeeds_within_bound" {
	bs_board_new 10
	# capture original validator and create an '_orig' variant
	orig="$(declare -f bs_placement_validate)"
	orig_mod="${orig/bs_placement_validate/bs_placement_validate_orig}"
	eval "${orig_mod}"

	OVERRIDES_N=5
	OVERRIDES_COUNT=0
	bs_placement_validate() {
		OVERRIDES_COUNT=$((OVERRIDES_COUNT + 1))
		if [ "${OVERRIDES_COUNT}" -le "${OVERRIDES_N}" ]; then
			return 4
		fi
		bs_placement_validate_orig "$@"
	}

	bs_rng_init_from_seed 88
	bs_auto_place_fleet >/dev/null 2>&1 || fail "placement failed after retries"
	if [ "${OVERRIDES_COUNT}" -le "${OVERRIDES_N}" ]; then fail "override did not run enough times"; fi
	if [ "$(bs_board_total_remaining_segments)" -ne "$(bs_total_segments)" ]; then fail "final placement inconsistent"; fi
}