#!/usr/bin/env bats
setup() {
	TMPDIR="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp.XXXXXX")" || exit 1
	export XDG_STATE_HOME="$TMPDIR"
	export BS_VERBOSE=1
}
teardown() {
	if [[ -n "${TMPDIR:-}" && "${TMPDIR}" == "${BATS_TEST_DIRNAME}/tmp."* ]]; then
		rm -rf -- "$TMPDIR"
	fi
}
@test "Integration_test_logger_does_not_record_sensitive_tokens_or_board_layouts_in_real_filesystem_logs" {
	json='{"token":"SENSITIVE_TOKEN_12345","board":"LARGE_BOARDDATA_!@#","password":"hunter2","other":"visible"}'
	run bash -c '. "$1/logger.sh"; bs_log_info "saving game" "$2"' -- "$BATS_TEST_DIRNAME" "$json"
	[ "$status" -eq 0 ]
	LOGFILE="$TMPDIR/battleship/logs/battleship.log"
	count=0
	max=50
	while [ $count -lt $max ]; do
		if [ -s "$LOGFILE" ]; then
			break
		fi
		sleep 0.1
		count=$((count + 1))
	done
	[ -s "$LOGFILE" ] || fail "log file was not created or is empty"
	if grep -q "SENSITIVE_TOKEN_12345" "$LOGFILE"; then fail "token was written in cleartext"; fi
	if grep -q "LARGE_BOARDDATA_!@#" "$LOGFILE"; then fail "board layout was written in cleartext"; fi
	if grep -q "hunter2" "$LOGFILE"; then fail "password was written in cleartext"; fi
	grep -q "REDACTED" "$LOGFILE" || fail "expected redaction marker not found in log"
}
