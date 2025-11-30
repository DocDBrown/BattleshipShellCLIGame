#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

TE__ON_SHOT_RESULT_CB=""
TE__ON_REQUEST_AI_SHOT_CB=""
TE__STATS_SHOTS=0
TE__STATS_HITS=0
TE__STATS_MISSES=0
# Parsed coordinates populated by te__parse_coord_to_zero_based
TE__PARSED_R=""
TE__PARSED_C=""

te__require_fn() {
	local fn="${1:-}"
	if [ -z "${fn}" ]; then
		return 2
	fi
	if ! type "${fn}" >/dev/null 2>&1; then
		return 3
	fi
	return 0
}

te_init() {
	local size="${1:-10}"

	# Board creation helper is required
	if ! te__require_fn bs_board_new >/dev/null 2>&1; then
		return 10
	fi

	# Board size validation is optional: use when available, but don't hard-fail
	# if projects/tests haven't provided validate_board_size.
	if te__require_fn validate_board_size >/dev/null 2>&1; then
		validate_board_size "${size}" || return 12
	fi

	bs_board_new "${size}" || return 13

	TE__STATS_SHOTS=0
	TE__STATS_HITS=0
	TE__STATS_MISSES=0
	return 0
}

te_reset_stats() {
	TE__STATS_SHOTS=0
	TE__STATS_HITS=0
	TE__STATS_MISSES=0
	return 0
}

te_set_on_shot_result_callback() {
	local fn="${1:-}"
	if [ -z "${fn}" ]; then
		TE__ON_SHOT_RESULT_CB=""
		return 0
	fi
	te__require_fn "${fn}" || return 2
	TE__ON_SHOT_RESULT_CB="${fn}"
	return 0
}

te_set_on_request_ai_shot_callback() {
	local fn="${1:-}"
	if [ -z "${fn}" ]; then
		TE__ON_REQUEST_AI_SHOT_CB=""
		return 0
	fi
	te__require_fn "${fn}" || return 2
	TE__ON_REQUEST_AI_SHOT_CB="${fn}"
	return 0
}

te_stats_get() {
	printf "%d %d %d" "${TE__STATS_SHOTS}" "${TE__STATS_HITS}" "${TE__STATS_MISSES}"
}

te__parse_coord_to_zero_based() {
	local coord="${1:-}"
	local size_current=${BS_BOARD_SIZE:-0}

	if [ -z "${coord}" ]; then
		return 1
	fi

	# Optional external validator; if present, we require it to pass.
	if te__require_fn validate_coordinate >/dev/null 2>&1; then
		if ! validate_coordinate "${coord}" "${size_current}"; then
			# "invalid format" as reported by the external validator
			return 3
		fi
	fi

	# Internal validation and parsing: A1 through (at most) row/col 12.
	# This is independent of validate_coordinate, so tests can stub that as needed.
	if [[ ! "${coord}" =~ ^([A-Z])([1-9][0-9]*)$ ]]; then
		# syntactically invalid (e.g. "5A")
		return 4
	fi
	local letter="${BASH_REMATCH[1]}"
	local number="${BASH_REMATCH[2]}"

	# Require BS_BOARD_SIZE to be sane
	if [[ ! "${size_current}" =~ ^[0-9]+$ ]] || [ "${size_current}" -le 0 ]; then
		return 5
	fi

	local ord
	ord=$(printf '%d' "'${letter}") || return 6
	local row=$((ord - 65))
	local col=$((number - 1))

	if ((row < 0 || col < 0 || row >= size_current || col >= size_current)); then
		# geometrically out of bounds (e.g. "Z99")
		return 6
	fi

	TE__PARSED_R="${row}"
	TE__PARSED_C="${col}"
	return 0
}

te_human_shoot() {
	local coord="${1:-}"
	if [ -z "${coord}" ]; then
		return 1
	fi
	if ! te__require_fn bs_board_get_state >/dev/null 2>&1; then
		return 20
	fi

	te__parse_coord_to_zero_based "${coord}" || return 2

	local r="${TE__PARSED_R}"
	local c="${TE__PARSED_C}"

	local cur_state
	cur_state=$(bs_board_get_state "${r}" "${c}") || return 3

	# Already resolved cell: report via callback but do not change stats or board.
	if [[ "${cur_state}" == "hit" || "${cur_state}" == "miss" ]]; then
		if [ -n "${TE__ON_SHOT_RESULT_CB}" ] && te__require_fn "${TE__ON_SHOT_RESULT_CB}" >/dev/null 2>&1; then
			"${TE__ON_SHOT_RESULT_CB}" "human" "${coord}" "already_shot" "" "" \
				"${TE__STATS_SHOTS}" "${TE__STATS_HITS}" "${TE__STATS_MISSES}" || true
		fi
		return 0
	fi

	TE__STATS_SHOTS=$((TE__STATS_SHOTS + 1))

	local owner
	if te__require_fn bs_board_get_owner >/dev/null 2>&1; then
		owner=$(bs_board_get_owner "${r}" "${c}") || owner=""
	else
		owner=""
	fi

	if [ -n "${owner}" ]; then
		# Ship present -> hit path
		if ! te__require_fn bs_board_set_hit >/dev/null 2>&1; then
			return 21
		fi
		bs_board_set_hit "${r}" "${c}" || return 4
		TE__STATS_HITS=$((TE__STATS_HITS + 1))

		local sunk="false"
		if te__require_fn bs_board_ship_is_sunk >/dev/null 2>&1; then
			sunk=$(bs_board_ship_is_sunk "${owner}") || sunk="false"
		fi

		local ship_name=""
		if te__require_fn bs_ship_name >/dev/null 2>&1; then
			ship_name=$(bs_ship_name "${owner}") || ship_name=""
		fi

		local remaining=""
		if te__require_fn bs_board_ship_remaining_segments >/dev/null 2>&1; then
			remaining=$(bs_board_ship_remaining_segments "${owner}") || remaining=""
		fi

		if [ -n "${TE__ON_SHOT_RESULT_CB}" ] && te__require_fn "${TE__ON_SHOT_RESULT_CB}" >/dev/null 2>&1; then
			if [[ "${sunk}" == "true" ]]; then
				"${TE__ON_SHOT_RESULT_CB}" "human" "${coord}" "sunk" "${owner}" "${ship_name}" \
					"${TE__STATS_SHOTS}" "${TE__STATS_HITS}" "${TE__STATS_MISSES}" "${remaining}" || true
			else
				"${TE__ON_SHOT_RESULT_CB}" "human" "${coord}" "hit" "${owner}" "${ship_name}" \
					"${TE__STATS_SHOTS}" "${TE__STATS_HITS}" "${TE__STATS_MISSES}" "${remaining}" || true
			fi
		fi

		local win="false"
		if te__require_fn bs_board_is_win >/dev/null 2>&1; then
			win=$(bs_board_is_win) || win="false"
		fi
		if [[ "${win}" == "true" ]]; then
			if [ -n "${TE__ON_SHOT_RESULT_CB}" ] && te__require_fn "${TE__ON_SHOT_RESULT_CB}" >/dev/null 2>&1; then
				"${TE__ON_SHOT_RESULT_CB}" "human" "${coord}" "win" "${owner}" "${ship_name}" \
					"${TE__STATS_SHOTS}" "${TE__STATS_HITS}" "${TE__STATS_MISSES}" "0" || true
			fi
		fi

		return 0
	else
		# Miss path
		if ! te__require_fn bs_board_set_miss >/dev/null 2>&1; then
			return 22
		fi
		bs_board_set_miss "${r}" "${c}" || return 5
		TE__STATS_MISSES=$((TE__STATS_MISSES + 1))

		if [ -n "${TE__ON_SHOT_RESULT_CB}" ] && te__require_fn "${TE__ON_SHOT_RESULT_CB}" >/dev/null 2>&1; then
			"${TE__ON_SHOT_RESULT_CB}" "human" "${coord}" "miss" "" "" \
				"${TE__STATS_SHOTS}" "${TE__STATS_HITS}" "${TE__STATS_MISSES}" || true
		fi
		return 0
	fi
}

te_request_ai_shot() {
	if [ -z "${TE__ON_REQUEST_AI_SHOT_CB}" ]; then
		return 1
	fi
	te__require_fn "${TE__ON_REQUEST_AI_SHOT_CB}" || return 2
	"${TE__ON_REQUEST_AI_SHOT_CB}" || return 3
	return 0
}

# public API: functions are defined above; no top-level execution
