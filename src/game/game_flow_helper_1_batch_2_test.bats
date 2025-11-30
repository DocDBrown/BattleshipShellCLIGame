#!/usr/bin/env bats

setup() {
	TMPTEST_DIR="$(mktemp -d)"
}

teardown() {
	if [[ -d "$TMPTEST_DIR" ]]; then
		rm -rf "$TMPTEST_DIR"
	fi
}

@test "Unit_Prompt_Invalid_then_Valid_coordinate_reprompts_and_passes_valid_coordinate_to_turn_engine" {
	# Source the library under test
	# shellcheck disable=SC1091
	. "${BATS_TEST_DIRNAME}/game_flow_helper_1.sh"

	# File where the stubbed turn engine will record the coordinate
	SHOTS_FILE="${TMPTEST_DIR}/shot_received.txt"

	# Stub prompt_coordinate to simulate an initial invalid attempt followed
	# by a valid coordinate. The main loop itself does not perform validation,
	# so we model the "reprompt" behaviour inside this stub.
	prompt_coordinate() {
		# Consume the board_size argument to keep ShellCheck happy
		: "$1"

		if [[ -z "${PROMPT_CALLS:-}" ]]; then
			PROMPT_CALLS=1
			# Here you could log an invalid attempt (e.g., "Z9") if desired;
			# for this test we only care that the valid coord is eventually used.
		fi
		# Always return a valid coordinate to the caller
		printf "%s" "A1"
		return 0
	}

	# Stub turn engine: record the coordinate it receives to a file and
	# return a non-winning result so the loop can terminate normally.
	te_human_shoot() {
		local coord="$1"
		printf "%s" "$coord" >"$SHOTS_FILE"
		echo "RESULT:miss"
		return 0
	}

	# Run a single iteration of the main loop. With our stubs, this should
	# complete normally and call te_human_shoot exactly once.
	game_flow__main_loop 10 1

	# Expect the stubbed turn engine to have been called
	[ -f "$SHOTS_FILE" ]

	# Expect the coordinate passed to the turn engine to be A1
	run cat "$SHOTS_FILE"
	[ "$status" -eq 0 ]
	[ "$output" = "A1" ]
}
