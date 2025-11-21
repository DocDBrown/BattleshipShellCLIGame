#!/usr/bin/env bats

setup() {
	:
}

teardown() {
	:
}

@test "Integration_elapsed_time_boundary_at_60_seconds_produces_minute_formatted_duration" {
	run timeout 5s bash -c "set -euo pipefail; source \"${BATS_TEST_DIRNAME}/stats.sh\"; _STATS_START=1000000; _STATS_END=1000060; stats_summary_text"
	[ "$status" -eq 0 ] || fail "expected exit status 0 but was $status; output: $output"
	[[ "$output" == *"Duration: 1m00s (60 seconds)"* ]] || fail "expected duration line with '1m00s (60 seconds)'; output: $output"
}
