#!/usr/bin/env bats

# Bounds checks for both hunt and target modes

setup() {
	TEST_TEMP_DIR="$(mktemp -d)"
	export TEST_TEMP_DIR

	# rng.sh mock: always returns the min index (first candidate)
	cat >"${TEST_TEMP_DIR}/rng.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

bs_rng_int_range() {
  local min=$1
  # ignore max; always choose first candidate
  echo "$min"
}
EOF

	# board_state.sh mock: only board size constant
	cat >"${TEST_TEMP_DIR}/board_state.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

BS_BOARD_SIZE=10
EOF

	cp "${BATS_TEST_DIRNAME}/ai_hard.sh" "${TEST_TEMP_DIR}/ai_hard.sh"

	# shellcheck disable=SC1091
	source "${TEST_TEMP_DIR}/ai_hard.sh"
}

teardown() {
	rm -rf "$TEST_TEMP_DIR"
}

@test "unit_ai_hard_respects_board_bounds_and_never_generates_out_of_range_coordinates" {
	bs_ai_hard_init

	# 1. Hunt mode: repeatedly select cells; all must be in bounds.
	for _ in {1..20}; do
		bs_ai_hard_choose_shot >"${TEST_TEMP_DIR}/shot.txt"
		local status=$?
		[ "$status" -eq 0 ]

		local r c
		read -r r c <"${TEST_TEMP_DIR}/shot.txt"

		[ "$r" -ge 1 ] && [ "$r" -le 10 ]
		[ "$c" -ge 1 ] && [ "$c" -le 10 ]

		bs_ai_hard_notify_result "$r" "$c" "miss"
	done

	# 2. Target mode bounds near top-left corner
	bs_ai_hard_init
	bs_ai_hard_notify_result 1 1 "hit"

	local count=0
	while [ "${#BS_AI_HARD_TARGET_QUEUE_R[@]}" -gt 0 ]; do
		bs_ai_hard_choose_shot >"${TEST_TEMP_DIR}/shot.txt"
		local status=$?
		[ "$status" -eq 0 ]

		local r c
		read -r r c <"${TEST_TEMP_DIR}/shot.txt"

		[ "$r" -ge 1 ] && [ "$r" -le 10 ]
		[ "$c" -ge 1 ] && [ "$c" -le 10 ]

		bs_ai_hard_notify_result "$r" "$c" "miss"
		count=$((count + 1))
	done

	# Ensure we actually processed at least one queued target (1,2 or 2,1)
	[ "$count" -ge 1 ]
}
