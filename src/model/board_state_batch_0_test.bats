#!/usr/bin/env bats

@test "unit_board_new_valid_size_creates_NxN_unknown_cells" {
	run bash -c "source \"${BATS_TEST_DIRNAME}/board_state.sh\"; bs_board_new 3 || exit \$?; printf '%s\n' \"\$BS_BOARD_SIZE\"; bs_board_get_cell 0 0; bs_board_get_cell 2 2"
	[ "$status" -eq 0 ]
	expected=$'3\nunknown\nunknown'
	[ "$output" = "$expected" ]
}

@test "unit_board_new_invalid_size_returns_error" {
	run bash -c "source \"${BATS_TEST_DIRNAME}/board_state.sh\"; bs_board_new 0"
	[ "$status" -ne 0 ]
	[[ "$output" == *"Invalid board size"* ]]
}

@test "unit_get_cell_out_of_bounds_returns_error" {
	run bash -c "source \"${BATS_TEST_DIRNAME}/board_state.sh\"; bs_board_new 3; bs_board_get_cell 5 5"
	[ "$status" -ne 0 ]
	[[ "$output" == *"Out of bounds"* ]]
}

@test "unit_set_cell_and_get_returns_updated_state" {
	run bash -c "source \"${BATS_TEST_DIRNAME}/board_state.sh\"; bs_board_new 3; bs_board_set_cell 1 1 ship; bs_board_get_cell 1 1"
	[ "$status" -eq 0 ]
	[ "$output" = "ship" ]

	run bash -c "source \"${BATS_TEST_DIRNAME}/board_state.sh\"; bs_board_new 3; bs_board_set_cell 0 0 invalid"
	[ "$status" -ne 0 ]
	[[ "$output" == *"Invalid state"* ]]
}

@test "unit_associate_ship_segment_with_cell_records_ship_type_and_cell_state_ship" {
	run bash -c "source \"${BATS_TEST_DIRNAME}/board_state.sh\"; bs_board_new 5; bs_board_associate_ship_segment 2 3 carrier || exit \$?; bs_board_get_cell 2 3; printf '%s\n' \"\${BS_BOARD_SHIPMAP[2,3]}\"; printf '%s\n' \"\${BS_BOARD_SHIP_SEGMENTS[carrier]}\""
	[ "$status" -eq 0 ]
	expected=$'ship\ncarrier\n1'
	[ "$output" = "$expected" ]
}
