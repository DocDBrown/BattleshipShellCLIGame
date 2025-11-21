#!/usr/bin/env bats

setup() {
	:
}

teardown() {
	# no global cleanup; each test removes its own tmp dir
	:
}

@test "test_bs_log_appends_rather_than_overwrites_existing_file" {
	tmpdir="$(mktemp -d "$BATS_TEST_DIRNAME/tmp.XXXXXX")"
	logdir="$tmpdir/battleship/logs"
	mkdir -p "$logdir"
	logfile="$logdir/battleship.log"
	printf 'OLDLINE\n' >"$logfile"
	# run the logger; ensure it appends
	run timeout 10s bash -c "export BS_VERBOSE=1; export XDG_STATE_HOME='$tmpdir'; source '$BATS_TEST_DIRNAME/logger.sh'; bs_log_info 'testmsg' '{}'"
	[ "$status" -eq 0 ]
	# original content must remain
	run grep -Fq 'OLDLINE' "$logfile"
	[ "$status" -eq 0 ]
	# new JSON entry should be present
	run grep -Fq '"message_template":"testmsg"' "$logfile"
	[ "$status" -eq 0 ]
	rm -rf "$tmpdir"
}

@test "test_logger_respects_verbose_flag_and_creates_no_file_when_disabled" {
	tmpdir="$(mktemp -d "$BATS_TEST_DIRNAME/tmp.XXXXXX")"
	# verbose disabled (explicit 0)
	run timeout 10s bash -c "export BS_VERBOSE=0; export XDG_STATE_HOME='$tmpdir'; source '$BATS_TEST_DIRNAME/logger.sh'; bs_log_info 'no' '{}'"
	# should fail to emit (non-zero)
	[ "$status" -ne 0 ]
	# no log file created
	[ ! -f "$tmpdir/battleship/logs/battleship.log" ]
	rm -rf "$tmpdir"
}

@test "test_no_op_stubs_return_failure_status_when_log_file_creation_fails" {
	# force path normalization failure by giving HOME a leading hyphen; keep change scoped to subprocess
	run timeout 10s bash -c "export BS_VERBOSE=1; export HOME='-'; source '$BATS_TEST_DIRNAME/logger.sh'; bs_log_info 'x' '{}'"
	# Expect specific non-zero code from emitter when file is unavailable
	[ "$status" -eq 4 ]
}

@test "test_bs_log_warn_and_error_stubs_behave_consistently_on_path_resolution_failure" {
	# force path resolution failure and exercise warn and error paths
	run timeout 10s bash -c "export BS_VERBOSE=1; export HOME='-'; source '$BATS_TEST_DIRNAME/logger.sh'; bs_log_warn 'w' '{}' 500 123"
	[ "$status" -eq 4 ]

	run timeout 10s bash -c "export BS_VERBOSE=1; export HOME='-'; source '$BATS_TEST_DIRNAME/logger.sh'; bs_log_error 'e' '{}' '{\"code\":\"E\"}' 50"
	[ "$status" -eq 4 ]
}

@test "test_bs_log_functions_do_not_record_sensitive_personal_identifiers_or_detailed_board_layouts_in_output" {
	tmpdir="$(mktemp -d "$BATS_TEST_DIRNAME/tmp.XXXXXX")"
	logdir="$tmpdir/battleship/logs"
	logfile="$logdir/battleship.log"
	# create a small helper script in the test-owned tmpdir to avoid complex quoting in-bash
	caller="$tmpdir/caller.sh"
	cat >"$caller" <<'SH'
#!/usr/bin/env bash
export BS_VERBOSE=1
export XDG_STATE_HOME="__XDG__"
source "__SUT__"
bs_log_info 'sensitive' '{"email":"sensitive@example.com","password":"p123","token":"tokval","ip":"1.2.3.4","board":"A1,A2","secret":"topsecret","chat":"user chat content"}'
SH
	# replace placeholders with runtime paths
	sed -i "s|__XDG__|$tmpdir|g" "$caller"
	sed -i "s|__SUT__|$BATS_TEST_DIRNAME/logger.sh|g" "$caller"
	chmod +x "$caller"
	run timeout 10s bash "$caller"
	[ "$status" -eq 0 ]
	# Ensure file exists
	[ -f "$logfile" ]
	# Sensitive raw values must NOT appear
	run grep -Fq 'sensitive@example.com' "$logfile"
	[ "$status" -ne 0 ]
	run grep -Fq 'p123' "$logfile"
	[ "$status" -ne 0 ]
	run grep -Fq 'tokval' "$logfile"
	[ "$status" -ne 0 ]
	run grep -Fq '1.2.3.4' "$logfile"
	[ "$status" -ne 0 ]
	# Board/chat/secret fields should be redacted per module configuration
	run grep -Fq '"email":"REDACTED"' "$logfile"
	[ "$status" -eq 0 ]
	run grep -Fq '"password":"REDACTED"' "$logfile"
	[ "$status" -eq 0 ]
	run grep -Fq '"token":"REDACTED"' "$logfile"
	[ "$status" -eq 0 ]
	run grep -Fq '"ip":"REDACTED"' "$logfile"
	[ "$status" -eq 0 ]
	run grep -Fq '"board":"REDACTED"' "$logfile"
	[ "$status" -eq 0 ]
	run grep -Fq '"chat":"REDACTED"' "$logfile"
	[ "$status" -eq 0 ]

	rm -rf "$tmpdir"
}
