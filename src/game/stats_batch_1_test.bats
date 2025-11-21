#!/usr/bin/env bats

setup() {
	SCRIPT="${BATS_TEST_DIRNAME}/stats.sh"
}

teardown() {
	:
}

@test "unit_handle_sunk_event_increments_sunk_ships_count" {
	run timeout 5s bash -c "source \"$SCRIPT\"; stats_init; stats_on_shot player sunk; stats_summary_kv"
	[ "$status" -eq 0 ]
	echo "$output" | grep -q '^sunk_ships_player=1$'
	echo "$output" | grep -q '^hits_player=1$'
}

@test "unit_accuracy_reports_zero_percent_without_division_by_zero_when_no_shots" {
	run timeout 5s bash -c "source \"$SCRIPT\"; stats_init; stats_summary_kv"
	[ "$status" -eq 0 ]
	echo "$output" | grep -q '^accuracy_player_percent=0.00$'
	echo "$output" | grep -q '^accuracy_ai_percent=0.00$'
	echo "$output" | grep -q '^duration_seconds=0$'
}

@test "unit_machine_readable_output_contains_expected_keys_and_key_value_format" {
	run timeout 5s bash -c "source \"$SCRIPT\"; stats_init; stats_start; stats_on_shot player hit; stats_on_shot ai miss; stats_end; stats_summary_kv"
	[ "$status" -eq 0 ]
	kv="$output"
	for key in total_shots_player hits_player misses_player sunk_ships_player accuracy_player_percent total_shots_ai hits_ai misses_ai sunk_ships_ai accuracy_ai_percent duration_seconds duration_readable; do
		printf '%s\n' "$kv" | grep -q "^${key}=" || {
			printf 'missing key %s\n' "$key"
			return 1
		}
	done
	printf '%s\n' "$kv" | grep -E -q '^duration_seconds=[0-9]+$'
	printf '%s\n' "$kv" | grep -E -q '^accuracy_player_percent=[0-9]+\.[0-9][0-9]$'
}

@test "unit_summary_and_machine_readable_output_values_are_consistent" {
	run timeout 5s bash -c "source \"$SCRIPT\"; stats_init; stats_start; stats_on_shot player hit; stats_on_shot player miss; stats_on_shot ai sunk; stats_end; stats_summary_kv; echo '---KVEND---'; stats_summary_text"
	[ "$status" -eq 0 ]
	kv="${output%%---KVEND---*}"
	txt="${output#*---KVEND---}"
	player_hits=$(printf '%s\n' "$kv" | awk -F= '/^hits_player=/{print $2}')
	printf '%s\n' "$txt" | grep -q "Hits: ${player_hits}"
}

@test "unit_multiple_sequential_shots_update_counters_and_accuracies_correctly" {
	run timeout 5s bash -c "source \"$SCRIPT\"; stats_init; stats_start; stats_on_shot player hit; stats_on_shot player miss; stats_on_shot player hit; stats_on_shot player sunk; stats_on_shot ai miss; stats_on_shot ai miss; stats_end; stats_summary_kv"
	[ "$status" -eq 0 ]
	kv="$output"
	tp=$(printf '%s\n' "$kv" | awk -F= '/^total_shots_player=/{print $2}')
	hp=$(printf '%s\n' "$kv" | awk -F= '/^hits_player=/{print $2}')
	mp=$(printf '%s\n' "$kv" | awk -F= '/^misses_player=/{print $2}')
	sp=$(printf '%s\n' "$kv" | awk -F= '/^sunk_ships_player=/{print $2}')
	ap=$(printf '%s\n' "$kv" | awk -F= '/^accuracy_player_percent=/{print $2}')
	[ "$tp" -eq 4 ]
	[ "$hp" -eq 3 ]
	[ "$mp" -eq 1 ]
	[ "$sp" -eq 1 ]
	printf '%s\n' "$ap" | grep -q '^75\.00$'
	ta=$(printf '%s\n' "$kv" | awk -F= '/^total_shots_ai=/{print $2}')
	ha=$(printf '%s\n' "$kv" | awk -F= '/^hits_ai=/{print $2}')
	ma=$(printf '%s\n' "$kv" | awk -F= '/^misses_ai=/{print $2}')
	aa=$(printf '%s\n' "$kv" | awk -F= '/^accuracy_ai_percent=/{print $2}')
	[ "$ta" -eq 2 ]
	[ "$ha" -eq 0 ]
	[ "$ma" -eq 2 ]
	printf '%s\n' "$aa" | grep -q '^0\.00$'
}
