#!/usr/bin/env bats

setup() {
	SCRIPT="${BATS_TEST_DIRNAME}/rng.sh"
}

teardown() {
	:
}

@test "bs_rng_init_from_seed_enables_deterministic_mode_and_makes_subsequent_ints_reproducible" {
	S="$SCRIPT" run bash -c 'source "$S"; bs_rng_init_from_seed 12345; echo "$(bs_rng_get_uint32)"; echo "$(bs_rng_get_uint32)"; echo "$(bs_rng_get_uint32)"'
	[ "$status" -eq 0 ]
	first="$output"

	S="$SCRIPT" run bash -c 'source "$S"; bs_rng_init_from_seed 12345; echo "$(bs_rng_get_uint32)"; echo "$(bs_rng_get_uint32)"; echo "$(bs_rng_get_uint32)"'
	[ "$status" -eq 0 ]
	[ "$first" = "$output" ]
}

@test "bs_rng_int_range_seeded_returns_value_within_bounds_for_positive_range" {
	S="$SCRIPT" run bash -c 'source "$S"; bs_rng_init_from_seed 424242; for i in $(seq 1 20); do v=$(bs_rng_int_range 1 6); if [ -z "$v" ]; then echo "empty"; exit 2; fi; if [ "$v" -lt 1 ] || [ "$v" -gt 6 ]; then echo "out:$v"; exit 3; fi; echo "$v"; done'
	[ "$status" -eq 0 ]
}

@test "bs_rng_int_range_seeded_min_equals_max_returns_that_value" {
	S="$SCRIPT" run bash -c 'source "$S"; bs_rng_init_from_seed 7; v=$(bs_rng_int_range 5 5); printf "%s\n" "$v"'
	[ "$status" -eq 0 ]
	[ "$output" = "5" ]
}

@test "bs_rng_int_range_seeded_handles_negative_range_and_returns_value_within_bounds" {
	S="$SCRIPT" run bash -c 'source "$S"; bs_rng_init_from_seed 31415; for i in $(seq 1 20); do v=$(bs_rng_int_range -5 5); if [ -z "$v" ]; then echo "empty"; exit 2; fi; if [ "$v" -lt -5 ] || [ "$v" -gt 5 ]; then echo "out:$v"; exit 3; fi; echo "$v"; done'
	[ "$status" -eq 0 ]
}

@test "bs_rng_int_range_seeded_same_seed_produces_identical_sequence_across_invocations" {
	S="$SCRIPT" run bash -c 'source "$S"; bs_rng_init_from_seed 2025; for i in $(seq 1 10); do echo "$(bs_rng_int_range 0 100)"; done'
	[ "$status" -eq 0 ]
	seq1="$output"

	S="$SCRIPT" run bash -c 'source "$S"; bs_rng_init_from_seed 2025; for i in $(seq 1 10); do echo "$(bs_rng_int_range 0 100)"; done'
	[ "$status" -eq 0 ]
	[ "$seq1" = "$output" ]
}
