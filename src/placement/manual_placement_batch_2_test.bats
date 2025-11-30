#!/usr/bin/env bats

setup() {
	MOCK_DIR=$(mktemp -d)

	mkdir -p "${MOCK_DIR}/src/model"
	mkdir -p "${MOCK_DIR}/src/util"
	mkdir -p "${MOCK_DIR}/src/tui"
	mkdir -p "${MOCK_DIR}/src/placement"

	# Mock ship_rules.sh
	cat <<'EOF' >"${MOCK_DIR}/src/model/ship_rules.sh"
bs_ship_list() { printf "Carrier\nBattleship\nCruiser\nSubmarine\nDestroyer\n"; }
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
	[[ "$coord" =~ ^[A-Z][0-9]+$ ]] || return 1
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

	# Mock tui_renderer.sh
	cat <<'EOF' >"${MOCK_DIR}/src/tui/tui_renderer.sh"
tui_render_dual_grid() { :; }
EOF

	cp "${BATS_TEST_DIRNAME}/manual_placement.sh" "${MOCK_DIR}/src/placement/manual_placement.sh"
	chmod +x "${MOCK_DIR}/src/placement/manual_placement.sh"

	TEST_SCRIPT="${MOCK_DIR}/src/placement/manual_placement.sh"
}

teardown() {
	rm -rf "${MOCK_DIR}"
}

@test "manual_placement_replace_last_ship_confirm_removes_previous_segments_and_prompts_for_replacement" {
	run timeout 5s bash "${TEST_SCRIPT}" --board-size 8 <<'EOF'
A1
H
R
AUTO
EOF

	[ "$status" -eq 3 ]
	[[ "$output" == *"Last placement removed"* ]]
	# After removing Carrier (Ship 1), the script should prompt for Carrier again.
	[[ "$output" == *"Placing Carrier"* || "$output" == *"Placing: Carrier"* ]]
}

@test "manual_placement_switches_to_auto_placement_midway_and_stops_manual_prompts_for_remaining_ships" {
	run timeout 5s bash "${TEST_SCRIPT}" --board-size 8 <<'EOF'
A1
H
AUTO
EOF

	[ "$status" -eq 3 ]
	[[ "$output" == *"Switching to auto-placement"* ]]
}

@test "manual_placement_handles_eof_from_prompts_and_exits_with_nonzero_status" {
	# Provide no stdin so the first prompt for a coordinate receives EOF
	run timeout 5s bash "${TEST_SCRIPT}" --board-size 8 <<'EOF'

EOF

	[ "$status" -ne 0 ]
	[ "$status" -eq 2 ]
	[[ "$output" == *"Input closed"* ]]
}

@test "manual_placement_aborts_with_error_when_placement_validator_dependency_is_missing" {
	# Remove the placement_validator to simulate missing dependency
	rm -f "${MOCK_DIR}/src/placement/placement_validator.sh"

	run timeout 5s bash "${TEST_SCRIPT}" --board-size 8
	[ "$status" -eq 2 ]
	[[ "$output" == *"Required file not found:"* ]]
}

@test "manual_placement_aborts_with_error_when_tui_renderer_dependency_is_missing" {
	# Remove the tui renderer to simulate missing dependency
	rm -f "${MOCK_DIR}/src/tui/tui_renderer.sh"

	run timeout 5s bash "${TEST_SCRIPT}" --board-size 8
	[ "$status" -eq 2 ]
	[[ "$output" == *"Required file not found:"* ]]
}
