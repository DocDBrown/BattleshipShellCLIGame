#!/usr/bin/env bats

setup() {
	TMPDIR="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp.XXXX")"
	# ensure TMPDIR is under test dir before removing in teardown
	case "$TMPDIR" in
	"${BATS_TEST_DIRNAME}"*) : ;;
	*)
		echo "Unsafe tmpdir: $TMPDIR" >&2
		exit 1
		;;
	esac
	SUT="${BATS_TEST_DIRNAME}/ship_rules.sh"
}

teardown() {
	if [[ -n "${TMPDIR:-}" && "${TMPDIR}" == "${BATS_TEST_DIRNAME}"* ]]; then
		rm -rf -- "$TMPDIR"
	fi
}

@test "test_total_segments_equals_sum_of_individual_ship_lengths" {
	run timeout 5s bash -c "source \"$SUT\" && bs_total_segments"
	[ "$status" -eq 0 ]
	total="$output"

	run timeout 5s bash -c "source \"$SUT\" && sum=0; for t in \$(bs_ship_list); do l=\$(bs_ship_length \"\$t\"); sum=\$((sum + l)); done; printf \"%d\n\" \$sum"
	[ "$status" -eq 0 ]
	[ "$total" = "$output" ]
}

@test "test_remaining_segments_returns_length_minus_hits_when_hits_less_than_length" {
	run timeout 5s bash -c "source \"$SUT\" && bs_ship_remaining_segments destroyer 1"
	[ "$status" -eq 0 ]
	[ "$output" = "1" ]
}

@test "test_remaining_segments_returns_zero_when_hits_equal_length" {
	run timeout 5s bash -c "source \"$SUT\" && bs_ship_remaining_segments cruiser 3"
	[ "$status" -eq 0 ]
	[ "$output" = "0" ]
}

@test "test_remaining_segments_returns_zero_and_is_idempotent_when_hits_exceed_length" {
	run timeout 5s bash -c "source \"$SUT\" && bs_ship_remaining_segments submarine 10"
	[ "$status" -eq 0 ]
	[ "$output" = "0" ]
	first="$output"

	run timeout 5s bash -c "source \"$SUT\" && bs_ship_remaining_segments submarine 10"
	[ "$status" -eq 0 ]
	[ "$output" = "$first" ]
}

@test "test_ship_is_sunk_when_hits_greater_or_equal_to_length" {
	run timeout 5s bash -c "source \"$SUT\" && bs_ship_is_sunk destroyer 2"
	[ "$status" -eq 0 ]
	[ "$output" = "true" ]

	run timeout 5s bash -c "source \"$SUT\" && bs_ship_is_sunk destroyer 3"
	[ "$status" -eq 0 ]
	[ "$output" = "true" ]

	run timeout 5s bash -c "source \"$SUT\" && bs_ship_is_sunk cruiser 2"
	[ "$status" -eq 0 ]
	[ "$output" = "false" ]
}
