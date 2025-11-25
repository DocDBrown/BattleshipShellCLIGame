#!/usr/bin/env bats

setup() {
	# Create an isolated temporary workspace for per-test helper scripts
	TMPDIR_TEST="$(mktemp -d)"
	# Write a deterministic-compatible copy of rng.sh into TMPDIR_TEST
	cat >"${TMPDIR_TEST}/rng.sh" <<'RNGSH'
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
		j=$(bs_rng_int_range 0 "$i")
		tmp="${arr[i]}"
		arr[i]="${arr[j]}"
		arr[j]="$tmp"
	done
	for item in "${arr[@]}"; do
		printf "%s\n" "$item"
	done
}
RNGSH

	# Source the deterministic RNG so bs_ai_medium_init can use it
	# shellcheck disable=SC1091
	. "${TMPDIR_TEST}/rng.sh"

	# Source the system under test from the same directory as this test file
	# shellcheck disable=SC1091
	. "${BATS_TEST_DIRNAME}/ai_medium.sh"

	# Remember TMPDIR for teardown
	BATS_TMPDIR="${TMPDIR_TEST}"
}

teardown() {
	if [[ -n "${BATS_TMPDIR:-}" && -d "${BATS_TMPDIR}" ]]; then
		rm -rf "${BATS_TMPDIR}"
	fi
}

@test "test_ai_medium_shuffle_and_neighbor_choice_are_deterministic_when_rng_seed_and_history_are_identical" {
	# Initialize with a fixed seed
	bs_ai_medium_init 5 123
	# Sequence: miss, hit, miss (hunt), miss
	shots1=()

	shot="$(bs_ai_medium_choose_shot)"
	read -r r c <<<"$shot"
	shots1+=("$shot")
	# Ignore potential out-of-bounds errors; determinism is what we test
	bs_ai_medium_record_result "$r" "$c" miss || true

	shot="$(bs_ai_medium_choose_shot)"
	read -r r c <<<"$shot"
	shots1+=("$shot")
	bs_ai_medium_record_result "$r" "$c" hit || true

	shot="$(bs_ai_medium_choose_shot)"
	read -r r c <<<"$shot"
	shots1+=("$shot")
	bs_ai_medium_record_result "$r" "$c" miss || true

	shot="$(bs_ai_medium_choose_shot)"
	read -r r c <<<"$shot"
	shots1+=("$shot")
	bs_ai_medium_record_result "$r" "$c" miss || true

	seq1="${shots1[*]}"

	# Reinitialize and repeat identical history
	bs_ai_medium_init 5 123
	shots2=()

	shot="$(bs_ai_medium_choose_shot)"
	read -r r c <<<"$shot"
	shots2+=("$shot")
	bs_ai_medium_record_result "$r" "$c" miss || true

	shot="$(bs_ai_medium_choose_shot)"
	read -r r c <<<"$shot"
	shots2+=("$shot")
	bs_ai_medium_record_result "$r" "$c" hit || true

	shot="$(bs_ai_medium_choose_shot)"
	read -r r c <<<"$shot"
	shots2+=("$shot")
	bs_ai_medium_record_result "$r" "$c" miss || true

	shot="$(bs_ai_medium_choose_shot)"
	read -r r c <<<"$shot"
	shots2+=("$shot")
	bs_ai_medium_record_result "$r" "$c" miss || true

	seq2="${shots2[*]}"

	[ "${seq1}" = "${seq2}" ]
}

@test "test_ai_medium_excludes_miss_cells_in_both_random_and_hunt_modes_and_never_targets_confirmed_misses" {
	bs_ai_medium_init 4 42
	# Pre-mark confirmed misses
	bs_ai_medium_record_result 0 0 miss || true
	bs_ai_medium_record_result 1 1 miss || true

	# First random choice should not return any already-missed cell
	shot="$(bs_ai_medium_choose_shot)"
	read -r r c <<<"$shot"
	if [ "$r" -eq 0 ] && [ "$c" -eq 0 ]; then
		echo "AI selected a previously confirmed miss 0,0" >&2
		return 1
	fi
	if [ "$r" -eq 1 ] && [ "$c" -eq 1 ]; then
		echo "AI selected a previously confirmed miss 1,1" >&2
		return 1
	fi

	# Now test hunt mode: ensure neighbor that was previously marked miss is excluded
	bs_ai_medium_record_result 1 2 miss || true
	# Trigger a hit that would normally enqueue neighbors around whatever cell this is
	bs_ai_medium_record_result 2 2 hit || true
	shot="$(bs_ai_medium_choose_shot)"
	read -r hr hc <<<"$shot"
	if [ "$hr" -eq 1 ] && [ "$hc" -eq 2 ]; then
		echo "AI selected a neighbor that was previously marked miss 1,2" >&2
		return 1
	fi

	# Also ensure it never returns the original misses even after more picks
	# Simulate marking shots returned as misses to advance the state
	for _ in 1 2 3; do
		s="$(bs_ai_medium_choose_shot)"
		read -r rr rc <<<"$s"
		bs_ai_medium_record_result "$rr" "$rc" miss || true
		if { [ "$rr" -eq 0 ] && [ "$rc" -eq 0 ]; } ||
			{ [ "$rr" -eq 1 ] && [ "$rc" -eq 1 ]; } ||
			{ [ "$rr" -eq 1 ] && [ "$rc" -eq 2 ]; }; then
			echo "AI returned a previously confirmed miss during progression: ${rr},${rc}" >&2
			return 1
		fi
	done
}
