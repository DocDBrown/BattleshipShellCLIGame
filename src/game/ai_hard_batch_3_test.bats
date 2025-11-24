#!/usr/bin/env bats

setup() {
	TEST_TEMP_DIR=$(mktemp -d)
	# Create mocks for dependencies
	# rng.sh mock: deterministic return for testing
	cat >"$TEST_TEMP_DIR/rng.sh" <<'EOF'
#!/usr/bin/env bash
bs_rng_int_range() {
	echo "$1"
}
EOF

	# board_state.sh mock: provides BS_BOARD_SIZE
	cat >"$TEST_TEMP_DIR/board_state.sh" <<'EOF'
#!/usr/bin/env bash
BS_BOARD_SIZE=10
EOF

	# Copy System Under Test to temp dir so it can source dependencies relatively
	cp "${BATS_TEST_DIRNAME}/ai_hard.sh" "$TEST_TEMP_DIR/ai_hard.sh"

	# Source the SUT from the temp dir
	source "$TEST_TEMP_DIR/ai_hard.sh"
}

teardown() {
	rm -rf "$TEST_TEMP_DIR"
}

@test "unit_ai_hard_respects_board_bounds_and_never_generates_out_of_range_coordinates" {
	bs_ai_hard_init

	# 1. Test Hunt Mode Bounds (Random Selection)
	# We loop multiple times to ensure generated coordinates are valid.
	# Since we mocked rng to return the first candidate, we iterate through the board.
	local i
	for i in {1..20}; do
		# Use file redirection to capture output while preserving state in main process
		bs_ai_hard_choose_shot >"$TEST_TEMP_DIR/shot.txt"
		local status=$?
		[ "$status" -eq 0 ]

		local r c
		read -r r c <"$TEST_TEMP_DIR/shot.txt"

		# Assert bounds
		[ "$r" -ge 1 ]
		[ "$r" -le 10 ]
		[ "$c" -ge 1 ]
		[ "$c" -le 10 ]

		# Mark as visited so AI picks a new cell next time
		bs_ai_hard_notify_result "$r" "$c" "miss"
	done

	# 2. Test Target Mode Bounds (Top-Left Corner)
	bs_ai_hard_init
	# Simulate hit at (1,1). Should generate neighbors (1,2) and (2,1).
	# Should NOT generate (0,1) or (1,0).
	bs_ai_hard_notify_result 1 1 "hit"

	# Consume the queue (expect 2 targets)
	local count=0
	while [ "${#BS_AI_HARD_TARGET_QUEUE_R[@]}" -gt 0 ]; do
		bs_ai_hard_choose_shot >"$TEST_TEMP_DIR/shot.txt"
		local status=$?
		[ "$status" -eq 0 ]

		local r c
		read -r r c <"$TEST_TEMP_DIR/shot.txt"

		[ "$r" -ge 1 ] && [ "$r" -le 10 ]
		[ "$c" -ge 1 ] && [ "$c" -le 10 ]
		count=$((count + 1))
	done
	# Ensure we actually processed targets
	[ "$count" -ge 1 ]

	# 3. Test Target Mode Bounds (Bottom-Right Corner)
	bs_ai_hard_init
	# Simulate hit at (10,10). Should generate neighbors (9,10) and (10,9).
	# Should NOT generate (11,10) or (10,11).
	bs_ai_hard_notify_result 10 10 "hit"

	count=0
	while [ "${#BS_AI_HARD_TARGET_QUEUE_R[@]}" -gt 0 ]; do
		bs_ai_hard_choose_shot >"$TEST_TEMP_DIR/shot.txt"
		local status=$?
		[ "$status" -eq 0 ]

		local r c
		read -r r c <"$TEST_TEMP_DIR/shot.txt"

		[ "$r" -ge 1 ] && [ "$r" -le 10 ]
		[ "$c" -ge 1 ] && [ "$c" -le 10 ]
		count=$((count + 1))
	done
	[ "$count" -ge 1 ]
}
