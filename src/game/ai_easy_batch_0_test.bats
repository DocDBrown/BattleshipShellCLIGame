#!/usr/bin/env bats

setup() {
	# Create a temporary directory for dependencies
	TEST_TEMP_DIR="$(mktemp -d)"

	# Write rng.sh dependency
	cat <<'EOF' >"$TEST_TEMP_DIR/rng.sh"
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

	# Write board_state.sh dependency
	cat <<'EOF' >"$TEST_TEMP_DIR/board_state.sh"
#!/usr/bin/env bash
set -o nounset
set -o pipefail

BS__THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
if [[ -f "${BS__THIS_DIR}/ship_rules.sh" ]]; then
	. "${BS__THIS_DIR}/ship_rules.sh"
fi

BS_BOARD_SIZE=0
BS_BOARD_TOTAL_SEGMENTS=0
BS_BOARD_REMAINING_SEGMENTS=0
_BS_BOARD_SEEN_SHIPS=""
_BS_RET_R=0
_BS_RET_C=0

_bs_board__sanitize_for_var() {
	printf "%s" "${1//[^a-zA-Z0-9]/_}"
}

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

	# Source dependencies
	# shellcheck source=/dev/null
	source "$TEST_TEMP_DIR/rng.sh"
	# shellcheck source=/dev/null
	source "$TEST_TEMP_DIR/board_state.sh"

	# Source the system under test
	# shellcheck source=/dev/null
	source "${BATS_TEST_DIRNAME}/ai_easy.sh"
}

teardown() {
	if [[ -n "${TEST_TEMP_DIR:-}" && -d "$TEST_TEMP_DIR" ]]; then
		rm -rf "$TEST_TEMP_DIR"
	fi
}

@test "bs_ai_easy_init_default_creates_10x10_target_list_with_100_unique_cells" {
	# Initialize board state (required for integration)
	bs_board_new 10

	# Call init directly to set globals in this process
	bs_ai_easy_init 10 12345

	# Verify initialization flag
	[ "${BS_AI_EASY_INITIALIZED:-0}" -eq 1 ]

	# Verify array size
	[ "${#BS_AI_EASY_REMAINING_SHOTS[@]}" -eq 100 ]

	# Verify uniqueness of cells
	local unique_count
	unique_count=$(printf "%s\n" "${BS_AI_EASY_REMAINING_SHOTS[@]}" | sort | uniq | wc -l)
	# Trim whitespace from wc output
	unique_count=${unique_count// /}
	[ "$unique_count" -eq 100 ]
}

@test "bs_ai_easy_init_with_1x1_board_initializes_single_target" {
	bs_board_new 1
	bs_ai_easy_init 1 12345

	[ "${#BS_AI_EASY_REMAINING_SHOTS[@]}" -eq 1 ]
	[ "${BS_AI_EASY_REMAINING_SHOTS[0]}" = "0:0" ]

	# Verify choose_shot works for this single target
	run bs_ai_easy_choose_shot
	[ "$status" -eq 0 ]
	[ "$output" = "0 0" ]
}

@test "bs_ai_easy_init_with_invalid_size_returns_nonzero_and_does_not_create_targets" {
	# Ensure clean state
	BS_AI_EASY_INITIALIZED=0

	run bs_ai_easy_init -5
	[ "$status" -eq 3 ]
	[ "${BS_AI_EASY_INITIALIZED:-0}" -ne 1 ]
}

@test "bs_ai_easy_init_is_idempotent_multiple_calls_do_not_duplicate_targets" {
	bs_board_new 10

	# First init
	bs_ai_easy_init 10 12345
	[ "${#BS_AI_EASY_REMAINING_SHOTS[@]}" -eq 100 ]

	# Second init
	bs_ai_easy_init 10 67890
	[ "${#BS_AI_EASY_REMAINING_SHOTS[@]}" -eq 100 ]
}

@test "bs_ai_easy_choose_shot_before_init_returns_nonzero_error_and_no_coordinate" {
	# Ensure uninitialized
	BS_AI_EASY_INITIALIZED=0

	run bs_ai_easy_choose_shot
	[ "$status" -eq 2 ]
	[[ "$output" == *"not initialized"* ]]
}
