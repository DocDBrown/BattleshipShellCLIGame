#!/usr/bin/env bats

# Deterministic RNG helpers for these tests
BS_RNG_MODE="auto"
BS_RNG_STATE=0

bs_rng_init_from_seed() {
	if [ $# -lt 1 ]; then
		return 2
	fi
	BS_RNG_MODE="lcg"
	BS_RNG_STATE=$(( $1 & 0xFFFFFFFF ))
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
	if [ "${BS_RNG_MODE:-auto}" = "lcg" ]; then
		bs_rng_lcg_next
		return 0
	fi
	od -An -tu4 -N4 /dev/urandom | tr -d ' \n'
}

bs_rng_int_range() {
	if [ $# -ne 2 ]; then
		return 2
	fi
	local min=$1 max=$2
	if [ "$min" -gt "$max" ]; then
		return 2
	fi
	local span=$((max - min + 1))
	while :; do
		local v
		v="$(bs_rng_get_uint32)"
		if [ -z "$v" ]; then
			continue
		fi
		local r=$((v % span))
		printf "%d\n" "$((min + r))"
		return 0
	done
}

parse_shot() {
	local IFS=' '
	# shellcheck disable=SC2086
	set -- $1
	if [ $# -ne 2 ]; then
		return 1
	fi
	r=$1
	c=$2
	return 0
}

setup() {
	# shellcheck disable=SC1091
	. "${BATS_TEST_DIRNAME}/ai_medium.sh"
}

@test "test_ai_medium_random_initial_shot_with_seeded_bs_rng_is_deterministic_and_reproducible" {
	bs_ai_medium_init 5 12345
	shot1="$(bs_ai_medium_choose_shot)"

	bs_ai_medium_init 5 12345
	shot2="$(bs_ai_medium_choose_shot)"

	[ "${shot1}" = "${shot2}" ]
}

@test "test_ai_medium_random_initial_shot_is_within_board_bounds_and_not_previously_targeted" {
	local size=4
	local r c
	bs_ai_medium_init "${size}"
	shot="$(bs_ai_medium_choose_shot)"

	if ! parse_shot "${shot}"; then
		echo "shot '${shot}' did not contain two coordinates" >&2
		return 1
	fi

	[ "${r}" -ge 0 ]
	[ "${r}" -lt "${size}" ]
	[ "${c}" -ge 0 ]
	[ "${c}" -lt "${size}" ]

	idx=$((r * size + c))
	[ "${BS_AI_MEDIUM_CELLSTATES[idx]}" = "unknown" ]
}

@test "test_ai_medium_enters_hunt_mode_after_hit_and_targets_adjacent_cells_up_down_left_right" {
	bs_ai_medium_init 5
	local r c

	# Place a hit at (2,2)
	bs_ai_medium_record_result 2 2 hit

	shot="$(bs_ai_medium_choose_shot)"

	if ! parse_shot "${shot}"; then
		echo "shot '${shot}' did not contain two coordinates" >&2
		return 1
	fi

	ok=0
	if [ "${r}" -eq 1 ] && [ "${c}" -eq 2 ]; then ok=1; fi
	if [ "${r}" -eq 3 ] && [ "${c}" -eq 2 ]; then ok=1; fi
	if [ "${r}" -eq 2 ] && [ "${c}" -eq 1 ]; then ok=1; fi
	if [ "${r}" -eq 2 ] && [ "${c}" -eq 3 ]; then ok=1; fi

	[ "${ok}" -eq 1 ]
}

@test "test_ai_medium_hunt_mode_respects_board_boundaries_and_skips_out_of_bounds_neighbors" {
	bs_ai_medium_init 3
	local r c
	# Hit at top-left corner
	bs_ai_medium_record_result 0 0 hit

	shot="$(bs_ai_medium_choose_shot)"

	if ! parse_shot "${shot}"; then
		echo "shot '${shot}' did not contain two coordinates" >&2
		return 1
	fi

	ok=0
	if [ "${r}" -eq 1 ] && [ "${c}" -eq 0 ]; then ok=1; fi
	if [ "${r}" -eq 0 ] && [ "${c}" -eq 1 ]; then ok=1; fi
	[ "${ok}" -eq 1 ]
}

@test "test_ai_medium_hunt_mode_skips_already_targeted_neighbors_and_selects_other_available_neighbors" {
	bs_ai_medium_init 3
	local r c

	# Pre-mark one neighbor as miss so it should be skipped when enqueueing
	bs_ai_medium_record_result 1 2 miss
	# Now record a hit at (1,1); neighbors are (0,1),(2,1),(1,0),(1,2) but (1,2) is already targeted
	bs_ai_medium_record_result 1 1 hit

	shot="$(bs_ai_medium_choose_shot)"

	if ! parse_shot "${shot}"; then
		echo "shot '${shot}' did not contain two coordinates" >&2
		return 1
	fi

	# Must not be already-targeted neighbor (1,2)
	if [ "${r}" -eq 1 ] && [ "${c}" -eq 2 ]; then
		echo "AI selected already-targeted neighbor (1,2)" >&2
		return 1
	fi

	ok=0
	if [ "${r}" -eq 0 ] && [ "${c}" -eq 1 ]; then ok=1; fi
	if [ "${r}" -eq 2 ] && [ "${c}" -eq 1 ]; then ok=1; fi
	if [ "${r}" -eq 1 ] && [ "${c}" -eq 0 ]; then ok=1; fi

	[ "${ok}" -eq 1 ]
}