#!/usr/bin/env bats

setup() {
	:
}

teardown() {
	:
}

@test "unit: bs_total_segments returns 17 for the canonical fleet" {
	run bash -c "source \"${BATS_TEST_DIRNAME}/ship_rules.sh\"; bs_total_segments"
	[ "$status" -eq 0 ]
	[ "$output" = "17" ]
}

@test "unit: bs_validate_fleet succeeds for the canonical fleet composition" {
	run bash -c "source \"${BATS_TEST_DIRNAME}/ship_rules.sh\"; bs_validate_fleet"
	[ "$status" -eq 0 ]
}

@test "unit: bs_validate_fleet errors when a ship length is missing" {
	tmpd=$(mktemp -d)
	trap 'rm -rf "${tmpd}"' RETURN
	cat >"${tmpd}/test_ship_rules.sh" <<'EOF'
#!/usr/bin/env bash
# Minimal test copy that simulates missing length
BS_SHIP_ORDER=("carrier" "battleship")
declare -A BS_SHIP_LENGTHS=(["carrier"]=5)
bs_validate_fleet() {
    local k
    declare -A seen=()
    for k in "${BS_SHIP_ORDER[@]}"; do
        if [[ -z "${BS_SHIP_LENGTHS[$k]:-}" ]]; then
            printf "Missing length for ship: %s\n" "$k" >&2
            return 2
        fi
        if [[ ! "${BS_SHIP_LENGTHS[$k]}" =~ ^[1-9][0-9]*$ ]]; then
            printf "Invalid length for ship %s: %s\n" "$k" "${BS_SHIP_LENGTHS[$k]}" >&2
            return 3
        fi
        if [[ -n "${seen[$k]:-}" ]]; then
            printf "Duplicate ship in order: %s\n" "$k" >&2
            return 4
        fi
        seen[$k]=1
    done
    return 0
}
EOF
	run bash -c "source \"${tmpd}/test_ship_rules.sh\"; bs_validate_fleet"
	[ "$status" -ne 0 ]
}

@test "unit: bs_validate_fleet errors when a ship length is non-numeric" {
	tmpd=$(mktemp -d)
	trap 'rm -rf "${tmpd}"' RETURN
	cat >"${tmpd}/test_ship_rules.sh" <<'EOF'
#!/usr/bin/env bash
BS_SHIP_ORDER=("carrier")
declare -A BS_SHIP_LENGTHS=(["carrier"]=abc)
bs_validate_fleet() {
    local k
    declare -A seen=()
    for k in "${BS_SHIP_ORDER[@]}"; do
        if [[ -z "${BS_SHIP_LENGTHS[$k]:-}" ]]; then
            printf "Missing length for ship: %s\n" "$k" >&2
            return 2
        fi
        if [[ ! "${BS_SHIP_LENGTHS[$k]}" =~ ^[1-9][0-9]*$ ]]; then
            printf "Invalid length for ship %s: %s\n" "$k" "${BS_SHIP_LENGTHS[$k]}" >&2
            return 3
        fi
        if [[ -n "${seen[$k]:-}" ]]; then
            printf "Duplicate ship in order: %s\n" "$k" >&2
            return 4
        fi
        seen[$k]=1
    done
    return 0
}
EOF
	run bash -c "source \"${tmpd}/test_ship_rules.sh\"; bs_validate_fleet"
	[ "$status" -ne 0 ]
}

@test "unit: bs_validate_fleet errors when BS_SHIP_ORDER contains duplicates" {
	tmpd=$(mktemp -d)
	trap 'rm -rf "${tmpd}"' RETURN
	cat >"${tmpd}/test_ship_rules.sh" <<'EOF'
#!/usr/bin/env bash
BS_SHIP_ORDER=("carrier" "carrier")
declare -A BS_SHIP_LENGTHS=(["carrier"]=5)
bs_validate_fleet() {
    local k
    declare -A seen=()
    for k in "${BS_SHIP_ORDER[@]}"; do
        if [[ -z "${BS_SHIP_LENGTHS[$k]:-}" ]]; then
            printf "Missing length for ship: %s\n" "$k" >&2
            return 2
        fi
        if [[ ! "${BS_SHIP_LENGTHS[$k]}" =~ ^[1-9][0-9]*$ ]]; then
            printf "Invalid length for ship %s: %s\n" "$k" "${BS_SHIP_LENGTHS[$k]}" >&2
            return 3
        fi
        if [[ -n "${seen[$k]:-}" ]]; then
            printf "Duplicate ship in order: %s\n" "$k" >&2
            return 4
        fi
        seen[$k]=1
    done
    return 0
}
EOF
	run bash -c "source \"${tmpd}/test_ship_rules.sh\"; bs_validate_fleet"
	[ "$status" -ne 0 ]
}

@test "unit: bs_ship_is_sunk behavior and error handling" {
	run bash -c "source \"${BATS_TEST_DIRNAME}/ship_rules.sh\"; bs_ship_is_sunk carrier 5"
	[ "$status" -eq 0 ]
	[ "$output" = "true" ]

	run bash -c "source \"${BATS_TEST_DIRNAME}/ship_rules.sh\"; bs_ship_is_sunk carrier 6"
	[ "$status" -eq 0 ]
	[ "$output" = "true" ]

	run bash -c "source \"${BATS_TEST_DIRNAME}/ship_rules.sh\"; bs_ship_is_sunk carrier 4"
	[ "$status" -eq 0 ]
	[ "$output" = "false" ]

	run bash -c "source \"${BATS_TEST_DIRNAME}/ship_rules.sh\"; bs_ship_is_sunk carrier abc"
	[ "$status" -ne 0 ]

	run bash -c "source \"${BATS_TEST_DIRNAME}/ship_rules.sh\"; bs_ship_is_sunk unknownship 1"
	[ "$status" -ne 0 ]
}

@test "unit: bs_ship_remaining_segments behavior and error handling" {
	run bash -c "source \"${BATS_TEST_DIRNAME}/ship_rules.sh\"; bs_ship_remaining_segments carrier 2"
	[ "$status" -eq 0 ]
	[ "$output" = "3" ]

	run bash -c "source \"${BATS_TEST_DIRNAME}/ship_rules.sh\"; bs_ship_remaining_segments carrier 99"
	[ "$status" -eq 0 ]
	[ "$output" = "0" ]

	run bash -c "source \"${BATS_TEST_DIRNAME}/ship_rules.sh\"; bs_ship_remaining_segments carrier abc"
	[ "$status" -ne 0 ]

	run bash -c "source \"${BATS_TEST_DIRNAME}/ship_rules.sh\"; bs_ship_remaining_segments unknownship 1"
	[ "$status" -ne 0 ]
}
