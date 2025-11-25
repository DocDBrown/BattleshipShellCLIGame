#!/usr/bin/env bats

# The BS_AI_MEDIUM_CELLSTATES array is used indirectly by helper functions,
# so shellcheck cannot see its reads. Suppress the "appears unused" warning.
# shellcheck disable=SC2034

# Fallback implementation of fail() so we don't depend on external helpers.
if ! declare -F fail >/dev/null 2>&1; then
	fail() {
		echo "$@" >&2
		return 1
	}
fi

setup() {
	# create a per-test temporary dir for helper scripts
	TMPDIR_TEST=$(mktemp -d)
	rngfile="$TMPDIR_TEST/rng.sh"
	cat >"$rngfile" <<'RNGSH'
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

	chmod +x "$rngfile"
	# shellcheck source=/dev/null
	. "$rngfile"

	# source the system under test from the same directory as this test
	# shellcheck disable=SC1091
	. "${BATS_TEST_DIRNAME}/ai_medium_helper_2.sh"
}

teardown() {
	rm -rf "$TMPDIR_TEST"
}

@test "unit_medium_random_mode_selects_unshot_cell_when_no_hits_and_seeded_returns_deterministic_cell" {
	BS_AI_MEDIUM_BOARD_SIZE=3
	# initialize all to unknown
	local total=$((BS_AI_MEDIUM_BOARD_SIZE * BS_AI_MEDIUM_BOARD_SIZE))
	for ((i = 0; i < total; i++)); do
		BS_AI_MEDIUM_CELLSTATES[i]='unknown'
	done

	bs_rng_init_from_seed 42
	if ! _bs_ai_medium_pick_random_unknown; then
		fail "expected selection to succeed"
	fi
	idx1=${_BS_AI_MEDIUM_RET_IDX}

	bs_rng_init_from_seed 42
	if ! _bs_ai_medium_pick_random_unknown; then
		fail "expected selection to succeed on re-seed"
	fi
	idx2=${_BS_AI_MEDIUM_RET_IDX}

	[ "$idx1" -eq "$idx2" ]
}

@test "unit_medium_random_mode_excludes_all_previous_shots_from_selection" {
	BS_AI_MEDIUM_BOARD_SIZE=2
	# total 4, mark three as known
	BS_AI_MEDIUM_CELLSTATES[0]='miss'
	BS_AI_MEDIUM_CELLSTATES[1]='hit'
	BS_AI_MEDIUM_CELLSTATES[2]='miss'
	BS_AI_MEDIUM_CELLSTATES[3]='unknown'

	bs_rng_init_from_seed 7
	if ! _bs_ai_medium_pick_random_unknown; then
		fail "expected selection to succeed when one unknown remains"
	fi
	[ "${_BS_AI_MEDIUM_RET_IDX}" -eq 3 ]
}

@test "unit_medium_rng_seed_determinism_produces_reproducible_choice_order" {
	# verify bs_rng_shuffle produces same order when seeded
	local -a arr=(a b c d e)
	bs_rng_init_from_seed 12345
	readarray -t seq1 < <(bs_rng_shuffle "${arr[@]}")
	bs_rng_init_from_seed 12345
	readarray -t seq2 < <(bs_rng_shuffle "${arr[@]}")
	# compare flattened sequences
	[ "${seq1[*]}" = "${seq2[*]}" ]
}

@test "unit_medium_hunt_mode_enters_after_receiving_a_hit_and_selects_adjacent_up_down_left_or_right" {
	BS_AI_MEDIUM_BOARD_SIZE=3
	# index layout (0..8): row-major
	# center at index 4 (row 1, col 1)
	local center_idx=4
	# initialize all to miss
	for ((i = 0; i < 9; i++)); do
		BS_AI_MEDIUM_CELLSTATES[i]='miss'
	done
	# center is hit
	BS_AI_MEDIUM_CELLSTATES[4]='hit'
	# set up neighbor (up) to unknown and others to miss
	BS_AI_MEDIUM_CELLSTATES[1]='unknown' # up
	BS_AI_MEDIUM_CELLSTATES[7]='miss'    # down
	BS_AI_MEDIUM_CELLSTATES[3]='miss'    # left
	BS_AI_MEDIUM_CELLSTATES[5]='miss'    # right

	if ! bs_ai_medium_pick_hunt_adjacent "$center_idx"; then
		fail "expected hunt pick to succeed when up neighbor is unknown"
	fi
	[ "${_BS_AI_MEDIUM_RET_IDX}" -eq 1 ]
}

@test "unit_medium_hunt_mode_does_not_select_diagonal_neighbors" {
	BS_AI_MEDIUM_BOARD_SIZE=3
	# center at index 4 (row 1, col 1)
	local center_idx=4
	# initialize all to miss
	for ((i = 0; i < 9; i++)); do
		BS_AI_MEDIUM_CELLSTATES[i]='miss'
	done
	# center is hit
	BS_AI_MEDIUM_CELLSTATES[4]='hit'
	# make a diagonal cell unknown while all orthogonal neighbours are non-unknown
	BS_AI_MEDIUM_CELLSTATES[0]='unknown' # diagonal up-left of center
	BS_AI_MEDIUM_CELLSTATES[1]='miss'    # up
	BS_AI_MEDIUM_CELLSTATES[3]='miss'    # left
	# right (5) and down (7) remain miss from initialisation loop

	# Should not pick diagonal; there are no orthogonal unknowns so expect failure
	if bs_ai_medium_pick_hunt_adjacent "$center_idx"; then
		fail "hunt pick should not select diagonal neighbors"
	fi
}
