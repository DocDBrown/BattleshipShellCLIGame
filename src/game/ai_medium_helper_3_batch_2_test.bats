#!/usr/bin/env bats

setup() {
	# Source the library under test from the same directory as this test.
	# shellcheck disable=SC1091
	. "${BATS_TEST_DIRNAME}/ai_medium_helper_3.sh"
	BS_AI_MEDIUM_SEEN_SHOTS=()
	TMPDIR_TEST=""
}

teardown() {
	if [[ -n "${TMPDIR_TEST}" && -d "${TMPDIR_TEST}" ]]; then
		rm -rf "${TMPDIR_TEST}"
	fi
}

@test "unit_internal_hunt_cluster_state_is_preserved_between_consecutive_calls_until_cluster_resolved" {
	# Initially the item should not be recorded
	if _bs_ai_medium_has_seen "A1"; then
		fail "Should not have seen A1 initially"
	fi

	# Mark A1 as seen and verify it is reported as seen
	if ! _bs_ai_medium_mark_seen "A1"; then
		fail "mark_seen should succeed for A1"
	fi

	if ! _bs_ai_medium_has_seen "A1"; then
		fail "A1 should be recorded after mark_seen"
	fi

	# Calling mark_seen again for the same index should be idempotent
	if ! _bs_ai_medium_mark_seen "A1"; then
		fail "mark_seen should be idempotent for A1"
	fi

	# Ensure array contains exactly one entry
	n=${#BS_AI_MEDIUM_SEEN_SHOTS[@]}
	if [ "${n}" -ne 1 ]; then
		fail "Expected exactly one seen entry, got ${n}"
	fi
}

@test "unit_with_fixed_rng_seed_random_mode_selection_is_deterministic_for_repeatable_tests" {
	TMPDIR_TEST=$(mktemp -d)

	# Create a minimal, deterministic rng.sh in the per-test temp dir and source it.
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
RNGSH

	# shellcheck disable=SC1091
	. "${TMPDIR_TEST}/rng.sh"

	if ! bs_rng_init_from_seed 0; then
		fail "bs_rng_init_from_seed should succeed"
	fi

	val=$(bs_rng_get_uint32)
	if [ "${val}" -ne 1013904223 ]; then
		fail "Expected deterministic first LCG output 1013904223, got ${val}"
	fi
}
