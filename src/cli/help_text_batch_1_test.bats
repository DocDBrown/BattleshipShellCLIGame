#!/usr/bin/env bats

setup() {
	TMP_HOME="$(mktemp -d)"
}

teardown() {
	if [ -n "${TMP_HOME}" ] && [ -d "${TMP_HOME}" ]; then
		rm -rf "${TMP_HOME}"
	fi
}

@test "unit_print_help_includes_privacy_note_offline_operation_no_telemetry" {
	run timeout 5s bash -c ". \"${BATS_TEST_DIRNAME}/help_text.sh\" && battleship_help_long"
	[ "$status" -eq 0 ]
	[[ "$output" == *"does not phone home or report telemetry."* ]]
}

@test "unit_print_help_mentions_accessibility_toggles_no_color_high_contrast_monochrome" {
	run timeout 5s bash -c ". \"${BATS_TEST_DIRNAME}/help_text.sh\" && battleship_help_accessibility"
	[ "$status" -eq 0 ]
	[[ "$output" == *"--no-color"* ]]
	[[ "$output" == *"--high-contrast"* ]]
	[[ "$output" == *"--monochrome"* ]]
}

@test "unit_print_help_mentions_state_directory_behavior_and_default_paths" {
	# Ensure predictable default by overriding HOME for this invocation
	run timeout 5s bash -c "HOME='${TMP_HOME}' . \"${BATS_TEST_DIRNAME}/help_text.sh\" && battleship_help_privacy_and_state"
	[ "$status" -eq 0 ]
	expected_path="${TMP_HOME}/.local/share/battleship"
	[[ "$output" == *"${expected_path}"* ]]
}

@test "unit_print_help_allows_minimal_ANSI_when_NO_COLOR_unset" {
	# When BATTLESHIP_NO_COLOR is not set to 1 and MONOCHROME not set, minimal ANSI should be present
	run timeout 5s bash -c ". \"${BATS_TEST_DIRNAME}/help_text.sh\" && battleship_help_long"
	[ "$status" -eq 0 ]
	esc="$(printf '\\033[1m')"
	# Ensure the bold sequence appears in the output
	[[ "$output" == *"$esc"* ]]
}

@test "unit_NO_COLOR_env_prevents_all_ANSI_in_help_and_version_outputs" {
	# Help output
	run timeout 5s bash -c "BATTLESHIP_NO_COLOR=1 . \"${BATS_TEST_DIRNAME}/help_text.sh\" && battleship_help_long"
	[ "$status" -eq 0 ]
	# Assert no ESC (ANSI) bytes present
	if printf '%s' "$output" | grep -q $'\033'; then
		false
	fi

	# Version output
	run timeout 5s bash -c "BATTLESHIP_NO_COLOR=1 . \"${BATS_TEST_DIRNAME}/help_text.sh\" && battleship_help_version"
	[ "$status" -eq 0 ]
	if printf '%s' "$output" | grep -q $'\033'; then
		false
	fi
}
