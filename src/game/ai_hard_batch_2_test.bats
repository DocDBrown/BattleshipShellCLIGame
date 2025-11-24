#!/usr/bin/env bats

setup() {
	BS_TMP_DIR=$(mktemp -d)
	mkdir -p "${BS_TMP_DIR}"

	cat >"${BS_TMP_DIR}/rng.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
BS_RNG_MODE="auto"
BS_RNG_STATE=0
BS_RNG_MODULO=4294967296
bs_rng_init_from_seed() {
	if [ $# -lt 1 ]; then
		return 2
	fi
	local seed=$1
	BS_RNG_MODE="lcg"
	BS_RNG_STATE=$((seed & 0xFFFFFFFF))
	return 0
}
bs_rng_init_auto() {
	BS_RNG_MODE="auto"
	BS_RNG_STATE=0
	return 0
}
bs_rng_lcg_next() {
	BS_RNG_STATE=$(((BS_RNG_STATE * 1664525 + 1013904223) & 0xFFFFFFFF))
	printf "%u" "$BS_RNG_STATE"
}
bs_rng_get_uint32() {
	if [ "$BS_RNG_MODE" = "lcg" ]; then
		bs_rng_lcg_next
		return 0
	fi
	od -An -tu4 -N4 /dev/urandom | tr -d ' \n'
}
bs_rng_int_range() {
	if [ $# -ne 2 ]; then
		return 2
	fi
	local min=$1
	local max=$2
	if [ "$min" -gt "$max" ]; then
		return 2
	fi
	local span=$((max - min + 1))
	if [ "$span" -le 0 ]; then
		printf "%d\n" "$min"
		return 0
	fi
	if [ "$span" -eq 1 ]; then
		printf "%d\n" "$min"
		return 0
	fi
	local threshold=$(((BS_RNG_MODULO / span) * span))
	while :; do
		local v
		v=$(bs_rng_get_uint32)
		if [ -z "$v" ]; then
			continue
		fi
		if [ "$v" -lt "$threshold" ]; then
			local r=$((v % span))
			printf "%d\n" "$((min + r))"
			return 0
		fi
	done
}
bs_rng_shuffle() {
	local -a arr=()
	if [ $# -gt 0 ]; then
		arr=("$@")
	else
		local i=0
		while IFS= read -r line; do
			arr[i]="$line"
			i=$((i + 1))
		done
	fi
	local n=${#arr[@]}
	if [ "$n" -le 1 ]; then
		for item in "${arr[@]}"; do
			printf "%s\n" "$item"
		done
		return 0
	fi
	local i j tmp
	for ((i = n - 1; i > 0; i--)); do
		j=$(bs_rng_int_range 0 $i)
		tmp="${arr[i]}"
		arr[i]="${arr[j]}"
		arr[j]="$tmp"
	done
	for item in "${arr[@]}"; do
		printf "%s\n" "$item"
	done
}
EOF

	cat >"${BS_TMP_DIR}/board_state.sh" <<'EOF'
#!/usr/bin/env bash
set -o nounset
set -o pipefail
BS_BOARD_SIZE=0
BS_BOARD_TOTAL_SEGMENTS=0
BS_BOARD_REMAINING_SEGMENTS=0
_BS_BOARD_SEEN_SHIPS=""
_BS_RET_R=0
_BS_RET_C=0
_bs_board__sanitize_for_var() { printf "%s" "${1//[^a-zA-Z0-9]/_}"; }
bs_board__normalize_coord() {
	local raw_r="${1:-}"
	local raw_c="${2:-}"
	if [[ -z "$raw_r" || -z "$raw_c" ]]; then
		return 1
	fi
	if [[ ! "$raw_r" =~ ^[0-9]+$ ]] || [[ ! "$raw_c" =~ ^[0-9]+$ ]]; then
		return 1
	fi
	local r=$((raw_r + 1))
	local c=$((raw_c + 1))
	if ((r < 1 || r > BS_BOARD_SIZE || c < 1 || c > BS_BOARD_SIZE)); then
		return 2
	fi
	_BS_RET_R=$r
	_BS_RET_C=$c
	return 0
}
bs_board_new() {
	local n=${1:-10}
	if [[ ! "$n" =~ ^[1-9][0-9]*$ ]]; then
		printf "Invalid board size: %s\n" "$n" >&2
		return 1
	fi
	BS_BOARD_SIZE=$n
	BS_BOARD_TOTAL_SEGMENTS=0
	BS_BOARD_REMAINING_SEGMENTS=0
	local ship sanitized_ship
	for ship in $_BS_BOARD_SEEN_SHIPS; do
		sanitized_ship=$(_bs_board__sanitize_for_var "$ship")
		unset "BS_BOARD_SHIP_SEGMENTS_${sanitized_ship}" || true
		unset "BS_BOARD_HITS_BY_SHIP_${sanitized_ship}" || true
	done
	_BS_BOARD_SEEN_SHIPS=""
	local r c key var_name_state var_name_owner
	for ((r = 1; r <= BS_BOARD_SIZE; r++)); do
		for ((c = 1; c <= BS_BOARD_SIZE; c++)); do
			key="${r}_${c}"
			var_name_state="BS_BOARD_CELLSTATE_${key}"
			var_name_owner="BS_BOARD_OWNER_${key}"
			eval "${var_name_state}='unknown'"
			eval "${var_name_owner}=''"
		done
	done
	return 0
}
bs_board_in_bounds() {
	bs_board__normalize_coord "$1" "$2" || return 1
	printf "%d %d" "$_BS_RET_R" "$_BS_RET_C"
}
bs_board_get_state() {
	bs_board__normalize_coord "$1" "$2" || {
		printf "Coordinates out of bounds: %s %s\n" "$1" "$2" >&2
		return 2
	}
	local key="${_BS_RET_R}_${_BS_RET_C}"
	local var_name="BS_BOARD_CELLSTATE_${key}"
	if [[ -n "${!var_name+x}" ]]; then
		printf "%s" "${!var_name}"
	else
		printf "unknown"
	fi
}
bs_board_get_owner() {
	bs_board__normalize_coord "$1" "$2" || {
		printf "Coordinates out of bounds: %s %s\n" "$1" "$2" >&2
		return 2
	}
	local key="${_BS_RET_R}_${_BS_RET_C}"
	local var_name="BS_BOARD_OWNER_${key}"
	if [[ -n "${!var_name+x}" ]]; then
		printf "%s" "${!var_name}"
	else
		printf ""
	fi
}
bs_board__inc_ship_segment() {
	local ship="$1"
	if [[ ! " $_BS_BOARD_SEEN_SHIPS " =~ " ${ship} " ]]; then
		_BS_BOARD_SEEN_SHIPS="${_BS_BOARD_SEEN_SHIPS} ${ship}"
	fi
	local sanitized_ship=$(_bs_board__sanitize_for_var "$ship")
	local seg_var="BS_BOARD_SHIP_SEGMENTS_${sanitized_ship}"
	local cur_segs="${!seg_var:-0}"
	eval "${seg_var}=$((cur_segs + 1))"
	BS_BOARD_TOTAL_SEGMENTS=$((BS_BOARD_TOTAL_SEGMENTS + 1))
	BS_BOARD_REMAINING_SEGMENTS=$((BS_BOARD_REMAINING_SEGMENTS + 1))
}
bs_board_set_ship() {
	local raw_r="$1" raw_c="$2" raw_ship="${3:-}"
	if [[ -z "$raw_ship" ]]; then
		printf "Missing ship type\n" >&2
		return 2
	fi
	local ship="${raw_ship,,}"
	bs_board__normalize_coord "$raw_r" "$raw_c" || {
		printf "Coordinates out of bounds: %s %s\n" "$raw_r" "$raw_c" >&2
		return 4
	}
	local key="${_BS_RET_R}_${_BS_RET_C}"
	local state_var="BS_BOARD_CELLSTATE_${key}"
	local owner_var="BS_BOARD_OWNER_${key}"
	local cur_state="${!state_var:-unknown}"
	local cur_owner="${!owner_var:-}"
	if [[ "$cur_state" == "ship" && "$cur_owner" == "$ship" ]]; then
		return 0
	fi
	if [[ "$cur_state" == "ship" && -n "$cur_owner" && "$cur_owner" != "$ship" ]]; then
		local sanitized_cur_owner=$(_bs_board__sanitize_for_var "$cur_owner")
		local seg_var="BS_BOARD_SHIP_SEGMENTS_${sanitized_cur_owner}"
		local cur_segs="${!seg_var:-0}"
		eval "${seg_var}=$((cur_segs - 1))"
		BS_BOARD_TOTAL_SEGMENTS=$((BS_BOARD_TOTAL_SEGMENTS - 1))
		BS_BOARD_REMAINING_SEGMENTS=$((BS_BOARD_REMAINING_SEGMENTS - 1))
		if ((BS_BOARD_REMAINING_SEGMENTS < 0)); then
			BS_BOARD_REMAINING_SEGMENTS=0
		fi
	fi
	bs_board__inc_ship_segment "$ship"
	eval "${state_var}='ship'"
	eval "${owner_var}='${ship}'"
	return 0
}
bs_board_set_hit() {
	local raw_r="$1" raw_c="$2"
	bs_board__normalize_coord "$raw_r" "$raw_c" || {
		printf "Coordinates out of bounds: %s %s\n" "$raw_r" "$raw_c" >&2
		return 2
	}
	local key="${_BS_RET_R}_${_BS_RET_C}"
	local state_var="BS_BOARD_CELLSTATE_${key}"
	local owner_var="BS_BOARD_OWNER_${key}"
	local cur_state="${!state_var:-unknown}"
	local owner="${!owner_var:-}"
	if [[ "$cur_state" == "hit" ]]; then
		return 0
	fi
	eval "${state_var}='hit'"
	if [[ -n "$owner" && "$cur_state" == "ship" ]]; then
		local sanitized_owner=$(_bs_board__sanitize_for_var "$owner")
		local hit_var="BS_BOARD_HITS_BY_SHIP_${sanitized_owner}"
		local cur_hits="${!hit_var:-0}"
		eval "${hit_var}=$((cur_hits + 1))"
		BS_BOARD_REMAINING_SEGMENTS=$((BS_BOARD_REMAINING_SEGMENTS - 1))
		if ((BS_BOARD_REMAINING_SEGMENTS < 0)); then
			BS_BOARD_REMAINING_SEGMENTS=0
		fi
	fi
	return 0
}
bs_board_set_miss() {
	local raw_r="$1" raw_c="$2"
	bs_board__normalize_coord "$raw_r" "$raw_c" || {
		printf "Coordinates out of bounds: %s %s\n" "$raw_r" "$raw_c" >&2
		return 2
	}
	local key="${_BS_RET_R}_${_BS_RET_C}"
	eval "BS_BOARD_CELLSTATE_${key}='miss'"
	eval "BS_BOARD_OWNER_${key}=''"
	return 0
}
bs_board_total_remaining_segments() {
	printf "%d" "$BS_BOARD_REMAINING_SEGMENTS"
}
bs_board_ship_is_sunk() {
	local raw_ship="${1:-}"
	if [[ -z "$raw_ship" ]]; then
		printf "Invalid ship type: %s\n" "$raw_ship" >&2
		return 2
	fi
	local ship="${raw_ship,,}"
	local sanitized_ship=$(_bs_board__sanitize_for_var "$ship")
	local placed_var="BS_BOARD_SHIP_SEGMENTS_${sanitized_ship}"
	local hits_var="BS_BOARD_HITS_BY_SHIP_${sanitized_ship}"
	local placed="${!placed_var:-0}"
	local hits="${!hits_var:-0}"
	if ((placed == 0)); then
		printf "false"
		return 0
	fi
	if ((hits >= placed)); then
		printf "true"
	else
		printf "false"
	fi
	return 0
}
bs_board_is_win() {
	if ((BS_BOARD_REMAINING_SEGMENTS == 0)); then
		printf "true"
		return 0
	fi
	printf "false"
	return 0
}
bs_board_ship_remaining_segments() {
	local raw_ship="${1:-}"
	if [[ -z "$raw_ship" ]]; then
		printf "Invalid ship type: %s\n" "$raw_ship" >&2
		return 2
	fi
	local ship="${raw_ship,,}"
	local sanitized_ship=$(_bs_board__sanitize_for_var "$ship")
	local placed_var="BS_BOARD_SHIP_SEGMENTS_${sanitized_ship}"
	local hits_var="BS_BOARD_HITS_BY_SHIP_${sanitized_ship}"
	local placed="${!placed_var:-0}"
	local hits="${!hits_var:-0}"
	local rem=$((placed - hits))
	if ((rem < 0)); then
		rem=0
	fi
	printf "%d" "$rem"
	return 0
}
EOF

	cp "${BATS_TEST_DIRNAME}/ai_hard.sh" "${BS_TMP_DIR}/ai_hard.sh"

	# shellcheck disable=SC1091
	source "${BS_TMP_DIR}/rng.sh"
	# shellcheck disable=SC1091
	source "${BS_TMP_DIR}/board_state.sh"
	# shellcheck disable=SC1091
	source "${BS_TMP_DIR}/ai_hard.sh"

	bs_rng_init_from_seed 123
	bs_board_new 5
	bs_ai_hard_init
}

teardown() {
	if [ -n "${BS_TMP_DIR:-}" ] && [ -d "${BS_TMP_DIR}" ]; then
		rm -f "${BS_TMP_DIR}/rng.sh" "${BS_TMP_DIR}/board_state.sh" "${BS_TMP_DIR}/ai_hard.sh"
		rmdir "${BS_TMP_DIR}" 2>/dev/null || true
	fi
}

@test "unit_ai_hard_does_not_read_hidden_layout_and_uses_only_reported_outcomes" {
	bs_board_set_ship 0 0 destroyer

	local visited_before=${BS_AI_HARD_VISITED_1_1:-}
	[ -z "$visited_before" ]

	local shot
	shot=$(bs_ai_hard_choose_shot)
	[ -n "$shot" ]

	local r c
	r=${shot%% *}
	c=${shot##* }
	[ "$r" -ge 1 ]
	[ "$r" -le "$BS_BOARD_SIZE" ]
	[ "$c" -ge 1 ]
	[ "$c" -le "$BS_BOARD_SIZE" ]

	bs_ai_hard_notify_result "$r" "$c" miss
	local visited_after_var="BS_AI_HARD_VISITED_${r}_${c}"
	[ "${!visited_after_var:-}" = 1 ]
}

@test "unit_ai_hard_is_idempotent_when_receiving_duplicate_outcome_reports" {
	bs_rng_init_from_seed 42
	bs_board_new 4
	bs_ai_hard_init

	local shot
	shot=$(bs_ai_hard_choose_shot)
	local r=${shot%% *}
	local c=${shot##* }

	bs_ai_hard_notify_result "$r" "$c" hit
	local queue_len1=${#BS_AI_HARD_TARGET_QUEUE_R[@]}
	local hits_len1=${#BS_AI_HARD_HITS_R[@]}

	bs_ai_hard_notify_result "$r" "$c" hit
	local queue_len2=${#BS_AI_HARD_TARGET_QUEUE_R[@]}
	local hits_len2=${#BS_AI_HARD_HITS_R[@]}

	[ "$queue_len1" -eq "$queue_len2" ]
	[ "$hits_len1" -eq "$hits_len2" ]
}

@test "unit_ai_hard_prefers_continuing_existing_target_hunts_over_random_scouting" {
	bs_rng_init_from_seed 7
	bs_board_new 4
	bs_ai_hard_init

	bs_ai_hard_notify_result 2 2 hit

	local next
	next=$(bs_ai_hard_choose_shot)
	local nr=${next%% *}
	local nc=${next##* }

	[ "$nr" -ge 1 ]
	[ "$nr" -le "$BS_BOARD_SIZE" ]
	[ "$nc" -ge 1 ]
	[ "$nc" -le "$BS_BOARD_SIZE" ]

	[ $((nr == 1 && nc == 2 || nr == 3 && nc == 2 || nr == 2 && nc == 1 || nr == 2 && nc == 3)) -eq 1 ]
}

@test "unit_ai_hard_selects_among_multiple_partial_hunts_consistently_using_priority_and_rng_ties" {
	bs_rng_init_from_seed 99
	bs_board_new 5
	bs_ai_hard_init

	bs_ai_hard_notify_result 2 2 hit
	bs_ai_hard_notify_result 4 4 hit

	unset BS_AI_HARD_VISITED_3_2
	unset BS_AI_HARD_VISITED_1_2

	local choice1 choice2
	choice1=$(bs_ai_hard_choose_shot)
	bs_ai_hard_notify_result ${choice1%% *} ${choice1##* } miss
	choice2=$(bs_ai_hard_choose_shot)

	[ "$choice1" != "$choice2" ]
}

@test "unit_ai_hard_returns_no_move_when_all_board_cells_are_exhausted" {
	bs_rng_init_from_seed 5
	bs_board_new 3
	bs_ai_hard_init

	local r c
	for ((r = 1; r <= BS_BOARD_SIZE; r++)); do
		for ((c = 1; c <= BS_BOARD_SIZE; c++)); do
			local v="BS_AI_HARD_VISITED_${r}_${c}"
			eval "${v}=1"
		done
	done

	run bs_ai_hard_choose_shot
	[ "$status" -ne 0 ]
	[ -z "$output" ]
}
