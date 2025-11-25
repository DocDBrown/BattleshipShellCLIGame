#!/usr/bin/env bats
# shellcheck disable=SC1091

setup() {
	TEST_TMPDIR="$(mktemp -d)"

	cat >"${TEST_TMPDIR}/bs_rng_stub.sh" <<'EOF'
#!/usr/bin/env bash
BS_RNG_MODE="lcg"
BS_RNG_STATE=1
bs_rng_init_from_seed() {
	if [ $# -lt 1 ]; then
		return 2
	fi
	BS_RNG_STATE=$(( $1 & 0xFFFFFFFF ))
	BS_RNG_MODE="lcg"
	return 0
}
bs_rng_init_auto() {
	BS_RNG_MODE="auto"
	BS_RNG_STATE=0
	return 0
}
bs_rng_get_uint32() {
	BS_RNG_STATE=$(((BS_RNG_STATE * 1664525 + 1013904223) & 0xFFFFFFFF))
	printf "%u" "$BS_RNG_STATE"
}
bs_rng_int_range() {
	if [ $# -ne 2 ]; then
		return 2
	fi
	min=$1
	max=$2
	if [ "$min" -gt "$max" ]; then
		return 2
	fi
	span=$((max-min+1))
	if [ "$span" -le 1 ]; then
		printf "%d\n" "$min"
		return 0
	fi
	v="$(bs_rng_get_uint32)"
	r=$((v % span))
	printf "%d\n" "$((min + r))"
	return 0
}
EOF

	. "${TEST_TMPDIR}/bs_rng_stub.sh"

	CALLED_BOARD_GET_OWNER=0
	CALLED_BOARD_GET_STATE=0
	# shellcheck disable=SC2317
	bs_board_get_owner() {
		CALLED_BOARD_GET_OWNER=1
		return 0
	}
	# shellcheck disable=SC2317
	bs_board_get_state() {
		CALLED_BOARD_GET_STATE=1
		return 0
	}

	. "${BATS_TEST_DIRNAME}/ai_medium.sh"
}

teardown() {
	rm -rf "${TEST_TMPDIR}"
	unset BS_AI_MEDIUM_BOARD_SIZE BS_AI_MEDIUM_CELLSTATES BS_AI_MEDIUM_HUNT_QUEUE BS_AI_MEDIUM_SEEN_SHOTS || true
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

@test "test_ai_medium_maintains_hunt_cluster_across_multiple_turns_and_continues_probing_cluster_until_exhausted_or_sunk" {
	bs_ai_medium_init 4 42
	OUT="${TEST_TMPDIR}/out1"
	local r1 c1 r2 c2

	bs_ai_medium_choose_shot >"${OUT}"
	IFS=' ' read -r r1 c1 <"${OUT}"

	bs_ai_medium_record_result "${r1}" "${c1}" hit
	[ ${#BS_AI_MEDIUM_HUNT_QUEUE[@]} -gt 0 ]

	bs_ai_medium_choose_shot >"${OUT}"
	IFS=' ' read -r r2 c2 <"${OUT}"

	dr=$((r1 > r2 ? r1 - r2 : r2 - r1))
	dc=$((c1 > c2 ? c1 - c2 : c2 - c1))
	sum=$((dr + dc))
	[ "${sum}" -eq 1 ]

	bs_ai_medium_record_result "${r2}" "${c2}" sunk
	[ ${#BS_AI_MEDIUM_HUNT_QUEUE[@]} -eq 0 ]
}

@test "test_ai_medium_reverts_to_random_after_hunt_fails_and_does_not_repeat_any_previous_shots" {
	bs_ai_medium_init 3 7
	local rr cc r c

	bs_ai_medium_record_result 0 0 miss
	bs_ai_medium_record_result 1 1 miss

	OUT="${TEST_TMPDIR}/out2"
	bs_ai_medium_choose_shot >"${OUT}"
	IFS=' ' read -r rr cc <"${OUT}"

	if ! parse_shot "${rr} ${cc}"; then
		echo "shot '${rr} ${cc}' did not contain two coordinates" >&2
		return 1
	fi

	_bs_ai_medium_idx_from_raw "${r}" "${c}"
	chosen_idx=${_BS_AI_MEDIUM_RET_IDX}

	found=0
	for s in "${BS_AI_MEDIUM_SEEN_SHOTS[@]:-}"; do
		if [ "${s}" = "${chosen_idx}" ]; then
			found=1
			break
		fi
	done
	[ "${found}" -eq 0 ]
}

@test "test_ai_medium_does_not_peek_at_hidden_player_board_and_uses_only_turn_history_and_board_state" {
	bs_ai_medium_init 5 11
	OUT="${TEST_TMPDIR}/out3"
	bs_ai_medium_choose_shot >"${OUT}"
	[ "${CALLED_BOARD_GET_OWNER}" -eq 0 ]
	[ "${CALLED_BOARD_GET_STATE}" -eq 0 ]
}

@test "test_ai_medium_returns_no_move_when_all_cells_have_been_targeted" {
	bs_ai_medium_init 2 5
	for r in 0 1; do
		for c in 0 1; do
			bs_ai_medium_record_result "${r}" "${c}" miss
		done
	done

	OUT="${TEST_TMPDIR}/out4"
	if bs_ai_medium_choose_shot >"${OUT}" 2>/dev/null; then
		echo "expected no move when all cells are targeted" >&2
		return 1
	fi
}

@test "test_ai_medium_handles_malformed_turn_history_input_gracefully_without_crash_and_returns_error_or_no_move" {
	bs_ai_medium_init 3 3

	if bs_ai_medium_record_result 0 0; then
		echo "expected bs_ai_medium_record_result to fail on missing args" >&2
		return 1
	fi

	if bs_ai_medium_record_result 0 0 banana; then
		echo "expected bs_ai_medium_record_result to fail on invalid result" >&2
		return 1
	fi
}