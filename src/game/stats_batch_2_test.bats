#!/usr/bin/env bats
setup() {
	TMPDIR=$(mktemp -d)
	cp "${BATS_TEST_DIRNAME}/stats.sh" "$TMPDIR/stats.sh"
	chmod +x "$TMPDIR/stats.sh"
}
teardown() {
	if [ -d "${TMPDIR:-}" ]; then
		rm -rf "$TMPDIR"
	fi
}
@test "unit_timestamp_calculation_uses_recorded_start_and_end_for_elapsed_time" {
	cat >"$TMPDIR/wrapper1.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/stats.sh"
_STATS_START=1000
_STATS_END=1015
_stats_elapsed_seconds
EOF
	chmod +x "$TMPDIR/wrapper1.sh"
	run timeout 5s bash "$TMPDIR/wrapper1.sh"
	[ "$status" -eq 0 ]
	[ "$output" -eq 15 ]
}
@test "unit_save_state_key_value_output_is_stable_and_parseable_by_simple_key_value_parser" {
	cat >"$TMPDIR/wrapper2.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/stats.sh"
stats_init
_total_shots_player=10
_hits_player=4
_misses_player=6
_sunk_player=2
_total_shots_ai=8
_hits_ai=3
_misses_ai=5
_sunk_ai=1
_STATS_START=1000
_STATS_END=1065
out=$(stats_summary_kv)
required_keys=(total_shots_player hits_player misses_player sunk_ships_player accuracy_player_percent total_shots_ai hits_ai misses_ai sunk_ships_ai accuracy_ai_percent duration_seconds duration_readable)
for k in "${required_keys[@]}"; do
  grep -q "^${k}=" <<<"$out" || { echo "missing:$k"; exit 2; }
done
val() { awk -F= -v key="$1" '$1==key{print substr($0,index($0,"=")+1)}' <<<"$out"; }
[ "$(val total_shots_player)" -eq 10 ] || { echo "mismatch total_shots_player"; exit 3; }
[ "$(val hits_player)" -eq 4 ] || { echo "mismatch hits_player"; exit 3; }
[ "$(val duration_seconds)" -eq 65 ] || { echo "mismatch duration_seconds"; exit 3; }
if ! grep -qE '^accuracy_player_percent=[0-9]+\.[0-9][0-9]$' <<<"$out"; then echo "bad accuracy_player_percent"; exit 4; fi
if ! grep -qE '^accuracy_ai_percent=[0-9]+\.[0-9][0-9]$' <<<"$out"; then echo "bad accuracy_ai_percent"; exit 4; fi
echo "$out"
EOF
	chmod +x "$TMPDIR/wrapper2.sh"
	run timeout 5s bash "$TMPDIR/wrapper2.sh"
	[ "$status" -eq 0 ]
	[[ "$output" == *"total_shots_player=10"* ]]
	[[ "$output" == *"duration_seconds=65"* ]]
}
