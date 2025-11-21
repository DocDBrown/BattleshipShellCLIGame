#!/usr/bin/env bats

setup() {
	TEST_TMPDIR=""
}

teardown() {
	if [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ]; then
		rm -rf "$TEST_TMPDIR"
	fi
}

create_fake_tput_batch_2_test() {
	local dir="$1"
	cat >"$dir/tput" <<'SH'
#!/usr/bin/env bash
case "$1" in
  colors) echo 8 ;;
  bold) printf '\\033[1m' ;;
  smso) printf '\\033[7m' ;;
  clear) printf '\\033[H\\033[2J' ;;
  sgr0) printf '\\033[0m' ;;
  *) exit 0 ;;
esac
SH
	chmod +x "$dir/tput"
}

@test "unit_detects_bold_capability_true_when_tput_reports_bold_capability" {
	TEST_TMPDIR="$(mktemp -d)"
	create_fake_tput_batch_2_test "$TEST_TMPDIR"
	run bash -c "export PATH=\"$TEST_TMPDIR:\$PATH\"; export TERM='xterm-256color'; unset COLORTERM NO_COLOR BS_NO_COLOR BS_MONOCHROME BS_HIGH_CONTRAST; export BS_TERM_PROBED=0; source \"${BATS_TEST_DIRNAME}/terminal_capabilities.sh\"; bs_term_probe; printf 'HAS_BOLD=%s\nHAS_STANDOUT=%s\nHAS_COLOR=%s\nCOLORS=%s\nCLEAR=%s\nRESET=%s\n' \"\$BS_TERM_HAS_BOLD\" \"\$BS_TERM_HAS_STANDOUT\" \"\$BS_TERM_HAS_COLOR\" \"\$BS_TERM_COLORS\" \"\$BS_TERM_CLEAR_SEQ\" \"\$BS_TERM_RESET_SEQ\""
	[ "$status" -eq 0 ]
	[[ "$output" == *"HAS_BOLD=1"* ]]
	[[ "$output" == *"HAS_STANDOUT=1"* ]]
	[[ "$output" == *"HAS_COLOR=1"* ]]
	[[ "$output" == *"COLORS=8"* ]]
}

@test "unit_detects_bold_capability_false_when_tput_unavailable_or_capability_missing" {
	TEST_TMPDIR="$(mktemp -d)"
	# Use an empty PATH directory so tput is unavailable
	run bash -c "export PATH=\"$TEST_TMPDIR\"; export TERM='xterm'; unset COLORTERM NO_COLOR BS_NO_COLOR BS_MONOCHROME BS_HIGH_CONTRAST; export BS_TERM_PROBED=0; source \"${BATS_TEST_DIRNAME}/terminal_capabilities.sh\"; bs_term_probe; printf 'HAS_BOLD=%s\nHAS_STANDOUT=%s\nHAS_COLOR=%s\nCOLORS=%s\n' \"\$BS_TERM_HAS_BOLD\" \"\$BS_TERM_HAS_STANDOUT\" \"\$BS_TERM_HAS_COLOR\" \"\$BS_TERM_COLORS\""
	[ "$status" -eq 0 ]
	[[ "$output" == *"HAS_BOLD=0"* ]]
	[[ "$output" == *"HAS_STANDOUT=0"* ]]
}

@test "unit_detects_standout_capability_true_when_tput_reports_standout_capability" {
	TEST_TMPDIR="$(mktemp -d)"
	create_fake_tput_batch_2_test "$TEST_TMPDIR"
	run bash -c "export PATH=\"$TEST_TMPDIR:\$PATH\"; export TERM='xterm-256color'; unset COLORTERM NO_COLOR BS_NO_COLOR BS_MONOCHROME BS_HIGH_CONTRAST; export BS_TERM_PROBED=0; source \"${BATS_TEST_DIRNAME}/terminal_capabilities.sh\"; bs_term_probe; printf 'HAS_STANDOUT=%s\nHAS_BOLD=%s\n' \"\$BS_TERM_HAS_STANDOUT\" \"\$BS_TERM_HAS_BOLD\""
	[ "$status" -eq 0 ]
	[[ "$output" == *"HAS_STANDOUT=1"* ]]
	[[ "$output" == *"HAS_BOLD=1"* ]]
}

@test "unit_detects_standout_capability_false_when_tput_unavailable_or_capability_missing" {
	TEST_TMPDIR="$(mktemp -d)"
	run bash -c "export PATH=\"$TEST_TMPDIR\"; export TERM='vt100'; unset COLORTERM NO_COLOR BS_NO_COLOR BS_MONOCHROME BS_HIGH_CONTRAST; export BS_TERM_PROBED=0; source \"${BATS_TEST_DIRNAME}/terminal_capabilities.sh\"; bs_term_probe; printf 'HAS_STANDOUT=%s\nHAS_BOLD=%s\n' \"\$BS_TERM_HAS_STANDOUT\" \"\$BS_TERM_HAS_BOLD\""
	[ "$status" -eq 0 ]
	[[ "$output" == *"HAS_STANDOUT=0"* ]]
	[[ "$output" == *"HAS_BOLD=0"* ]]
}

@test "unit_respects_cli_flag_monochrome_disables_color_and_control_sequences" {
	TEST_TMPDIR="$(mktemp -d)"
	create_fake_tput_batch_2_test "$TEST_TMPDIR"
	run bash -c "export PATH=\"$TEST_TMPDIR:\$PATH\"; export TERM='xterm-256color'; unset COLORTERM NO_COLOR BS_NO_COLOR BS_MONOCHROME BS_HIGH_CONTRAST; export BS_MONOCHROME=1; export BS_TERM_PROBED=0; source \"${BATS_TEST_DIRNAME}/terminal_capabilities.sh\"; bs_term_probe; printf 'HAS_COLOR=%s\nHAS_BOLD=%s\nHAS_STANDOUT=%s\nCLEAR=%s\nRESET=%s\n' \"\$BS_TERM_HAS_COLOR\" \"\$BS_TERM_HAS_BOLD\" \"\$BS_TERM_HAS_STANDOUT\" \"\$BS_TERM_CLEAR_SEQ\" \"\$BS_TERM_RESET_SEQ\""
	[ "$status" -eq 0 ]
	[[ "$output" == *"HAS_COLOR=0"* ]]
	[[ "$output" == *"HAS_BOLD=0"* ]]
	[[ "$output" == *"HAS_STANDOUT=0"* ]]
	# Ensure CLEAR and RESET are empty lines
	echo "$output" | grep -q '^CLEAR=$'
	echo "$output" | grep -q '^RESET=$'
}
