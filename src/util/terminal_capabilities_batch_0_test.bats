#!/usr/bin/env bats

setup() {
	TEST_TMPDIR="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp.XXXXXX")"
}

teardown() {
	if [[ "${TEST_TMPDIR:-}" != "${BATS_TEST_DIRNAME}"/* ]]; then
		echo "Refusing to delete unsafe tempdir" >&2
		return 1
	fi
	rm -rf "${TEST_TMPDIR}"
}

create_fake_tput_batch_0() {
	mkdir -p "${TEST_TMPDIR}/bin"
	cat >"${TEST_TMPDIR}/bin/tput" <<'TPUT'
#!/usr/bin/env sh
case "$1" in
  colors) printf '%s' '8' ;;
  bold) printf '\033[1m' ;;
  smso) printf '\033[7m' ;;
  clear) printf '\033[H\033[2J' ;;
  sgr0) printf '\033[0m' ;;
  *) printf '%s' '' ;;
esac
TPUT
	chmod +x "${TEST_TMPDIR}/bin/tput"
}

@test "unit_bs_term_supports_color_returns_false_when_cli_flag_no_color_present" {
	SUT="${BATS_TEST_DIRNAME}/terminal_capabilities.sh"
	run timeout 30s bash -c "BS_NO_COLOR=1; export BS_NO_COLOR; unset NO_COLOR; unset COLORTERM; unset BS_MONOCHROME; source \"$SUT\"; bs_term_supports_color"
	[ "$status" -ne 0 ]
}

@test "unit_bs_term_supports_color_returns_false_when_NO_COLOR_env_set_and_no_cli_flag" {
	SUT="${BATS_TEST_DIRNAME}/terminal_capabilities.sh"
	run timeout 30s bash -c "NO_COLOR=1; export NO_COLOR; unset BS_NO_COLOR; unset COLORTERM; unset BS_MONOCHROME; source \"$SUT\"; bs_term_supports_color"
	[ "$status" -ne 0 ]
}

@test "unit_bs_term_supports_color_returns_false_when_TERM_unset_and_tput_unavailable" {
	SUT="${BATS_TEST_DIRNAME}/terminal_capabilities.sh"
	run timeout 30s bash -c "PATH=''; unset TERM; unset COLORTERM; unset NO_COLOR; unset BS_NO_COLOR; unset BS_MONOCHROME; source \"$SUT\"; bs_term_supports_color"
	[ "$status" -ne 0 ]
}

@test "unit_bs_term_supports_color_returns_true_when_tput_reports_colors_greater_than_zero" {
	SUT="${BATS_TEST_DIRNAME}/terminal_capabilities.sh"
	create_fake_tput_batch_0
	run timeout 30s bash -c "PATH=\"${TEST_TMPDIR}/bin:$PATH\"; TERM=xterm-256color; export TERM; unset NO_COLOR; unset BS_NO_COLOR; unset BS_MONOCHROME; unset COLORTERM; source \"$SUT\"; bs_term_supports_color"
	[ "$status" -eq 0 ]
}

@test "unit_bs_term_supports_color_returns_true_when_tput_unavailable_but_COLORTERM_indicates_truecolor" {
	SUT="${BATS_TEST_DIRNAME}/terminal_capabilities.sh"
	run timeout 30s bash -c "PATH=''; COLORTERM=truecolor; export COLORTERM; unset NO_COLOR; unset BS_NO_COLOR; unset BS_MONOCHROME; unset TERM; source \"$SUT\"; bs_term_supports_color"
	[ "$status" -eq 0 ]
}
