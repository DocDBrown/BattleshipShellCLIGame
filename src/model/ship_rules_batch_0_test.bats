#!/usr/bin/env bats

setup() {
	SCRIPT="${BATS_TEST_DIRNAME}/ship_rules.sh"
	if [[ ! -f "$SCRIPT" ]]; then
		echo "Missing script under test: $SCRIPT" >&2
		return 1
	fi
}

@test "test_bs_ship_list_contains_expected_ship_identifiers" {
	run bash -c "source \"$SCRIPT\"; bs_ship_list"
	[ "$status" -eq 0 ]
	expected=$'carrier\nbattleship\ncruiser\nsubmarine\ndestroyer'
	[ "$output" = "$expected" ]
}

@test "test_bs_ship_list_idempotent_across_multiple_calls_returns_same_order_and_contents" {
	run bash -c "source \"$SCRIPT\"; bs_ship_list"
	[ "$status" -eq 0 ]
	out1="$output"
	run bash -c "source \"$SCRIPT\"; bs_ship_list"
	[ "$status" -eq 0 ]
	out2="$output"
	[ "$out1" = "$out2" ]
}

@test "test_bs_ship_list_and_length_keys_are_consistent_each_identifier_has_a_length_entry_and_no_orphan_lengths" {
	run bash -c "source \"$SCRIPT\"; bs_ship_list"
	[ "$status" -eq 0 ]
	ship_list="$output"
	while IFS= read -r ship; do
		run bash -c "source \"$SCRIPT\"; bs_ship_length \"$ship\""
		[ "$status" -eq 0 ]
		[[ "$output" =~ ^[1-9][0-9]*$ ]]
	done <<<"$ship_list"

	run bash -c "source \"$SCRIPT\"; for k in \"\${!BS_SHIP_LENGTHS[@]}\"; do printf \"%s\\n\" \"\$k\"; done | sort"
	[ "$status" -eq 0 ]
	lengths_keys_sorted="$output"
	run bash -c "source \"$SCRIPT\"; bs_ship_list | sort"
	[ "$status" -eq 0 ]
	ship_list_sorted="$output"
	[ "$lengths_keys_sorted" = "$ship_list_sorted" ]
}

@test "test_bs_ship_length_returns_positive_integer_for_every_canonical_ship_type" {
	run bash -c "source \"$SCRIPT\"; bs_ship_list"
	[ "$status" -eq 0 ]
	list="$output"
	while IFS= read -r ship; do
		run bash -c "source \"$SCRIPT\"; bs_ship_length \"$ship\""
		[ "$status" -eq 0 ]
		[[ "$output" =~ ^[1-9][0-9]*$ ]]
	done <<<"$list"
}

@test "test_bs_ship_length_handles_unknown_ship_identifier_gracefully" {
	run bash -c "source \"$SCRIPT\"; bs_ship_length bogus_ship"
	[ "$status" -ne 0 ]
	[[ "$output" == *"Unknown ship type:"* ]]
}
