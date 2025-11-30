#!/usr/bin/env bats

setup() {
	# Create a temporary directory for mocks to isolate the test
	MOCK_DIR=$(mktemp -d)

	# Create the directory structure expected by the script
	mkdir -p "${MOCK_DIR}/src/model"
	mkdir -p "${MOCK_DIR}/src/util"
	mkdir -p "${MOCK_DIR}/src/tui"
	mkdir -p "${MOCK_DIR}/src/placement"

	# Mock ship_rules.sh
	cat <<'EOF' >"${MOCK_DIR}/src/model/ship_rules.sh"
bs_ship_list() {
	printf "Carrier\nBattleship\nCruiser\nSubmarine\nDestroyer\n"
}
bs_ship_name() { echo "$1"; }
bs_ship_length() {
	case "$1" in
		Carrier) echo 5 ;;
		Battleship) echo 4 ;;
		Cruiser) echo 3 ;;
		Submarine) echo 3 ;;
		Destroyer) echo 2 ;;
		*) echo 0 ;;
	esac
}
EOF

	# Mock validation.sh
	cat <<'EOF' >"${MOCK_DIR}/src/util/validation.sh"
validate_board_size() { return 0; }
validate_coordinate() {
	local coord="$1"
	local size="$2"
	[[ "$coord" =~ ^[A-Z][0-9]+$ ]] || return 1
	# Simple check: if row letter > H (for size 8), fail
	local letter="${coord:0:1}"
	local num="${coord:1}"
	if [[ "$letter" > "H" ]]; then return 1; fi
	if (( num > size )); then return 1; fi
	return 0
}
trim() { echo "$1" | xargs; }
upper() { echo "$1" | tr '[:lower:]' '[:upper:]'; }
EOF

	# Mock board_state.sh
	cat <<'EOF' >"${MOCK_DIR}/src/model/board_state.sh"
BS_BOARD_SIZE=8
BS_BOARD_TOTAL_SEGMENTS=0
_BS_PL_DR=0
_BS_PL_DC=0
bs_board_new() { BS_BOARD_SIZE="$1"; }
bs_board_set_ship() { :; }
bs_board_get_state() { echo "unknown"; }
bs_board_get_owner() { echo ""; }
bs_board_total_remaining_segments() { echo "0"; }
_bs_placement__normalize_orientation() {
	if [[ "$1" == "h" ]]; then _BS_PL_DR=0; _BS_PL_DC=1; return 0; fi
	if [[ "$1" == "v" ]]; then _BS_PL_DR=1; _BS_PL_DC=0; return 0; fi
	return 1
}
EOF

	# Mock placement_validator.sh
	cat <<'EOF' >"${MOCK_DIR}/src/placement/placement_validator.sh"
bs_placement_validate() { return 0; }
EOF

	# Mock tui_prompts.sh
	cat <<'EOF' >"${MOCK_DIR}/src/tui/tui_prompts.sh"
safe_read_line() {
	local prompt="$1"
	read -r line || return 1
	echo "$line"
}
prompt_board_size() { echo "8"; }
EOF

	# Mock tui_renderer.sh - Updated to print title for verification
	cat <<'EOF' >"${MOCK_DIR}/src/tui/tui_renderer.sh"
tui_render_dual_grid() { echo "# Grid Rendered - $7"; }
EOF

	# Copy the script under test to the mock dir
	cp "${BATS_TEST_DIRNAME}/manual_placement.sh" "${MOCK_DIR}/src/placement/manual_placement.sh"
	chmod +x "${MOCK_DIR}/src/placement/manual_placement.sh"

	TEST_SCRIPT="${MOCK_DIR}/src/placement/manual_placement.sh"
}

teardown() {
	rm -rf "${MOCK_DIR}"
}

@test "manual_placement_happy_path_places_all_ships_and_renders_progress_after_each_placement" {
	run timeout 5s bash "${TEST_SCRIPT}" --board-size 8 <<'EOF'
A1

A2

A3

A4

A5

EOF
	[ "$status" -eq 0 ] || {
		echo "Expected exit 0, got $status"
		echo "Output: $output"
		return 1
	}
	[[ "$output" == *"Manual placement complete"* ]] || {
		echo "Missing completion"
		return 1
	}
	[[ "$output" == *"All ships placed"* ]] || {
		echo "Missing all ships placed"
		return 1
	}
	[[ "$output" == *"Placing: Carrier"* ]] || {
		echo "Missing placing carrier"
		return 1
	}
	[[ "$output" == *"# Grid Rendered"* ]] || {
		echo "Renderer did not show ship symbol"
		return 1
	}
}

@test "manual_placement_trims_and_normalizes_coordinate_input_before_validation_and_placement" {
	run timeout 5s bash "${TEST_SCRIPT}" --board-size 8 <<'EOF'
  a3  

A2

A3

A4

A5

EOF
	[ "$status" -eq 0 ] || {
		echo "Expected exit 0, got $status"
		echo "Output: $output"
		return 1
	}
	[[ "$output" == *"Manual placement complete"* ]] || {
		echo "Missing completion after normalized input"
		return 1
	}
}

@test "manual_placement_reprompts_on_empty_coordinate_then_accepts_valid_coordinate_and_places" {
	run timeout 5s bash "${TEST_SCRIPT}" --board-size 8 <<'EOF'

A1

A2

A3

A4

A5

EOF
	[ "$status" -eq 0 ] || {
		echo "Expected exit 0, got $status"
		echo "Output: $output"
		return 1
	}
	[[ "$output" == *"Input cannot be empty"* ]] || {
		echo "Did not reprompt on empty input"
		return 1
	}
	[[ "$output" == *"Manual placement complete"* ]] || {
		echo "Missing completion after reprompt"
		return 1
	}
}

@test "manual_placement_reprompts_on_invalid_coordinate_before_invoking_placement_validator" {
	run timeout 5s bash "${TEST_SCRIPT}" --board-size 8 <<'EOF'
Z9
A1

A2

A3

A4

A5

EOF
	[ "$status" -eq 0 ] || {
		echo "Expected exit 0, got $status"
		echo "Output: $output"
		return 1
	}
	[[ "$output" == *"Invalid coordinate:"* ]] || {
		echo "Did not emit invalid coordinate message"
		return 1
	}
	[[ "$output" == *"Manual placement complete"* ]] || {
		echo "Missing completion after correcting invalid coordinate"
		return 1
	}
}

@test "manual_placement_accepts_both_short_and_long_orientation_tokens_and_places_correctly" {
	run timeout 5s bash "${TEST_SCRIPT}" --board-size 8 <<'EOF'
A1
horizontal
A2
H
A3

A4

A5

EOF
	[ "$status" -eq 0 ] || {
		echo "Expected exit 0, got $status"
		echo "Output: $output"
		return 1
	}
	[[ "$output" == *"Manual placement complete"* ]] || {
		echo "Missing completion when mixing orientation tokens"
		return 1
	}
}
