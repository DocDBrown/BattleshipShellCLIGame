#!/usr/bin/env bats

setup() {
	TMPDIR_TEST=$(mktemp -d)
}

teardown() {
	if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
		rm -rf "$TMPDIR_TEST"
	fi
}

@test "Integration_turn_engine_event_sequence_updates_stats_and_summary_matches_expected" {
	script="$BATS_TEST_DIRNAME/stats.sh"
	run timeout 30s bash -c "set -euo pipefail; source \"$script\"; stats_init; _STATS_START=1000; _STATS_END=1065; stats_on_shot player hit; stats_on_shot player miss; stats_on_shot player sunk; stats_on_shot ai miss; stats_on_shot ai sunk; stats_summary_kv"
	[ "$status" -eq 0 ]
	echo "$output" | grep -Fq "total_shots_player=3"
	echo "$output" | grep -Fq "hits_player=2"
	echo "$output" | grep -Fq "misses_player=1"
	echo "$output" | grep -Fq "sunk_ships_player=1"
	echo "$output" | grep -Fq "accuracy_player_percent=66.67"
	echo "$output" | grep -Fq "total_shots_ai=2"
	echo "$output" | grep -Fq "hits_ai=1"
	echo "$output" | grep -Fq "misses_ai=1"
	echo "$output" | grep -Fq "sunk_ships_ai=1"
	echo "$output" | grep -Fq "accuracy_ai_percent=50.00"
	echo "$output" | grep -Fq "duration_seconds=65"
	echo "$output" | grep -Fq "duration_readable=1m05s"
}

@test "Integration_machine_readable_output_embedded_by_save_state_parses_back_to_same_metrics" {
	script="$BATS_TEST_DIRNAME/stats.sh"
	savefile="$TMPDIR_TEST/stats_save_kv.txt"
	run timeout 30s bash -c "set -euo pipefail; source \"$script\"; stats_init; _STATS_START=2000; _STATS_END=2002; stats_on_shot player hit; stats_on_shot ai miss; stats_on_shot player sunk; stats_on_shot ai sunk; stats_summary_kv > \"$savefile\"; cat \"$savefile\""
	[ "$status" -eq 0 ]
	# parse saved key=value output safely using grep+cut
	total_shots_player=$(grep '^total_shots_player=' "$savefile" | cut -d= -f2)
	hits_player=$(grep '^hits_player=' "$savefile" | cut -d= -f2)
	misses_player=$(grep '^misses_player=' "$savefile" | cut -d= -f2)
	sunk_player=$(grep '^sunk_ships_player=' "$savefile" | cut -d= -f2)
	acc_player=$(grep '^accuracy_player_percent=' "$savefile" | cut -d= -f2)
	total_ai=$(grep '^total_shots_ai=' "$savefile" | cut -d= -f2)
	hits_ai=$(grep '^hits_ai=' "$savefile" | cut -d= -f2)
	misses_ai=$(grep '^misses_ai=' "$savefile" | cut -d= -f2)
	sunk_ai=$(grep '^sunk_ships_ai=' "$savefile" | cut -d= -f2)
	acc_ai=$(grep '^accuracy_ai_percent=' "$savefile" | cut -d= -f2)
	dur_secs=$(grep '^duration_seconds=' "$savefile" | cut -d= -f2)

	[ "$total_shots_player" -eq 2 ]
	[ "$hits_player" -eq 2 ]
	[ "$misses_player" -eq 0 ]
	[ "$sunk_player" -eq 1 ]
	[ "$acc_player" = "100.00" ]
	[ "$total_ai" -eq 2 ]
	[ "$hits_ai" -eq 1 ]
	[ "$misses_ai" -eq 1 ]
	[ "$sunk_ai" -eq 1 ]
	[ "$acc_ai" = "50.00" ]
	[ "$dur_secs" -eq 2 ]
}
