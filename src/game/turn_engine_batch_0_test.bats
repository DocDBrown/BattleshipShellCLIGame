#!/usr/bin/env bats
# shellcheck disable=SC1090,SC1091,SC2034,SC2317

setup() {
	:
}

# local fail helper so "|| fail" works even if bats-core helpers are not loaded
fail() {
	printf '%s\n' "$*" >&2
	return 1
}

te_write_deps_batch_0() {
	local out="${1}"
	cat >"${out}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Minimal mock implementations used by tests
bs_board_new() {
    BS_BOARD_SIZE=${1:-10}
    BS_BOARD_REMAINING_SEGMENTS=${BS_BOARD_REMAINING_SEGMENTS:-0}
    return 0
}

validate_board_size() {
    local s="${1:-}"
    if [[ ! "${s}" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    if ((s < 8 || s > 12)); then
        return 1
    fi
    return 0
}

validate_coordinate() {
    local coord="${1:-}"
    local size="${2:-0}"
    if [ -z "${coord}" ]; then return 1; fi
    if [[ ! "${coord}" =~ ^([A-Z])([1-9]|10|11|12)$ ]]; then return 1; fi
    local letter="${BASH_REMATCH[1]}"; local number="${BASH_REMATCH[2]}"
    local ord; ord=$(printf '%d' "'${letter}") || return 1
    local max=$((65 + size - 1))
    if ((ord < 65 || ord > max)); then return 1; fi
    if ((number < 1 || number > size)); then return 1; fi
    return 0
}

_bs_key() {
    printf "%s_%s" "${1}" "${2}"
}

bs_board_get_state() {
    local r="${1}" c="${2}"
    local k; k=$(_bs_key "${r}" "${c}")
    local var="MOCK_CELLSTATE_${k}"
    if [[ -n "${!var+x}" ]]; then
        printf "%s" "${!var}"
    else
        printf "unknown"
    fi
}

bs_board_get_owner() {
    local r="${1}" c="${2}"
    local k; k=$(_bs_key "${r}" "${c}")
    local var="MOCK_OWNER_${k}"
    if [[ -n "${!var+x}" ]]; then
        printf "%s" "${!var}"
    else
        printf ""
    fi
}

bs_board_set_hit() {
    local r="${1}" c="${2}"
    local k; k=$(_bs_key "${r}" "${c}")
    local state_var="MOCK_CELLSTATE_${k}"
    local owner_var="MOCK_OWNER_${k}"
    local owner="${!owner_var:-}"
    eval "${state_var}='hit'"
    if [[ -n "${owner}" ]]; then
        local hit_var="HITS_${owner}"
        local cur_hits=${!hit_var:-0}
        eval "${hit_var}=$((cur_hits + 1))"
        BS_BOARD_REMAINING_SEGMENTS=$((BS_BOARD_REMAINING_SEGMENTS - 1))
        if ((BS_BOARD_REMAINING_SEGMENTS < 0)); then BS_BOARD_REMAINING_SEGMENTS=0; fi
    fi
    return 0
}

bs_board_set_miss() {
    local r="${1}" c="${2}"
    local k; k=$(_bs_key "${r}" "${c}")
    eval "MOCK_CELLSTATE_${k}='miss'"
    eval "MOCK_OWNER_${k}=''"
    return 0
}

bs_board_ship_is_sunk() {
    local raw_ship="${1:-}"
    local placed_var="PLACED_${raw_ship}"
    local hit_var="HITS_${raw_ship}"
    local placed=${!placed_var:-0}
    local hits=${!hit_var:-0}
    if ((placed == 0)); then printf "false"; return 0; fi
    if ((hits >= placed)); then printf "true"; else printf "false"; fi
    return 0
}

bs_ship_name() {
    local raw="${1:-}"
    local cap="${raw^}"
    printf "%s" "${cap}"
}

bs_board_ship_remaining_segments() {
    local raw_ship="${1:-}"
    local placed_var="PLACED_${raw_ship}"
    local hit_var="HITS_${raw_ship}"
    local placed=${!placed_var:-0}
    local hits=${!hit_var:-0}
    local rem=$((placed - hits))
    if ((rem < 0)); then rem=0; fi
    printf "%d" "$rem"
}

bs_board_is_win() {
    if ((BS_BOARD_REMAINING_SEGMENTS == 0)); then
        printf "true"
    else
        printf "false"
    fi
}
EOF
	chmod +x "${out}" || true
}

@test "Unit - human turn with valid miss: validates coordinate, calls bs_board_set_miss, increments shots and misses, and emits miss event" {
	TMPDIR_TEST=$(mktemp -d)
	deps_path="${TMPDIR_TEST}/deps_batch_0.sh"
	te_write_deps_batch_0 "${deps_path}"
	# shellcheck disable=SC1091
	. "${deps_path}"
	# shellcheck disable=SC1091
	. "${BATS_TEST_DIRNAME}/turn_engine.sh"

	te_init || fail "te_init failed"

	cbfile="${TMPDIR_TEST}/cb.out"
	# Reorder fields so field 3 is result, field 4 is ship_name (we pass $5 there)
	te_shot_cb_batch_0() {
		printf "%s|%s|%s|%s|%s|%s\n" \
			"$1" "$2" "$3" \
			"${5:-}" "${4:-}" "${6:-}" >>"${cbfile}"
	}
	te_set_on_shot_result_callback "te_shot_cb_batch_0"

	# Shoot B2 (row=1,col=1) where nothing is placed
	te_human_shoot "B2" || fail "human shoot failed"

	# Stats should be: shots=1 hits=0 misses=1
	stats=$(te_stats_get)
	[ "${stats}" = "1 0 1" ]

	# Verify callback recorded a miss (field 3)
	result=$(awk -F'|' 'NR==1{print $3}' "${cbfile}")
	[ "${result}" = "miss" ]

	rm -rf "${TMPDIR_TEST}"
}

@test "Unit - human turn with valid hit (not sunk): validates coordinate, calls bs_board_set_hit, increments shots and hits, and emits hit event" {
	TMPDIR_TEST=$(mktemp -d)
	deps_path="${TMPDIR_TEST}/deps_batch_0.sh"
	te_write_deps_batch_0 "${deps_path}"
	# shellcheck disable=SC1091
	. "${deps_path}"
	# shellcheck disable=SC1091
	. "${BATS_TEST_DIRNAME}/turn_engine.sh"

	te_init || fail "te_init failed"

	# Prepare a ship segment at B2 (row=1,col=1)
	MOCK_CELLSTATE_1_1="ship"
	MOCK_OWNER_1_1="destroyer"
	PLACED_destroyer=2
	HITS_destroyer=0
	BS_BOARD_REMAINING_SEGMENTS=2

	cbfile="${TMPDIR_TEST}/cb.out"
	te_shot_cb_batch_0() {
		printf "%s|%s|%s|%s|%s|%s\n" \
			"$1" "$2" "$3" \
			"${5:-}" "${4:-}" "${6:-}" >>"${cbfile}"
	}
	te_set_on_shot_result_callback "te_shot_cb_batch_0"

	te_human_shoot "B2" || fail "human shoot failed"

	stats=$(te_stats_get)
	[ "${stats}" = "1 1 0" ]

	# Verify callback recorded a hit (field 3)
	result=$(awk -F'|' 'NR==1{print $3}' "${cbfile}")
	[ "${result}" = "hit" ]

	rm -rf "${TMPDIR_TEST}"
}

@test "Unit - human turn causing ship sunk: bs_board_set_hit results in bs_board_ship_is_sunk true and turn_engine emits sunk event using bs_ship_name" {
	TMPDIR_TEST=$(mktemp -d)
	deps_path="${TMPDIR_TEST}/deps_batch_0.sh"
	te_write_deps_batch_0 "${deps_path}"
	# shellcheck disable=SC1091
	. "${deps_path}"
	# shellcheck disable=SC1091
	. "${BATS_TEST_DIRNAME}/turn_engine.sh"

	te_init || fail "te_init failed"

	MOCK_CELLSTATE_2_2="ship"
	MOCK_OWNER_2_2="submarine"
	PLACED_submarine=1
	HITS_submarine=0
	BS_BOARD_REMAINING_SEGMENTS=2 # ensure not final win

	cbfile="${TMPDIR_TEST}/cb.out"
	te_shot_cb_batch_0() {
		printf "%s|%s|%s|%s|%s|%s\n" \
			"$1" "$2" "$3" \
			"${5:-}" "${4:-}" "${6:-}" >>"${cbfile}"
	}
	te_set_on_shot_result_callback "te_shot_cb_batch_0"

	# Fire at C3 -> row=2 col=2
	te_human_shoot "C3" || fail "human shoot failed"

	stats=$(te_stats_get)
	[ "${stats}" = "1 1 0" ]

	# First callback should indicate sunk (field 3)
	first_result=$(awk -F'|' 'NR==1{print $3}' "${cbfile}")
	[ "${first_result}" = "sunk" ]

	# Ensure ship name is present in the event (4th field)
	shipname=$(awk -F'|' 'NR==1{print $4}' "${cbfile}")
	[ "${shipname}" = "Submarine" ]

	rm -rf "${TMPDIR_TEST}"
}

@test "Unit - human turn causing final fleet destruction: after hit turn_engine emits win event and updates stats" {
	TMPDIR_TEST=$(mktemp -d)
	deps_path="${TMPDIR_TEST}/deps_batch_0.sh"
	te_write_deps_batch_0 "${deps_path}"
	# shellcheck disable=SC1091
	. "${deps_path}"
	# shellcheck disable=SC1091
	. "${BATS_TEST_DIRNAME}/turn_engine.sh"

	te_init || fail "te_init failed"

	MOCK_CELLSTATE_0_0="ship"
	MOCK_OWNER_0_0="destroyer"
	PLACED_destroyer=1
	HITS_destroyer=0
	BS_BOARD_REMAINING_SEGMENTS=1

	cbfile="${TMPDIR_TEST}/cb.out"
	te_shot_cb_batch_0() {
		printf "%s|%s|%s|%s|%s|%s\n" \
			"$1" "$2" "$3" \
			"${5:-}" "${4:-}" "${6:-}" >>"${cbfile}"
	}
	te_set_on_shot_result_callback "te_shot_cb_batch_0"

	te_human_shoot "A1" || fail "human shoot failed"

	stats=$(te_stats_get)
	[ "${stats}" = "1 1 0" ]

	# There should be at least two events appended: one sunk, one win
	has_sunk=0
	has_win=0
	while IFS= read -r line; do
		res=$(printf "%s" "${line}" | awk -F'|' '{print $3}')
		if [ "${res}" = "sunk" ]; then has_sunk=1; fi
		if [ "${res}" = "win" ]; then has_win=1; fi
	done <"${cbfile}"

	[ "${has_sunk}" -eq 1 ]
	[ "${has_win}" -eq 1 ]

	rm -rf "${TMPDIR_TEST}"
}

@test "Unit - duplicate shot at already-hit cell: bs_board_set_hit idempotent, stats unchanged, no duplicate hit event" {
	TMPDIR_TEST=$(mktemp -d)
	deps_path="${TMPDIR_TEST}/deps_batch_0.sh"
	te_write_deps_batch_0 "${deps_path}"
	# shellcheck disable=SC1091
	. "${deps_path}"
	# shellcheck disable=SC1091
	. "${BATS_TEST_DIRNAME}/turn_engine.sh"

	te_init || fail "te_init failed"

	# Pre-mark D4 as already hit
	MOCK_CELLSTATE_3_3="hit"
	MOCK_OWNER_3_3="cruiser"
	PLACED_cruiser=3
	HITS_cruiser=1
	BS_BOARD_REMAINING_SEGMENTS=5

	cbfile="${TMPDIR_TEST}/cb.out"
	te_shot_cb_batch_0() {
		printf "%s|%s|%s|%s|%s|%s\n" \
			"$1" "$2" "$3" \
			"${5:-}" "${4:-}" "${6:-}" >>"${cbfile}"
	}
	te_set_on_shot_result_callback "te_shot_cb_batch_0"

	# Attempt duplicate shot at D4
	te_human_shoot "D4" || fail "human shoot failed"

	# Stats should remain zero because earlier te_init reset and we didn't count this as new shot
	stats=$(te_stats_get)
	[ "${stats}" = "0 0 0" ]

	# Callback should indicate already_shot (field 3)
	res=$(awk -F'|' 'NR==1{print $3}' "${cbfile}")
	[ "${res}" = "already_shot" ]

	rm -rf "${TMPDIR_TEST}"
}
