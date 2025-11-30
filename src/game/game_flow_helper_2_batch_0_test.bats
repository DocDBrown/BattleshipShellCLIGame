#!/usr/bin/env bats

setup() {
	:
}

@test "unit:bs_board_new_initializes_board_and_counts_for_default_size" {
	cd "${BATS_TEST_DIRNAME}/.." || exit 1
	# shellcheck source=/dev/null
	. "model/board_state.sh"

	bs_board_new || {
		echo 'bs_board_new failed' >&2
		false
	}

	local size total remaining state

	size="${BS_BOARD_SIZE:-0}"
	total="${BS_BOARD_TOTAL_SEGMENTS:-0}"
	remaining="${BS_BOARD_REMAINING_SEGMENTS:-0}"
	state="$(bs_board_get_state 0 0)"

	[ "${size:-0}" -eq 10 ] || {
		printf 'Expected board size 10, got %s\n' "${size:-unset}"
		false
	}
	[ "${total:-0}" -eq 0 ] || {
		printf 'Expected total 0, got %s\n' "${total:-unset}"
		false
	}
	[ "${remaining:-0}" -eq 0 ] || {
		printf 'Expected remaining 0, got %s\n' "${remaining:-unset}"
		false
	}
	[ "$state" = "unknown" ] || {
		printf 'Expected state unknown, got %s\n' "$state"
		false
	}
}

@test "unit:bs_board_new_rejects_invalid_size_and_returns_nonzero" {
	cd "${BATS_TEST_DIRNAME}/.." || exit 1
	# shellcheck source=/dev/null
	. "model/board_state.sh"

	run bs_board_new -5

	[ "$status" -ne 0 ]
	[ "$status" -eq 1 ] || {
		printf 'Expected status 1, got %s\n' "$status"
		false
	}

	echo "$output" | grep -q "Invalid board size" || {
		printf 'Expected Invalid board size message\n'
		false
	}
}

@test "unit:bs_board_set_ship_idempotent_and_updates_segment_counts" {
	cd "${BATS_TEST_DIRNAME}/.." || exit 1
	# shellcheck source=/dev/null
	. "model/board_state.sh"

	bs_board_new 5 || {
		echo 'bs_board_new 5 failed' >&2
		false
	}

	bs_board_set_ship 0 0 destroyer || {
		printf 'bs_board_set_ship 0 0 failed\n'
		false
	}
	bs_board_set_ship 0 1 destroyer || {
		printf 'bs_board_set_ship 0 1 failed\n'
		false
	}

	local total1 rem1 total2 rem2

	total1="${BS_BOARD_TOTAL_SEGMENTS:-0}"
	rem1="${BS_BOARD_REMAINING_SEGMENTS:-0}"

	bs_board_set_ship 0 0 destroyer || {
		printf 'bs_board_set_ship 0 0 (second time) failed\n'
		false
	}

	total2="${BS_BOARD_TOTAL_SEGMENTS:-0}"
	rem2="${BS_BOARD_REMAINING_SEGMENTS:-0}"

	[ "${total1:-0}" -eq 2 ] || {
		printf 'Expected total1 2 got %s\n' "${total1:-unset}"
		false
	}
	[ "${rem1:-0}" -eq 2 ] || {
		printf 'Expected rem1 2 got %s\n' "${rem1:-unset}"
		false
	}
	[ "${total2:-0}" -eq 2 ] || {
		printf 'Expected total2 2 got %s\n' "${total2:-unset}"
		false
	}
	[ "${rem2:-0}" -eq 2 ] || {
		printf 'Expected rem2 2 got %s\n' "${rem2:-unset}"
		false
	}
}

@test "unit:bs_board_set_hit_marks_cell_hit_decrements_remaining_and_is_idempotent" {
	cd "${BATS_TEST_DIRNAME}/.." || exit 1
	# shellcheck source=/dev/null
	. "model/board_state.sh"

	bs_board_new 5 || {
		echo 'bs_board_new 5 failed' >&2
		false
	}

	bs_board_set_ship 1 1 destroyer || {
		printf 'bs_board_set_ship 1 1 failed\n'
		false
	}
	bs_board_set_ship 1 2 destroyer || {
		printf 'bs_board_set_ship 1 2 failed\n'
		false
	}

	local rem_before rem_after rem_after2 state

	rem_before="${BS_BOARD_REMAINING_SEGMENTS:-0}"

	bs_board_set_hit 1 1 || {
		printf 'bs_board_set_hit 1 1 failed\n'
		false
	}

	state="$(bs_board_get_state 1 1)"
	rem_after="${BS_BOARD_REMAINING_SEGMENTS:-0}"

	bs_board_set_hit 1 1 || {
		printf 'bs_board_set_hit 1 1 (second time) failed\n'
		false
	}
	rem_after2="${BS_BOARD_REMAINING_SEGMENTS:-0}"

	[ "${rem_before:-0}" -eq 2 ] || {
		printf 'Expected rem_before 2 got %s\n' "${rem_before:-unset}"
		false
	}
	[ "$state" = "hit" ] || {
		printf 'Expected state hit got %s\n' "$state"
		false
	}
	[ "${rem_after:-0}" -eq 1 ] || {
		printf 'Expected rem_after 1 got %s\n' "${rem_after:-unset}"
		false
	}
	[ "${rem_after2:-0}" -eq 1 ] || {
		printf 'Expected rem_after2 1 got %s\n' "${rem_after2:-unset}"
		false
	}
}

@test "unit:bs_board_set_miss_marks_cell_miss_and_clears_owner" {
	cd "${BATS_TEST_DIRNAME}/.." || exit 1
	# shellcheck source=/dev/null
	. "model/board_state.sh"

	bs_board_new 5 || {
		echo 'bs_board_new 5 failed' >&2
		false
	}

	bs_board_set_ship 2 2 destroyer || {
		printf 'bs_board_set_ship 2 2 failed\n'
		false
	}
	bs_board_set_miss 2 2 || {
		printf 'bs_board_set_miss 2 2 failed\n'
		false
	}

	local state owner

	state="$(bs_board_get_state 2 2)"
	owner="$(bs_board_get_owner 2 2)"

	[ "$state" = "miss" ] || {
		printf 'Expected state miss got %s\n' "$state"
		false
	}
	[ -z "$owner" ] || {
		printf 'Expected empty owner got %s\n' "$owner"
		false
	}
}
