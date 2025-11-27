#!/usr/bin/env bash
# shellcheck disable=SC1091

setup() {
	TMPDIR=$(mktemp -d)
	# Copy the canonical board_state helper into a safe per-test dir so tests do not rely on repository layout
	cp "${BATS_TEST_DIRNAME}/../model/board_state.sh" "${TMPDIR}/board_state.sh"
	if [ -f "${BATS_TEST_DIRNAME}/../model/ship_rules.sh" ]; then
		cp "${BATS_TEST_DIRNAME}/../model/ship_rules.sh" "${TMPDIR}/ship_rules.sh"
	fi
	# Source the renderer from the same directory as this test (per BATS library rules)
	# shellcheck source=./tui_renderer.sh
	. "${BATS_TEST_DIRNAME}/tui_renderer.sh"
	# shellcheck source=/dev/null
	. "${TMPDIR}/board_state.sh"
}

teardown() {
	rm -rf "${TMPDIR}"
}

@test "bs_board_set_ship_overwriting_other_ship_decrements_previous_owner_segment_count" {
	bs_board_new 5
	bs_board_set_ship 0 0 Alpha
	placed_alpha=$(bs_board_ship_remaining_segments Alpha)
	[ "${placed_alpha}" -eq 1 ]
	total1=$(bs_board_total_remaining_segments)
	[ "${total1}" -eq 1 ]

	bs_board_set_ship 0 0 Beta
	placed_alpha_after=$(bs_board_ship_remaining_segments Alpha)
	placed_beta=$(bs_board_ship_remaining_segments Beta)
	total_after=$(bs_board_total_remaining_segments)

	[ "${placed_alpha_after}" -eq 0 ]
	[ "${placed_beta}" -eq 1 ]
	[ "${total_after}" -eq 1 ]
}

@test "bs_board_set_hit_marks_hit_updates_hits_and_remaining_segments_and_is_idempotent_on_repeat" {
	bs_board_new 5
	bs_board_set_ship 1 1 Cruiser
	bs_board_set_hit 1 1

	state_after=$(bs_board_get_state 1 1)
	[ "${state_after}" = "hit" ]

	sunk_now=$(bs_board_ship_is_sunk Cruiser)
	[ "${sunk_now}" = "true" ]

	total_after=$(bs_board_total_remaining_segments)
	[ "${total_after}" -eq 0 ]

	# Repeat hit should be idempotent
	bs_board_set_hit 1 1
	total_after2=$(bs_board_total_remaining_segments)
	[ "${total_after2}" -eq 0 ]
	sunk_after2=$(bs_board_ship_is_sunk Cruiser)
	[ "${sunk_after2}" = "true" ]
}

@test "bs_board_set_miss_marks_miss_and_clears_owner_for_cell" {
	bs_board_new 5
	bs_board_set_ship 2 2 Delta
	owner_before=$(bs_board_get_owner 2 2)
	[ "${owner_before}" = "delta" ]

	bs_board_set_miss 2 2
	state_after=$(bs_board_get_state 2 2)
	[ "${state_after}" = "miss" ]

	owner_after=$(bs_board_get_owner 2 2)
	[ -z "${owner_after}" ]
}

@test "bs_board_ship_is_sunk_and_remaining_segments_correctly_report_sunk_and_not_sunk_cases" {
	bs_board_new 5
	bs_board_set_ship 3 3 Sub
	bs_board_set_ship 3 4 Sub

	is_sunk_before=$(bs_board_ship_is_sunk Sub)
	[ "${is_sunk_before}" = "false" ]

	bs_board_set_hit 3 3
	is_sunk_mid=$(bs_board_ship_is_sunk Sub)
	[ "${is_sunk_mid}" = "false" ]

	bs_board_set_hit 3 4
	is_sunk_after=$(bs_board_ship_is_sunk Sub)
	[ "${is_sunk_after}" = "true" ]

	rem=$(bs_board_ship_remaining_segments Sub)
	[ "${rem}" -eq 0 ]
}

@test "bs_board_is_win_reports_true_when_no_remaining_segments_and_false_when_segments_remain" {
	bs_board_new 5
	bs_board_set_ship 0 0 Solo
	win_before=$(bs_board_is_win)
	[ "${win_before}" = "false" ]

	bs_board_set_hit 0 0
	win_after=$(bs_board_is_win)
	[ "${win_after}" = "true" ]
}
