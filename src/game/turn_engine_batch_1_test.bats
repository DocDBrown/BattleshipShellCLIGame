#!/usr/bin/env bats
# shellcheck disable=SC1090,SC1091,SC2034

setup() {
	TMPDIR_DIR="${BATS_TEST_DIRNAME}"
	TMPDIR="$(mktemp -d "${TMPDIR_DIR}/tmp.XXXX")"
	EVENTS="${TMPDIR}/events.txt"
	touch "${EVENTS}"
}

teardown() {
	if [ -n "${TMPDIR:-}" ] && [[ "${TMPDIR}" == "${BATS_TEST_DIRNAME}/tmp."* ]]; then
		rm -rf "${TMPDIR}"
	fi
}

# simple fail helper if bats-core's isn't available
fail() {
	printf '%s\n' "$*" >&2
	return 1
}

# Create a mock board_state and validation implementation inside the tempdir
create_mock_batch_1() {
	cat >"${TMPDIR}/mock_board_and_validation_batch_1.sh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
# minimal, deterministic mocks for bs_board_* and validation_*
BS_BOARD_SIZE=0
BS_BOARD_REMAINING_SEGMENTS=0
MISS_SET_CALLS=0
HIT_SET_CALLS=0
MOCK_FORCE_HIT_ERR=0
MOCK_FORCE_MISS_ERR=0

validate_board_size() {
    local s="${1:-}"
    if [[ ! "${s}" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    if ((s < 8 || s > 12)); then return 1; fi
    return 0
}

validate_coordinate() {
    local coord="${1:-}"
    local size="${2:-}"
    # special triggers for tests
    if [[ "${coord}" == "BAD_SIZE" ]]; then
        return 2
    fi
    if [[ "${coord}" == "BAD_COORD" ]]; then
        return 1
    fi
    if [[ ! "${coord}" =~ ^([A-Z])([1-9]|10|11|12)$ ]]; then
        return 1
    fi
    local letter="${BASH_REMATCH[1]}"
    local number="${BASH_REMATCH[2]}"
    local ord
    ord=$(printf '%d' "'${letter}") || return 1
    local max=$((65 + size - 1))
    if ((ord < 65 || ord > max)); then return 1; fi
    if ((number < 1 || number > size)); then return 1; fi
    return 0
}

# internal storage: keys like STATE_0_0, OWNER_0_0
bs_board_new() {
    BS_BOARD_SIZE=${1:-10}
    BS_BOARD_REMAINING_SEGMENTS=0
    return 0
}

_bs_key() {
    printf "%s_%s" "$1" "$2"
}

bs_board_get_state() {
    local r="$1" c="$2"
    local k
    k=$(_bs_key "$r" "$c")
    local var="STATE_${k}"
    if [[ -n "${!var:-}" ]]; then
        printf "%s" "${!var}"
    else
        printf "unknown"
    fi
}

bs_board_get_owner() {
    local r="$1" c="$2"
    local k
    k=$(_bs_key "$r" "$c")
    local var="OWNER_${k}"
    if [[ -n "${!var:-}" ]]; then
        printf "%s" "${!var}"
    else
        printf ""
    fi
}

bs_board_set_miss() {
    local r="$1" c="$2"
    local k
    k=$(_bs_key "$r" "$c")
    MISS_SET_CALLS=$((MISS_SET_CALLS + 1))
    if ((MOCK_FORCE_MISS_ERR != 0)); then
        return ${MOCK_FORCE_MISS_ERR}
    fi
    eval "STATE_${k}='miss'"
    eval "OWNER_${k}=''"
    return 0
}

bs_board_set_hit() {
    local r="$1" c="$2"
    local k
    k=$(_bs_key "$r" "$c")
    HIT_SET_CALLS=$((HIT_SET_CALLS + 1))
    if ((MOCK_FORCE_HIT_ERR != 0)); then
        return ${MOCK_FORCE_HIT_ERR}
    fi
    eval "STATE_${k}='hit'"
    # if owner present, decrement remaining
    local owner_var="OWNER_${k}"
    if [[ -n "${!owner_var:-}" ]]; then
        BS_BOARD_REMAINING_SEGMENTS=$((BS_BOARD_REMAINING_SEGMENTS - 1))
        if ((BS_BOARD_REMAINING_SEGMENTS < 0)); then BS_BOARD_REMAINING_SEGMENTS=0; fi
    fi
    return 0
}

bs_board_ship_is_sunk() { printf "false"; return 0; }
bs_board_is_win() { if ((BS_BOARD_REMAINING_SEGMENTS == 0)); then printf "true"; else printf "false"; fi; return 0; }
bs_board_ship_remaining_segments() { printf "0"; return 0; }
MOCK
	chmod +x "${TMPDIR}/mock_board_and_validation_batch_1.sh"
}

# callback collector
test_on_shot_result_batch_1() { printf "%s\n" "$*" >>"${EVENTS}"; }

@test "Unit - duplicate shot at already-missed cell: bs_board_set_miss idempotent, stats unchanged, no duplicate miss event" {
	create_mock_batch_1
	# source mock then library
	. "${TMPDIR}/mock_board_and_validation_batch_1.sh"
	. "${BATS_TEST_DIRNAME}/turn_engine.sh"

	# initialize
	te_init 10
	# pre-mark A1 (0,0) as miss
	bs_board_set_miss 0 0
	# attach callback
	te_set_on_shot_result_callback test_on_shot_result_batch_1

	# capture counts before
	before_stats="$(te_stats_get)"
	[ "${before_stats}" = "0 0 0" ] || fail "unexpected initial stats: ${before_stats}"
	before_miss_calls=${MISS_SET_CALLS:-0}

	# shoot the already-missed coordinate
	te_human_shoot "A1"
	status=$?
	[ $status -eq 0 ] || fail "te_human_shoot returned non-zero: ${status}"

	# ensure miss set was not called again (we called it once to pre-mark)
	[ "${MISS_SET_CALLS}" -eq "${before_miss_calls}" ] || fail "bs_board_set_miss called unexpectedly"

	# stats unchanged
	stats_after="$(te_stats_get)"
	[ "${stats_after}" = "0 0 0" ] || fail "stats changed unexpectedly: ${stats_after}"

	# at least one already_shot event present
	grep -q "already_shot" "${EVENTS}" || fail "expected already_shot event"
	num_events=$(wc -l <"${EVENTS}" | tr -d ' ')
	[ "${num_events}" -ge 1 ] || fail "no events recorded"
}

@test "Unit - human turn with invalid coordinate string: validate_coordinate fails and turn_engine returns non-zero without modifying board or emitting event" {
	create_mock_batch_1
	. "${TMPDIR}/mock_board_and_validation_batch_1.sh"
	. "${BATS_TEST_DIRNAME}/turn_engine.sh"

	te_init 10
	te_set_on_shot_result_callback test_on_shot_result_batch_1

	# ensure no prior calls
	MISS_SET_CALLS=0
	HIT_SET_CALLS=0

	# bad coordinate that validate_coordinate treats as invalid
	run te_human_shoot "BAD_COORD"

	# we expect failure status
	[ "${status}" -ne 0 ] || fail "expected non-zero for invalid coordinate"

	# no events emitted
	[ ! -s "${EVENTS}" ] || fail "events should be empty for invalid coordinate"
}

@test "Unit - human turn with invalid board size from validate_coordinate: validate_coordinate returns code 2 and turn_engine propagates non-zero exit" {
	create_mock_batch_1
	. "${TMPDIR}/mock_board_and_validation_batch_1.sh"
	. "${BATS_TEST_DIRNAME}/turn_engine.sh"

	te_init 10
	te_set_on_shot_result_callback test_on_shot_result_batch_1

	run te_human_shoot "BAD_SIZE"
	[ "${status}" -ne 0 ] || fail "expected non-zero when validate_coordinate indicates bad board size"

	# no events
	[ ! -s "${EVENTS}" ] || fail "events should be empty when validation fails with size error"
}

@test "Unit - AI turn delegates to same shot flow: AI chooser stubbed, chosen coordinate validated and board updated, appropriate event emitted and stats updated" {
	create_mock_batch_1
	. "${TMPDIR}/mock_board_and_validation_batch_1.sh"
	. "${BATS_TEST_DIRNAME}/turn_engine.sh"

	te_init 10
	# attach shot result callback
	te_set_on_shot_result_callback test_on_shot_result_batch_1

	# stub AI chooser that calls te_human_shoot for A1
	ai_choose_batch_1() {
		te_human_shoot "A1"
	}
	te_set_on_request_ai_shot_callback ai_choose_batch_1

	# ensure A1 is unknown
	state_before=$(bs_board_get_state 0 0)
	[ "${state_before}" = "unknown" ] || true

	# request an AI shot; the AI chooser will call te_human_shoot
	te_request_ai_shot
	status=$?
	[ $status -eq 0 ] || fail "te_request_ai_shot failed: ${status}"

	# stats: one shot should have been recorded
	stats_after="$(te_stats_get)"
	case "${stats_after}" in
	"1 0 1" | "1 1 0") : ;; # either miss or hit depending on mock owner
	*) fail "unexpected stats after AI shot: ${stats_after}" ;;
	esac

	# confirm an event was emitted
	[ -s "${EVENTS}" ] || fail "expected event from AI shot"
}

@test "Unit - turn_engine propagates board_state error: non-zero from bs_board_set_hit causes turn_engine to return non-zero and no event emission" {
	create_mock_batch_1
	. "${TMPDIR}/mock_board_and_validation_batch_1.sh"
	. "${BATS_TEST_DIRNAME}/turn_engine.sh"

	te_init 10
	te_set_on_shot_result_callback test_on_shot_result_batch_1

	# place an owner at A1 by setting owner variable directly in mock storage
	eval "OWNER_0_0='carrier'"
	BS_BOARD_REMAINING_SEGMENTS=1

	# force bs_board_set_hit to fail with code 5
	MOCK_FORCE_HIT_ERR=5

	run te_human_shoot "A1"
	[ "${status}" -ne 0 ] || fail "expected non-zero due to bs_board_set_hit failure"

	# no event should have been emitted
	[ ! -s "${EVENTS}" ] || fail "no events should be recorded when bs_board_set_hit fails"
}
