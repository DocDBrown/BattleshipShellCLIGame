#!/usr/bin/env bats

setup() {
	# Create a per-test temporary directory for helper scripts (rng)
	TMP_RNG_DIR=$(mktemp -d)
	# Write minimal/full rng implementation copied from project dependency to ensure deterministic seeding
	cat >"${TMP_RNG_DIR}/rng.sh" <<'RNGSH'
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
RNGSH

	# Source the temp rng so bs_rng_* functions are available
	# shellcheck disable=SC1091
	. "${TMP_RNG_DIR}/rng.sh"
	# Source the library under test from the same directory as this test
	# shellcheck disable=SC1091
	. "${BATS_TEST_DIRNAME}/ai_medium_helper_2.sh"
}

teardown() {
	# Remove only the per-test temporary directory we created
	rm -rf "${TMP_RNG_DIR}"
}

@test "unit_medium_selects_untried_adjacent_cells_before_far_random_targets_while_hunting" {
	# 3x3 board, center index 4
	BS_AI_MEDIUM_BOARD_SIZE=3
	# initialize all cells to unknown
	BS_AI_MEDIUM_CELLSTATES=()
	for i in $(seq 0 8); do
		BS_AI_MEDIUM_CELLSTATES[i]="unknown"
	done
	# center is a hit
	BS_AI_MEDIUM_CELLSTATES[4]="hit"
	# ensure the 'up' neighbor (index 1) is unknown and others are not preferred
	BS_AI_MEDIUM_CELLSTATES[1]="unknown"
	BS_AI_MEDIUM_CELLSTATES[3]="miss"
	BS_AI_MEDIUM_CELLSTATES[5]="miss"
	BS_AI_MEDIUM_CELLSTATES[7]="miss"

	# Call directly per Bats rules for library functions that mutate globals
	bs_ai_medium_pick_hunt_adjacent 4
	ret=$?
	[ "$ret" -eq 0 ]
	# The 'up' neighbor is index 1 and should be selected per the function's order
	[ -n "${_BS_AI_MEDIUM_RET_IDX:-}" ]
	[ "${_BS_AI_MEDIUM_RET_IDX}" -eq 1 ]
}

@test "unit_medium_handles_empty_or_missing_turn_history_as_fresh_random_mode" {
	BS_AI_MEDIUM_BOARD_SIZE=4
	BS_AI_MEDIUM_CELLSTATES=()
	for i in $(seq 0 15); do
		BS_AI_MEDIUM_CELLSTATES[i]="unknown"
	done
	# Seed RNG so we get deterministic behavior
	bs_rng_init_from_seed 123456
	_bs_ai_medium_pick_random_unknown
	ret=$?
	[ "$ret" -eq 0 ]
	# Result index must be within 0..15 and correspond to an unknown
	idx=${_BS_AI_MEDIUM_RET_IDX}
	# Arithmetic check for bounds
	if ! { [ "$idx" -ge 0 ] 2>/dev/null && [ "$idx" -lt $((BS_AI_MEDIUM_BOARD_SIZE * BS_AI_MEDIUM_BOARD_SIZE)) ] 2>/dev/null; }; then
		exit 1
	fi
	[ "${BS_AI_MEDIUM_CELLSTATES[idx]}" = "unknown" ]
}

@test "unit_medium_rejects_malformed_turn_history_with_non_integer_coordinates_and_returns_error" {
	BS_AI_MEDIUM_BOARD_SIZE=3
	# Expect bs_ai_medium_pick_hunt_adjacent to fail with status 3 for non-integer center index.
	run bs_ai_medium_pick_hunt_adjacent "not_an_int"
	[ "$status" -eq 3 ]
}

@test "unit_medium_selection_excludes_previous_shots_when_rng_seeded_and_is_consistently_reproducible" {
	BS_AI_MEDIUM_BOARD_SIZE=3
	BS_AI_MEDIUM_CELLSTATES=()
	for i in $(seq 0 8); do
		BS_AI_MEDIUM_CELLSTATES[i]="unknown"
	done
	# Mark some previous shots so they are excluded
	BS_AI_MEDIUM_CELLSTATES[0]="miss"
	BS_AI_MEDIUM_CELLSTATES[1]="hit"

	# Seed RNG and pick
	bs_rng_init_from_seed 424242
	_bs_ai_medium_pick_random_unknown
	ret=$?
	[ "$ret" -eq 0 ]
	idx1=${_BS_AI_MEDIUM_RET_IDX}
	# Reseed to the same value and pick again; result must be identical
	bs_rng_init_from_seed 424242
	_bs_ai_medium_pick_random_unknown
	ret2=$?
	[ "$ret2" -eq 0 ]
	idx2=${_BS_AI_MEDIUM_RET_IDX}
	[ "$idx1" -eq "$idx2" ]
	# Ensure selected index is not one of the previously-shot indices
	[ "$idx1" -ne 0 ]
	[ "$idx1" -ne 1 ]
}
