#!/usr/bin/env bats

setup() {
	# No persistent resources needed; source happens in each test to ensure clean environment
	:
}

@test "unit: bs__sanitize_type normalizes mixed-case input to lowercase" {
	run bash -c "source \"${BATS_TEST_DIRNAME}/ship_rules.sh\"; bs__sanitize_type 'CarRieR123'"
	[ "$status" -eq 0 ]
	[ "$output" = "carrier123" ]
}

@test "unit: bs__sanitize_type returns non-zero for empty input and for inputs with invalid characters" {
	run bash -c "source \"${BATS_TEST_DIRNAME}/ship_rules.sh\"; bs__sanitize_type ''"
	[ "$status" -ne 0 ]

	run bash -c "source \"${BATS_TEST_DIRNAME}/ship_rules.sh\"; bs__sanitize_type 'bad#ship'"
	[ "$status" -ne 0 ]
}

@test "unit: bs_ship_list lists canonical ship types in canonical order" {
	run bash -c "source \"${BATS_TEST_DIRNAME}/ship_rules.sh\"; bs_ship_list"
	[ "$status" -eq 0 ]
	expected=$'carrier\nbattleship\ncruiser\nsubmarine\ndestroyer'
	[ "$output" = "$expected" ]
}

@test "unit: bs_ship_length returns correct length for 'carrier' and errors for unknown ship type" {
	run bash -c "source \"${BATS_TEST_DIRNAME}/ship_rules.sh\"; bs_ship_length 'carrier'"
	[ "$status" -eq 0 ]
	[ "$output" = "5" ]

	run bash -c "source \"${BATS_TEST_DIRNAME}/ship_rules.sh\"; bs_ship_length 'nope'"
	[ "$status" -ne 0 ]
	[[ "$output" == *"Unknown ship type"* || "$output" == *"Invalid ship type"* ]]
}

@test "unit: bs_ship_name returns human-readable 'Battleship' for 'battleship' and falls back to sanitized token for unmapped types" {
	run bash -c "source \"${BATS_TEST_DIRNAME}/ship_rules.sh\"; bs_ship_name 'battleship'"
	[ "$status" -eq 0 ]
	[ "$output" = "Battleship" ]

	run bash -c "source \"${BATS_TEST_DIRNAME}/ship_rules.sh\"; bs_ship_name 'MyCustomShip'"
	[ "$status" -eq 0 ]
	[ "$output" = "mycustomship" ]
}
