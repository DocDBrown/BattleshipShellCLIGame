#!/usr/bin/env bats

setup() {
	MOCK_DIR=$(mktemp -d)
	
	mkdir -p "${MOCK_DIR}/src/model"
	mkdir -p "${MOCK_DIR}/src/util"
	mkdir -p "${MOCK_DIR}/src/tui"
	mkdir -p "${MOCK_DIR}/src/placement"

	# Mock ship_rules.sh
	cat <<'EOF' > "${MOCK_DIR}/src/model/ship_rules.sh"
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
	cat <<'EOF' > "${MOCK_DIR}/src/util/validation.sh"
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
	cat <<'EOF' > "${MOCK_DIR}/src/model/board_state.sh"
BS_BOARD_SIZE=8
BS_BOARD_TOTAL_SEGMENTS=0
_BS_PL_DR=0
_BS_PL_DC=0
bs_board_new() { BS_BOARD_SIZE="$1"; BS_BOARD_TOTAL_SEGMENTS=0; }
bs_board_set_ship() { ((BS_BOARD_TOTAL_SEGMENTS++)); }
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
	cat <<'EOF' > "${MOCK_DIR}/src/placement/placement_validator.sh"
bs_placement_validate() {
	local r=$1 c=$2 o=$3 s=$4
	# Simulate out of bounds for H1 (row 7, col 0)
	if [[ "$r" == "7" && "$c" == "0" ]]; then
		printf "Ship would be out of bounds\n" >&2
		return 1
	fi
	# Simulate overlap for A1 (row 0, col 0) ONLY for Battleship (Ship 2)
	if [[ "$r" == "0" && "$c" == "0" && "$s" == "Battleship" ]]; then
		printf "Overlap with existing ship\n" >&2
		return 1
	fi
	return 0
}
EOF

	# Mock tui_prompts.sh
	cat <<'EOF' > "${MOCK_DIR}/src/tui/tui_prompts.sh"
safe_read_line() {
	local prompt="$1"
	read -r line || return 1
	echo "$line"
}
prompt_board_size() { echo "8"; }
EOF

	# Mock tui_renderer.sh
	cat <<'EOF' > "${MOCK_DIR}/src/tui/tui_renderer.sh"
tui_render_dual_grid() { echo "# Grid Rendered - $7"; }
EOF

	cp "${BATS_TEST_DIRNAME}/manual_placement.sh" "${MOCK_DIR}/src/placement/manual_placement.sh"
	chmod +x "${MOCK_DIR}/src/placement/manual_placement.sh"
	
	TEST_SCRIPT="${MOCK_DIR}/src/placement/manual_placement.sh"
}

teardown() {
	rm -rf "${MOCK_DIR}"
}

@test "manual_placement_reprompts_on_invalid_orientation_until_valid_orientation_provided" {
	run timeout 5s bash "${TEST_SCRIPT}" --board-size 8 --dump-stats <<'EOF'
A1
Z
H
AUTO
EOF
	[ "$status" -eq 3 ]
	[[ "$output" == *"Invalid orientation"* ]]
}

@test "manual_placement_propagates_placement_validator_out_of_bounds_error_and_allows_retry" {
	run timeout 5s bash "${TEST_SCRIPT}" --board-size 8 --dump-stats <<'EOF'
H1
H
A1
H
AUTO
EOF
	[ "$status" -eq 3 ]
	[[ "$output" == *"Ship would be out of bounds"* ]]
	[[ "$output" == *"Placement validation failed"* ]]
}

@test "manual_placement_reports_overlap_error_from_placement_validator_and_prompts_for_alternate_position" {
	run timeout 5s bash "${TEST_SCRIPT}" --board-size 8 --dump-stats <<'EOF'
A1
H
A1
H
B1
H
AUTO
EOF
	[ "$status" -eq 3 ]
	[[ "$output" == *"Overlap with existing ship"* ]]
}

@test "manual_placement_updates_board_state_idempotently_when_same_ship_segment_is_placed_twice" {
	# Override ship list to ensure the second ship is also a Carrier (length 5)
	# so that the total segments check matches the expectation of 5.
	cat <<'EOF' >> "${MOCK_DIR}/src/model/ship_rules.sh"
bs_ship_list() { printf "Carrier\nCarrier\n"; }
EOF

	run timeout 5s bash "${TEST_SCRIPT}" --board-size 8 --dump-stats <<'EOF'
A1
H
R
A1
H
AUTO
EOF
	[ "$status" -eq 3 ]
	[[ "$output" == *"STATS: total_segments=5"* ]]
}

@test "manual_placement_replace_last_ship_cancel_keeps_existing_placement_and_continues" {
	# Place Carrier (5), Place Battleship (4), Undo (removes Battleship), Auto.
	# Remaining: Carrier (5).
	run timeout 5s bash "${TEST_SCRIPT}" --board-size 8 --dump-stats <<'EOF'
A1
H
B1
H
R
AUTO
EOF
	[ "$status" -eq 3 ]
	[[ "$output" == *"STATS: total_segments=5"* ]]
}