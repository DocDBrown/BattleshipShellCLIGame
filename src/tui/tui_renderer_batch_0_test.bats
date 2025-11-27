#!/usr/bin/env bats
# shellcheck disable=SC1091

setup() {
	TMPDIR="$(mktemp -d)"
	# Copy the model helper into per-test temporary directory as required by test rules
	cp "${BATS_TEST_DIRNAME}/../model/board_state.sh" "${TMPDIR}/board_state_batch_0.sh"
	# Sourcing the adjacent non-test file (renderer) as required by the test contract
	# shellcheck disable=SC1091
	. "${BATS_TEST_DIRNAME}/tui_renderer.sh"
}

teardown() {
	rm -rf "${TMPDIR}"
}

@test "bs_board_new_initializes_default_10x10_board_with_all_cells_unknown" {
	# Source the copied board_state into this test shell so we can inspect globals
	# shellcheck disable=SC1091
	. "${TMPDIR}/board_state_batch_0.sh"
	bs_board_new
	[ "$BS_BOARD_SIZE" -eq 10 ]
	# total remaining segments should be zero right after new
	out="$(bs_board_total_remaining_segments)"
	[ "$out" = "0" ]
	# Verify every cell reports unknown (0-based indices)
	for r in $(seq 0 9); do
		for c in $(seq 0 9); do
			val="$(bs_board_get_state "$r" "$c")"
			[ "$val" = "unknown" ]
		done
	done
}

@test "bs_board_new_rejects_invalid_board_size_non_numeric_or_zero" {
	# Use run in a subshell that sources the copied helper to assert non-zero exit codes safely
	run bash -c ". \"${TMPDIR}/board_state_batch_0.sh\"; bs_board_new 0"
	[ "$status" -ne 0 ]
	run bash -c ". \"${TMPDIR}/board_state_batch_0.sh\"; bs_board_new abc"
	[ "$status" -ne 0 ]
}

@test "bs_board__normalize_coord_rejects_non_numeric_and_out_of_bounds_inputs" {
	# Non-numeric input should fail
	run bash -c ". \"${TMPDIR}/board_state_batch_0.sh\"; bs_board_new 5; bs_board__normalize_coord a 1"
	[ "$status" -ne 0 ]
	# Out-of-bounds input should fail
	run bash -c ". \"${TMPDIR}/board_state_batch_0.sh\"; bs_board_new 5; bs_board__normalize_coord 10 1"
	[ "$status" -ne 0 ]
}

@test "bs_board_in_bounds_prints_normalized_coords_for_valid_input" {
	# Valid 0-based coords should print normalized 1-based coordinates
	run bash -c ". \"${TMPDIR}/board_state_batch_0.sh\"; bs_board_new 5; bs_board_in_bounds 0 0"
	[ "$status" -eq 0 ]
	[ "$output" = "1 1" ]
}

@test "bs_board_set_ship_places_segment_updates_segment_counts_and_is_idempotent_for_same_ship" {
	# Place a ship and verify segment counters and idempotency. All done inside a subshell for deterministic state.
	# Note: Variables BS_BOARD_... are escaped so they are expanded by the subshell, not the test runner.
	run bash -c ". \"${TMPDIR}/board_state_batch_0.sh\"; bs_board_new 5; bs_board_set_ship 0 0 Destroyer >/dev/null 2>&1; printf '%d %d\n' \"\$BS_BOARD_REMAINING_SEGMENTS\" \"\$BS_BOARD_TOTAL_SEGMENTS\"; bs_board_set_ship 0 0 Destroyer >/dev/null 2>&1; printf '%d %d\n' \"\$BS_BOARD_REMAINING_SEGMENTS\" \"\$BS_BOARD_TOTAL_SEGMENTS\"; bs_board_ship_remaining_segments Destroyer"
	[ "$status" -eq 0 ]
	# Output should contain three lines: first counts after first placement, counts after idempotent placement, and remaining for ship
	first="$(printf '%s' "$output" | sed -n '1p')"
	second="$(printf '%s' "$output" | sed -n '2p')"
	third="$(printf '%s' "$output" | sed -n '3p')"
	[ "$first" = "1 1" ]
	[ "$second" = "1 1" ]
	[ "$third" = "1" ]
}
