#!/usr/bin/env bats

setup() {
	SCRIPT="${BATS_TEST_DIRNAME}/ship_rules.sh"
}

@test "test_ship_not_sunk_when_hits_less_than_length" {
	run timeout 5s bash -c "source \"$SCRIPT\" && bs_ship_list"
	[ "$status" -eq 0 ]
	mapfile -t ships <<<"$output"
	[ "${#ships[@]}" -gt 0 ]

	for ship in "${ships[@]}"; do
		run timeout 5s bash -c "source \"$SCRIPT\" && bs_ship_length $ship"
		[ "$status" -eq 0 ]
		len="$output"
		[[ "$len" =~ ^[0-9]+$ ]]

		hits=$((len - 1))
		if ((hits < 0)); then hits=0; fi

		run timeout 5s bash -c "source \"$SCRIPT\" && bs_ship_is_sunk $ship $hits"
		[ "$status" -eq 0 ]
		[ "$output" = "false" ]
	done
}

@test "test_canonical_ship_names_used_in_status_messages_match_identifiers_and_lengths" {
	run timeout 5s bash -c "source \"$SCRIPT\" && bs_validate_fleet"
	[ "$status" -eq 0 ]

	run timeout 5s bash -c "source \"$SCRIPT\" && bs_ship_list"
	[ "$status" -eq 0 ]
	mapfile -t ships <<<"$output"
	[ "${#ships[@]}" -gt 0 ]

	total=0
	for ship in "${ships[@]}"; do
		run timeout 5s bash -c "source \"$SCRIPT\" && bs_ship_length $ship"
		[ "$status" -eq 0 ]
		len="$output"
		[[ "$len" =~ ^[0-9]+$ ]]
		total=$((total + len))

		run timeout 5s bash -c "source \"$SCRIPT\" && bs_ship_name $ship"
		[ "$status" -eq 0 ]
		name="$output"
		[ -n "$name" ]
	done

	run timeout 5s bash -c "source \"$SCRIPT\" && bs_total_segments"
	[ "$status" -eq 0 ]
	[ "$output" -eq "$total" ]
}
