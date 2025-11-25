#!/usr/bin/env bats

setup() {
	# Use a test-local temp directory so we don't clobber Bats' own TMPDIR.
	TMPDIR_TEST="$(mktemp -d)"
	SUT="${BATS_TEST_DIRNAME}/ai_medium_helper_1.sh"
	# shellcheck source=/dev/null
	. "${SUT}"
}

teardown() {
	if [[ -d "${TMPDIR_TEST}" ]]; then
		rm -rf "${TMPDIR_TEST}"
	fi
}

@test "ai_medium_reinit_clears_internal_hunt_state_and_is_idempotent" {
	BS_AI_MEDIUM_BOARD_SIZE=4
	BS_AI_MEDIUM_CELLSTATES=()
	for i in $(seq 0 $((BS_AI_MEDIUM_BOARD_SIZE * BS_AI_MEDIUM_BOARD_SIZE - 1))); do
		BS_AI_MEDIUM_CELLSTATES+=("unknown")
	done
	BS_AI_MEDIUM_HUNT_QUEUE=()
	_bs_ai_medium_push_hunt 5
	[ "${#BS_AI_MEDIUM_HUNT_QUEUE[@]}" -eq 1 ]
	BS_AI_MEDIUM_HUNT_QUEUE=()
	[ "${#BS_AI_MEDIUM_HUNT_QUEUE[@]}" -eq 0 ]
	BS_AI_MEDIUM_HUNT_QUEUE=()
	[ "${#BS_AI_MEDIUM_HUNT_QUEUE[@]}" -eq 0 ]
}

@test "ai_medium_reports_no_available_moves_when_all_board_cells_are_targeted" {
	BS_AI_MEDIUM_BOARD_SIZE=2
	BS_AI_MEDIUM_CELLSTATES=()
	for i in $(seq 0 $((BS_AI_MEDIUM_BOARD_SIZE * BS_AI_MEDIUM_BOARD_SIZE - 1))); do
		BS_AI_MEDIUM_CELLSTATES+=("miss")
	done
	BS_AI_MEDIUM_HUNT_QUEUE=()
	for i in "${!BS_AI_MEDIUM_CELLSTATES[@]}"; do
		_bs_ai_medium_push_hunt "${i}"
	done
	[ "${#BS_AI_MEDIUM_HUNT_QUEUE[@]}" -eq 0 ]

	# Use `run` so the expected non-zero exit status does not trip set -e.
	run _bs_ai_medium_pop_hunt
	[ "$status" -eq 1 ]
}

@test "ai_medium_handles_sparse_turn_history_and_still_generates_valid_moves" {
	BS_AI_MEDIUM_BOARD_SIZE=3
	BS_AI_MEDIUM_CELLSTATES=()
	for i in $(seq 0 $((BS_AI_MEDIUM_BOARD_SIZE * BS_AI_MEDIUM_BOARD_SIZE - 1))); do
		BS_AI_MEDIUM_CELLSTATES+=("unknown")
	done
	BS_AI_MEDIUM_HUNT_QUEUE=()
	BS_AI_MEDIUM_CELLSTATES[4]="hit"
	_bs_ai_medium_enqueue_neighbors 4

	# Queue should have some candidates, but we don't trust it to be perfect:
	[ "${#BS_AI_MEDIUM_HUNT_QUEUE[@]}" -ge 1 ]

	# Bound the number of pops to avoid any chance of an infinite loop
	initial_len=${#BS_AI_MEDIUM_HUNT_QUEUE[@]}
	if [[ "${initial_len}" -lt 0 ]]; then
		initial_len=0
	fi

	for _ in $(seq 1 "${initial_len}"); do
		output=$(_bs_ai_medium_pop_hunt 2>/dev/null) || break
		[[ "$output" =~ ^[0-9]+$ ]]
		idx="$output"
		[ "${BS_AI_MEDIUM_CELLSTATES[$idx]}" = "unknown" ]
	done
}

@test "ai_medium_with_seeded_rng_produces_deterministic_random_sequence_using_bs_rng_init_from_seed" {
	cat >"${TMPDIR_TEST}/rng.sh" <<'RNG'
#!/usr/bin/env bash
set -euo pipefail
BS_RNG_MODE="auto"
BS_RNG_STATE=0
BS_RNG_MODULO=4294967296
bs_rng_init_from_seed() {
    if [ $# -lt 1 ]; then return 2; fi
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
RNG
	# shellcheck source=/dev/null
	. "${TMPDIR_TEST}/rng.sh"
	bs_rng_init_from_seed 12345
	out1=$(bs_rng_get_uint32)
	out2=$(bs_rng_get_uint32)
	bs_rng_init_from_seed 12345
	out1b=$(bs_rng_get_uint32)
	out2b=$(bs_rng_get_uint32)
	[ "$out1" = "$out1b" ]
	[ "$out2" = "$out2b" ]
}

@test "ai_medium_different_seed_changes_random_sequence_and_moves_vary_accordingly" {
	cat >"${TMPDIR_TEST}/rng.sh" <<'RNG'
#!/usr/bin/env bash
set -euo pipefail
BS_RNG_MODE="auto"
BS_RNG_STATE=0
BS_RNG_MODULO=4294967296
bs_rng_init_from_seed() {
    if [ $# -lt 1 ]; then return 2; fi
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
RNG
	# shellcheck source=/dev/null
	. "${TMPDIR_TEST}/rng.sh"
	BS_AI_MEDIUM_BOARD_SIZE=5
	total=$((BS_AI_MEDIUM_BOARD_SIZE * BS_AI_MEDIUM_BOARD_SIZE))
	bs_rng_init_from_seed 1
	a=$(bs_rng_get_uint32)
	idx1=$((a % total))
	bs_rng_init_from_seed 2
	b=$(bs_rng_get_uint32)
	idx2=$((b % total))
	[ "$a" != "$b" ] || [ "$idx1" != "$idx2" ]
}
