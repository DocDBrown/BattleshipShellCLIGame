#!/usr/bin/env bats

setup() {
	TEST_TMPDIR="$(mktemp -d)"
	export XDG_STATE_HOME="$TEST_TMPDIR"
	SUT="$BATS_TEST_DIRNAME/logger.sh"
}

teardown() {
	if [[ -n "$TEST_TMPDIR" && "$TEST_TMPDIR" = /* && -d "$TEST_TMPDIR" ]]; then
		rm -rf "$TEST_TMPDIR"
	fi
}

wait_for_pattern_batch_0() {
	local file="${1-}"
	local pattern="${2-}"
	local max=30
	local i=0
	while ((i < max)); do
		if [[ -f "$file" ]] && grep -q -- "$pattern" "$file"; then
			return 0
		fi
		sleep 0.1
		i=$((i + 1))
	done
	return 1
}

@test "test_bs_log_info_writes_timestamped_eventcode_and_message_when_verbose_enabled" {
	logfile="$TEST_TMPDIR/battleship/logs/battleship.log"
	run timeout 30s bash -c "export BS_VERBOSE=1; export XDG_STATE_HOME='$TEST_TMPDIR'; source '$SUT'; bs_log_info 'Info message' '{}'"
	[ "$status" -eq 0 ]
	wait_for_pattern_batch_0 "$logfile" '"message_template":"Info message"' || fail "log entry not found"
	line="$(grep '"message_template":"Info message"' "$logfile" | tail -n1)"
	time_field="$(printf '%s' "$line" | sed -E 's/.*\"time\":\"([^\"]*)\".*/\1/')"
	if ! printf '%s' "$time_field" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'; then
		fail "time not ISO8601: $time_field"
	fi
	printf '%s' "$line" | grep -q '"event_id":"' || fail "event_id missing"
}

@test "test_bs_log_warn_writes_level_label_and_message_when_verbose_enabled" {
	logfile="$TEST_TMPDIR/battleship/logs/battleship.log"
	run timeout 30s bash -c "export BS_VERBOSE=1; export XDG_STATE_HOME='$TEST_TMPDIR'; source '$SUT'; bs_log_warn 'Warn message' '{\"k\":\"v\"}' 500 123"
	[ "$status" -eq 0 ]
	wait_for_pattern_batch_0 "$logfile" '"message_template":"Warn message"' || fail "warn log entry not found"
	grep -q '"level":"WARN"' "$logfile" || fail "WARN level label missing"
}

@test "test_bs_log_error_writes_level_label_and_message_when_verbose_enabled" {
	logfile="$TEST_TMPDIR/battleship/logs/battleship.log"
	run timeout 30s bash -c "export BS_VERBOSE=1; export XDG_STATE_HOME='$TEST_TMPDIR'; source '$SUT'; bs_log_error 'Error happened' '{\"err\":\"x\"}' '{\"code\":123}' 250"
	[ "$status" -eq 0 ]
	wait_for_pattern_batch_0 "$logfile" '"message_template":"Error happened"' || fail "error log entry not found"
	grep -q '"level":"ERROR"' "$logfile" || fail "ERROR level label missing"
}

@test "test_logged_entries_include_standardized_level_label_prefix_for_all_levels" {
	logfile="$TEST_TMPDIR/battleship/logs/battleship.log"
	run timeout 30s bash -c "export BS_VERBOSE=1; export XDG_STATE_HOME='$TEST_TMPDIR'; source '$SUT'; bs_log_info 'L1' '{}'; bs_log_warn 'L2' '{}' 400 10; bs_log_error 'L3' '{}' '{\"e\":\"y\"}'"
	[ "$status" -eq 0 ]
	wait_for_pattern_batch_0 "$logfile" '"message_template":"L3"' || fail "expected entries not found"
	grep -q '"level":"INFO"' "$logfile" || fail "INFO label missing"
	grep -q '"level":"WARN"' "$logfile" || fail "WARN label missing"
	grep -q '"level":"ERROR"' "$logfile" || fail "ERROR label missing"
}

@test "test_logged_entries_include_event_code_and_concise_description_format" {
	logfile="$TEST_TMPDIR/battleship/logs/battleship.log"
	run timeout 30s bash -c "export BS_VERBOSE=1; export XDG_STATE_HOME='$TEST_TMPDIR'; source '$SUT'; bs_log_info 'Concise desc' '{}'; bs_log_warn 'Concise warn' '{}' 404 5"
	[ "$status" -eq 0 ]
	wait_for_pattern_batch_0 "$logfile" '"message_template":"Concise desc"' || fail "info entry missing"
	# Ensure event_id present and non-empty for at least one entry
	line="$(grep '"message_template":"Concise desc"' "$logfile" | tail -n1)"
	event_id="$(printf '%s' "$line" | sed -E 's/.*\"event_id\":\"([^\"]*)\".*/\1/')"
	if [[ -z "$event_id" ]]; then
		fail "event_id empty"
	fi
	# outcome semantics: info -> success, warn -> failure
	grep -q '"message_template":"Concise desc"' "$logfile" || fail "info entry not present"
	grep -q '"outcome":"success"' "$logfile" || fail "info outcome not marked success"
	grep -q '"message_template":"Concise warn"' "$logfile" || fail "warn entry not present"
	grep -q '"outcome":"failure"' "$logfile" || fail "warn outcome not marked failure"
}
