#!/usr/bin/env bats

setup() {
	TMPDIR="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp.XXXXXX")"
	if [[ -z "${TMPDIR}" ]]; then
		fail "failed to create temp dir"
	fi
}

teardown() {
	if [[ -n "${TMPDIR}" && "${TMPDIR}" == "${BATS_TEST_DIRNAME}/"* ]]; then
		rm -rf -- "${TMPDIR}"
	fi
}

@test "Unit__bs_path_autosave_file_returns_autosave_file_path_under_autosaves" {
	run timeout 30s bash -c "source \"${BATS_TEST_DIRNAME}/../runtime/paths.sh\" && bs_path_autosave_file \"${TMPDIR}/state\""
	[ "$status" -eq 0 ]
	expected="${TMPDIR}/state/autosaves/autosave.sav"
	[ "$output" = "$expected" ]
	[ -d "${TMPDIR}/state/autosaves" ]
}

@test "Unit__bs_path_log_file_returns_log_file_path_under_logs" {
	run timeout 30s bash -c "source \"${BATS_TEST_DIRNAME}/../runtime/paths.sh\" && bs_path_log_file \"${TMPDIR}/state\""
	[ "$status" -eq 0 ]
	expected="${TMPDIR}/state/logs/battleship.log"
	[ "$output" = "$expected" ]
	[ -d "${TMPDIR}/state/logs" ]
}
