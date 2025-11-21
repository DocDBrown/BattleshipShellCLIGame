#!/usr/bin/env bats

setup() {
	TMPDIR="$(mktemp -d)"
}

teardown() {
	if [ -n "${TMPDIR-}" ] && [ -d "${TMPDIR}" ]; then
		rm -rf "${TMPDIR}"
	fi
}

@test "Integration_bs_term_supports_color_with_real_tput_reports_true_when_terminal_supports_colors" {
	# Require real tput and at least 8 colors to exercise the integration path
	if ! command -v tput >/dev/null 2>&1; then
		skip "tput not available in environment"
	fi
	# Ask tput about a common color-capable TERM value
	colors=$(TERM=xterm-256color tput colors 2>/dev/null || echo 0)
	case "$colors" in
	'' | *[!0-9]*) colors=0 ;;
	esac
	if [ "$colors" -lt 8 ]; then
		skip "tput reports fewer than 8 colors ($colors)"
	fi

	script_path="${BATS_TEST_DIRNAME}/terminal_capabilities.sh"
	run timeout 10s bash -c "set -euo pipefail; export TERM=xterm-256color; source \"$script_path\"; BS_TERM_PROBED=0; bs_term_probe >/dev/null 2>&1 || true; printf '%s' \"\$BS_TERM_HAS_COLOR\""
	[ "$status" -eq 0 ]
	# Expect the module to report color support in this environment
	[ "$output" -eq 1 ]
}

@test "Integration_bs_term_clear_screen_without_tput_on_PATH_returns_empty_fallback" {
	# Create an isolated directory that does not contain tput and place it early in PATH
	no_tput_dir="${TMPDIR}/no_tput"
	mkdir -p "$no_tput_dir"

	script_path="${BATS_TEST_DIRNAME}/terminal_capabilities.sh"
	# Run with PATH limited so tput is not discoverable, and TERM=dumb to trigger empty clear seq
	run timeout 10s bash -c "set -euo pipefail; PATH=\"$no_tput_dir\"; export PATH; TERM=dumb; source \"$script_path\"; BS_TERM_PROBED=0; bs_term_probe >/dev/null 2>&1 || true; bs_term_clear_screen; echo -n '---END---'"
	[ "$status" -eq 0 ]
	# When no tput is present and TERM=dumb, the clear sequence should be the empty conservative fallback
	[ "$output" = '---END---' ]
}
