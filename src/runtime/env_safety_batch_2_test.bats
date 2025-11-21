#!/usr/bin/env bats

setup() {
	# create a per-test temporary workspace inside the test directory to keep cleanup safe
	TMPDIR="$(mktemp -d "${BATS_TEST_DIRNAME}/envtest.XXXXXX")"
	# provide only mktemp in PATH to satisfy mandatory dependency without exposing other tools
	ln -s "$(command -v mktemp)" "$TMPDIR/mktemp"
	SCRIPT="${BATS_TEST_DIRNAME}/env_safety.sh"
}

teardown() {
	if [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ]; then
		rm -rf "$TMPDIR"
	fi
}

@test "unit_bs_env_init_absent_optional_utility_sets_flag_false_and_does_not_exit" {
	run bash -c "BS_SAFE_PATH=\"$TMPDIR\"; . \"$SCRIPT\"; bs_env_init; printf \"%s\n\" \"\$BS_HAS_AWK\""
	[ "$status" -eq 0 ]
	[ "$output" = "0" ]
}

@test "unit_bs_env_init_disables_core_dumps_when_ulimit_supported" {
	run bash -c "BS_SAFE_PATH=\"$TMPDIR\"; . \"$SCRIPT\"; bs_env_init; ulimit -c"
	[ "$status" -eq 0 ]
	# expect core size set to 0 when supported
	[ "$output" = "0" ]
}

@test "unit_bs_env_init_handles_ulimit_unsupported_without_fatal_error" {
	run bash -c "BS_SAFE_PATH=\"$TMPDIR\"; ulimit() { return 2; }; . \"$SCRIPT\"; bs_env_init; echo ok"
	[ "$status" -eq 0 ]
	[ "$output" = "ok" ]
}

@test "unit_bs_env_init_idempotent_on_second_invocation_no_error_no_leak" {
	run bash -c "BS_SAFE_PATH=\"$TMPDIR\"; . \"$SCRIPT\"; bs_env_init; bs_env_init; printf \"%s\n%s\n\" \"\$BS_HAS_MKTEMP\" \"\$PATH\""
	[ "$status" -eq 0 ]
	# first line should show mktemp was detected
	read -r first_line rest <<EOF
$output
EOF
	[ "$first_line" = "1" ]
	# second line should equal the BS_SAFE_PATH we provided
	expected_path="$TMPDIR"
	# extract second line
	second_line="$(printf "%s" "$output" | sed -n '2p')"
	[ "$second_line" = "$expected_path" ]
}
