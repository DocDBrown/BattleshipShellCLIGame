#!/usr/bin/env bats

@test "unit_start_game_resets_counters_and_records_start_timestamp" {
	run timeout 5s bash -c "source \"$BATS_TEST_DIRNAME/stats.sh\"; stats_init; stats_start; printf \"%d|%d|%d|%d|%d\n\" \"\$_STATS_START\" \"\$_total_shots_player\" \"\$_hits_player\" \"\$_misses_player\" \"\$_sunk_player\""
	[ "$status" -eq 0 ] || fail "command failed"
	IFS='|' read -r start total hits misses sunk <<<"$output"
	[ -n "$start" ] || fail "start not set"
	case "$start" in '' | *[!0-9]*) fail "start not numeric" ;; esac
	[ "$start" -gt 0 ] || fail "start not >0"
	[ "$total" -eq 0 ] || fail "total_shots_player not zero"
	[ "$hits" -eq 0 ] || fail "hits_player not zero"
	[ "$misses" -eq 0 ] || fail "misses_player not zero"
	[ "$sunk" -eq 0 ] || fail "sunk_player not zero"
}

@test "unit_end_game_records_end_timestamp_and_computes_elapsed_in_seconds_when_under_60" {
	run timeout 5s bash -c "source \"$BATS_TEST_DIRNAME/stats.sh\"; stats_init; _STATS_START=\$((\$(date +%s) - 10)); stats_end; stats_summary_kv"
	[ "$status" -eq 0 ] || fail "command failed"
	duration_seconds=$(printf "%s\n" "$output" | awk -F= '/^duration_seconds=/{print $2}')
	duration_readable=$(printf "%s\n" "$output" | awk -F= '/^duration_readable=/{print $2}')
	case "$duration_seconds" in '' | *[!0-9]*) fail "duration_seconds not numeric" ;; esac
	[ "$duration_seconds" -ge 0 ] || fail "duration_seconds negative"
	[ "$duration_seconds" -lt 60 ] || fail "duration_seconds not under 60"
	case "$duration_readable" in *m*) fail "duration_readable contains minutes" ;; esac
	case "$duration_readable" in *s) : ;; *) fail "duration_readable not seconds format" ;; esac
}

@test "unit_end_game_computes_elapsed_in_minutes_when_60_seconds_or_more" {
	run timeout 5s bash -c "source \"$BATS_TEST_DIRNAME/stats.sh\"; stats_init; _STATS_START=\$((\$(date +%s) - 125)); stats_end; stats_summary_kv"
	[ "$status" -eq 0 ] || fail "command failed"
	duration_seconds=$(printf "%s\n" "$output" | awk -F= '/^duration_seconds=/{print $2}')
	duration_readable=$(printf "%s\n" "$output" | awk -F= '/^duration_readable=/{print $2}')
	case "$duration_seconds" in '' | *[!0-9]*) fail "duration_seconds not numeric" ;; esac
	[ "$duration_seconds" -ge 60 ] || fail "duration_seconds not >= 60"
	echo "$duration_readable" | grep -E '^[0-9]+m[0-9]{2}s$' >/dev/null || fail "duration_readable not in minutes format"
}

@test "unit_handle_player_shot_hit_increments_player_shots_and_hits_and_updates_accuracy" {
	run timeout 5s bash -c "source \"$BATS_TEST_DIRNAME/stats.sh\"; stats_init; stats_on_shot player hit; stats_summary_kv"
	[ "$status" -eq 0 ] || fail "command failed"
	total_shots_player=$(printf "%s\n" "$output" | awk -F= '/^total_shots_player=/{print $2}')
	hits_player=$(printf "%s\n" "$output" | awk -F= '/^hits_player=/{print $2}')
	misses_player=$(printf "%s\n" "$output" | awk -F= '/^misses_player=/{print $2}')
	sunk_player=$(printf "%s\n" "$output" | awk -F= '/^sunk_ships_player=/{print $2}')
	acc=$(printf "%s\n" "$output" | awk -F= '/^accuracy_player_percent=/{print $2}')
	[ "$total_shots_player" -eq 1 ] || fail "total_shots_player not 1"
	[ "$hits_player" -eq 1 ] || fail "hits_player not 1"
	[ "$misses_player" -eq 0 ] || fail "misses_player not 0"
	[ "$sunk_player" -eq 0 ] || fail "sunk_ships_player not 0"
	[ "$acc" = "100.00" ] || fail "accuracy_player_percent not 100.00"
}

@test "unit_handle_ai_shot_miss_increments_ai_shots_and_misses_and_updates_accuracy" {
	run timeout 5s bash -c "source \"$BATS_TEST_DIRNAME/stats.sh\"; stats_init; stats_on_shot ai miss; stats_summary_kv"
	[ "$status" -eq 0 ] || fail "command failed"
	total_shots_ai=$(printf "%s\n" "$output" | awk -F= '/^total_shots_ai=/{print $2}')
	hits_ai=$(printf "%s\n" "$output" | awk -F= '/^hits_ai=/{print $2}')
	misses_ai=$(printf "%s\n" "$output" | awk -F= '/^misses_ai=/{print $2}')
	sunk_ai=$(printf "%s\n" "$output" | awk -F= '/^sunk_ships_ai=/{print $2}')
	acc=$(printf "%s\n" "$output" | awk -F= '/^accuracy_ai_percent=/{print $2}')
	[ "$total_shots_ai" -eq 1 ] || fail "total_shots_ai not 1"
	[ "$hits_ai" -eq 0 ] || fail "hits_ai not 0"
	[ "$misses_ai" -eq 1 ] || fail "misses_ai not 1"
	[ "$sunk_ai" -eq 0 ] || fail "sunk_ships_ai not 0"
	[ "$acc" = "0.00" ] || fail "accuracy_ai_percent not 0.00"
}
