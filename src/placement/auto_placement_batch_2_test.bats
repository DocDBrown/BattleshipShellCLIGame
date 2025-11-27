#!/usr/bin/env bats

setup() {
	TMPDIR="$(mktemp -d)"
}

teardown() {
	if [[ -d "${TMPDIR:-}" ]]; then
		rm -rf "${TMPDIR}"
	fi
}

@test "unit_auto_place_errors_if_required_dependency_placement_validator_or_board_state_missing" {
	# Create minimal helpers but intentionally omit placement_validator to trigger dependency error
	cat >"$TMPDIR/rng.sh" <<'SH'
#!/usr/bin/env bash
bs_rng_int_range() { printf "%d\n" 0; }
SH

	cat >"$TMPDIR/ship_rules.sh" <<'SH'
#!/usr/bin/env bash
bs_ship_list() { printf "destroyer\n"; }
bs_ship_length() { printf "2\n"; }
SH

	cat >"$TMPDIR/board_state.sh" <<'SH'
#!/usr/bin/env bash
BS_BOARD_SIZE=5
bs_board_set_ship() { return 0; }
bs_board_ship_remaining_segments() { printf "0"; return 0; }
SH

	wrapper="$TMPDIR/wrapper.sh"
	cat >"$wrapper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
. "$TMPDIR/rng.sh"
. "$TMPDIR/ship_rules.sh"
. "$TMPDIR/board_state.sh"
. "${BATS_TEST_DIRNAME}/auto_placement.sh"
bs_auto_place_fleet
EOF
	run timeout 5s bash "$wrapper"
	# Expect dependency-check failure (exit code 2)
	[ "$status" -eq 2 ]
	[[ "$output" == *"Missing required function: bs_placement_validate" ]]
}

@test "unit_auto_place_propagates_validator_error_on_invalid_orientation_and_aborts_attempt" {
	# Create minimal helpers and a placement validator that returns fatal code 5
	cat >"$TMPDIR/rng.sh" <<'SH'
#!/usr/bin/env bash
bs_rng_int_range() { printf "%d\n" 0; }
SH

	cat >"$TMPDIR/ship_rules.sh" <<'SH'
#!/usr/bin/env bash
bs_ship_list() { printf "destroyer\n"; }
bs_ship_length() { printf "2\n"; }
SH

	cat >"$TMPDIR/board_state.sh" <<'SH'
#!/usr/bin/env bash
BS_BOARD_SIZE=5
bs_board_set_ship() { return 0; }
bs_board_ship_remaining_segments() { printf "0"; return 0; }
SH

	# placement validator that signals invalid orientation (fatal code 5)
	cat >"$TMPDIR/placement_validator.sh" <<'SH'
#!/usr/bin/env bash
bs_placement_validate() { return 5; }
SH

	wrapper="$TMPDIR/wrapper2.sh"
	cat >"$wrapper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
. "$TMPDIR/rng.sh"
. "$TMPDIR/ship_rules.sh"
. "$TMPDIR/board_state.sh"
. "$TMPDIR/placement_validator.sh"
. "${BATS_TEST_DIRNAME}/auto_placement.sh"
bs_auto_place_fleet
EOF
	run timeout 5s bash "$wrapper"
	# Expect the auto-placement to propagate the validator's fatal code (5)
	[ "$status" -eq 5 ]
}

@test "unit_auto_place_propagates_validator_error_on_unknown_ship_type_and_aborts_with_error" {
	# Create minimal helpers and a placement validator that returns fatal code 2 (unknown ship)
	cat >"$TMPDIR/rng.sh" <<'SH'
#!/usr/bin/env bash
bs_rng_int_range() { printf "%d\n" 0; }
SH

	cat >"$TMPDIR/ship_rules.sh" <<'SH'
#!/usr/bin/env bash
bs_ship_list() { printf "destroyer\n"; }
bs_ship_length() { printf "2\n"; }
SH

	cat >"$TMPDIR/board_state.sh" <<'SH'
#!/usr/bin/env bash
BS_BOARD_SIZE=5
bs_board_set_ship() { return 0; }
bs_board_ship_remaining_segments() { printf "0"; return 0; }
SH

	# placement validator that signals unknown ship type (fatal code 2)
	cat >"$TMPDIR/placement_validator.sh" <<'SH'
#!/usr/bin/env bash
bs_placement_validate() { return 2; }
SH

	wrapper="$TMPDIR/wrapper3.sh"
	cat >"$wrapper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
. "$TMPDIR/rng.sh"
. "$TMPDIR/ship_rules.sh"
. "$TMPDIR/board_state.sh"
. "$TMPDIR/placement_validator.sh"
. "${BATS_TEST_DIRNAME}/auto_placement.sh"
bs_auto_place_fleet
EOF
	run timeout 5s bash "$wrapper"
	# Expect the auto-placement to propagate the validator's fatal code (2)
	[ "$status" -eq 2 ]
}
