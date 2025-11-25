#!/usr/bin/env bats
# shellcheck disable=SC1090,SC1091

setup() {
	TMPDIR="$(mktemp -d)"

	# Minimal ship_rules implementation for this batch
	cat >"${TMPDIR}/ship_rules.sh" <<'SH_RULES'
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Return a human-readable ship name; default behaviour: capitalise first letter
bs_ship_name() {
	local raw="${1:-}"
	if [ -z "${raw}" ]; then
		printf "\n"
		return 0
	fi
	raw=${raw,,}
	printf "%s\n" "${raw^}"
}

# The rest of these helpers are stubs sufficient for this batch of tests

bs_ship_list() {
	printf "%s\n" "carrier" "battleship" "cruiser" "submarine" "destroyer"
}

bs_ship_length() {
	local t="${1:-}"
	t=${t,,}
	case "${t}" in
		destroyer) printf "2\n" ;;
		*) printf "1\n" ;;
	esac
}

bs_total_segments() {
	printf "0\n"
}

bs_validate_fleet() {
	return 0
}

bs_ship_is_sunk() {
	# Not needed for this batch; return false by default
	printf "false\n"
	return 0
}

bs_ship_remaining_segments() {
	printf "0\n"
	return 0
}
SH_RULES

	# Validation helpers: board size and coordinate checks
	cat >"${TMPDIR}/validation.sh" <<'VALID'
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

_validate_board_size() {
	local s="${1}"
	if [[ ! "${s}" =~ ^[0-9]+$ ]]; then
		return 1
	fi
	if ((s < 8 || s > 12)); then
		return 1
	fi
	return 0
}

validate_board_size() {
	_validate_board_size "${@}"
}

validate_coordinate() {
	local coord="${1}"
	local size="${2}"

	if ! _validate_board_size "${size}"; then
		return 2
	fi
	if [ -z "${coord}" ]; then
		return 1
	fi

	# strict uppercase coordinates per specification
	if [[ ! "${coord}" =~ ^([A-Z])([1-9]|10|11|12)$ ]]; then
		return 1
	fi

	local letter="${BASH_REMATCH[1]}"
	local number="${BASH_REMATCH[2]}"
	local ord
	ord=$(printf '%d' "'${letter}") || return 1
	local max=$((65 + size - 1))
	if ((ord < 65 || ord > max)); then
		return 1
	fi
	if ((number < 1 || number > size)); then
		return 1
	fi

	return 0
}

validate_ai_difficulty() {
	local d="${1}"
	case "${d}" in
		easy | medium | hard) return 0 ;;
		*) return 1 ;;
	esac
}

is_non_empty_string() {
	[ -n "${1-}" ] && return 0 || return 1
}

is_safe_filename() {
	local fn="${1}"
	if [ -z "${fn}" ]; then
		return 1
	fi
	if [[ "${fn}" == -* ]]; then
		return 1
	fi
	if [[ "${fn}" == */* ]]; then
		return 1
	fi
	if [[ "${fn}" == *".."* ]]; then
		return 1
	fi
	if printf '%s' "${fn}" | LC_ALL=C grep -q '[[:cntrl:]]'; then
		return 1
	fi
	if printf '%s' "${fn}" | grep -q '[[:space:]]'; then
		return 1
	fi
	return 0
}
VALID

	# Minimal in-memory board implementation tailored for this batch
	cat >"${TMPDIR}/board_state.sh" <<'BOARD'
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Global board state
BS_BOARD_SIZE=0
BS_BOARD_REMAINING_SEGMENTS=0

_bs_key() {
	printf "%s_%s" "$1" "$2"
}

bs_board_new() {
	local n="${1:-10}"
	BS_BOARD_SIZE="${n}"
	BS_BOARD_REMAINING_SEGMENTS=0
	return 0
}

bs_board_get_state() {
	local r="${1:-}" c="${2:-}"
	local k; k=$(_bs_key "${r}" "${c}")
	local var="BS_CELLSTATE_${k}"
	if [ -n "${!var+x}" ]; then
		printf "%s" "${!var}"
	else
		printf "unknown"
	fi
}

bs_board_get_owner() {
	local r="${1:-}" c="${2:-}"
	local k; k=$(_bs_key "${r}" "${c}")
	local var="BS_OWNER_${k}"
	if [ -n "${!var+x}" ]; then
		printf "%s" "${!var}"
	else
		printf ""
	fi
}

bs_board_set_ship() {
	local r="${1:-}" c="${2:-}" ship="${3:-}"
	if [ -z "${ship}" ]; then
		printf "Missing ship type\n" >&2
		return 2
	fi
	local k; k=$(_bs_key "${r}" "${c}")
	local state_var="BS_CELLSTATE_${k}"
	local owner_var="BS_OWNER_${k}"
	local cur_state="${!state_var:-}"
	local cur_owner="${!owner_var:-}"

	# Idempotent: same ship already placed at this cell
	if [ "${cur_state}" = "ship" ] && [ "${cur_owner}" = "${ship}" ]; then
		return 0
	fi

	# Only increment remaining segments if this cell was not a ship before
	if [ "${cur_state}" != "ship" ]; then
		BS_BOARD_REMAINING_SEGMENTS=$((BS_BOARD_REMAINING_SEGMENTS + 1))
	fi

	eval "${state_var}='ship'"
	eval "${owner_var}='${ship}'"
	return 0
}

bs_board_set_hit() {
	local r="${1:-}" c="${2:-}"
	local k; k=$(_bs_key "${r}" "${c}")
	local state_var="BS_CELLSTATE_${k}"
	local owner_var="BS_OWNER_${k}"
	local cur_state="${!state_var:-unknown}"
	local owner="${!owner_var:-}"

	# Already hit: idempotent
	if [ "${cur_state}" = "hit" ]; then
		return 0
	fi

	eval "${state_var}='hit'"

	# Only decrement remaining when we are hitting a ship segment
	if [ "${cur_state}" = "ship" ] && [ -n "${owner}" ]; then
		BS_BOARD_REMAINING_SEGMENTS=$((BS_BOARD_REMAINING_SEGMENTS - 1))
		if [ "${BS_BOARD_REMAINING_SEGMENTS}" -lt 0 ]; then
			BS_BOARD_REMAINING_SEGMENTS=0
		fi
	fi
	return 0
}

bs_board_set_miss() {
	local r="${1:-}" c="${2:-}"
	local k; k=$(_bs_key "${r}" "${c}")
	local state_var="BS_CELLSTATE_${k}"
	local owner_var="BS_OWNER_${k}"
	eval "${state_var}='miss'"
	eval "${owner_var}=''"
	return 0
}

bs_board_is_win() {
	if [ "${BS_BOARD_REMAINING_SEGMENTS}" -eq 0 ]; then
		printf "true"
	else
		printf "false"
	fi
}

bs_board_ship_is_sunk() {
	# This board implementation does not track per-ship counts; for the purposes
	# of these tests, treat any ship as "sunk" once all segments are gone.
	if [ "${BS_BOARD_REMAINING_SEGMENTS}" -eq 0 ]; then
		printf "true"
	else
		printf "false"
	fi
}

bs_board_ship_remaining_segments() {
	# Per-ship breakdown not tracked; tests in this batch do not inspect it,
	# so return 0 to indicate "no remaining segments" for any ship.
	printf "0"
}
BOARD

	# Source helpers and SUT in the current test shell
	# shellcheck disable=SC1091
	. "${TMPDIR}/ship_rules.sh"
	# shellcheck disable=SC1091
	. "${TMPDIR}/validation.sh"
	# shellcheck disable=SC1091
	. "${TMPDIR}/board_state.sh"
	# shellcheck disable=SC1091
	. "${BATS_TEST_DIRNAME}/turn_engine.sh"
}

te_cleanup_batch_2() {
	if [ -n "${TMPDIR:-}" ] && [ -d "${TMPDIR}" ]; then
		rm -rf "${TMPDIR}"
	fi
}

teardown() {
	te_cleanup_batch_2
}

fail() {
	printf '%s\n' "$*" >&2
	return 1
}

# AI-shot helper for this batch
te_ai_shot_callback_batch_2() {
	# deterministic AI: take A2 (row=0,col=1)
	te_human_shoot "A2"
}

@test "Unit - sequential turns accumulate stats correctly: multiple human and AI turns update total shots, hits, and misses as expected" {
	# initialize game with default size (10)
	te_init || fail "te_init failed"

	# place a 2-segment destroyer at A1 (0,0) and A2 (0,1)
	bs_board_set_ship 0 0 destroyer || fail "set ship segment 1"
	bs_board_set_ship 0 1 destroyer || fail "set ship segment 2"

	# register AI callback that will shoot at A2
	te_set_on_request_ai_shot_callback te_ai_shot_callback_batch_2 || fail "set ai cb"

	# human shoots A1 -> hit
	te_human_shoot "A1" || fail "human shoot A1"

	# request AI shot -> will invoke callback and shoot A2 -> hit
	te_request_ai_shot || fail "request ai shot"

	# human shoots B1 -> miss
	te_human_shoot "B1" || fail "human shoot B1 (miss)"

	stats="$(te_stats_get)"
	if [ "${stats}" != "3 2 1" ]; then
		echo "Expected stats '3 2 1', got: ${stats}"
		return 1
	fi
}
