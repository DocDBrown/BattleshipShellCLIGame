#!/usr/bin/env bats

setup() {
	TMP_TEST_DIR="$(mktemp -d)"
}

teardown() {
	if [ -n "$TMP_TEST_DIR" ] && [ -d "$TMP_TEST_DIR" ]; then
		rm -rf "$TMP_TEST_DIR"
	fi
}

@test "unit_bs_env_init_happy_path_all_required_tools_present_initialization_succeeds" {
	# Ensure mktemp is reachable via BS_SAFE_PATH
	mktemp_dir="$(dirname "$(command -v mktemp)")"
	run timeout 5s bash -c "BS_SAFE_PATH='$mktemp_dir' ; source \"${BATS_TEST_DIRNAME}/env_safety.sh\" ; bs_env_init ; printf 'OK'"
	[ "$status" -eq 0 ]
	[[ "$output" == *"OK"* ]]
}

@test "unit_bs_env_init_missing_critical_utility_exits_nonzero_and_emits_concise_message" {
	# Create an empty directory that does not contain mktemp and point BS_SAFE_PATH at it
	NO_MK_DIR="$TMP_TEST_DIR/no_mk_dir"
	mkdir -p "$NO_MK_DIR"
	run timeout 5s bash -c "BS_SAFE_PATH='$NO_MK_DIR' ; source \"${BATS_TEST_DIRNAME}/env_safety.sh\""
	[ "$status" -eq 2 ]
	[[ "$output" == *"battleship_shell_script: required tool 'mktemp' not found in PATH"* ]]
}

@test "unit_bs_env_init_sets_safe_IFS_and_exports_expected_IFS_value" {
	mktemp_dir="$(dirname "$(command -v mktemp)")"
	# Print numeric byte value of IFS (space should be 32)
	run timeout 5s bash -c "BS_SAFE_PATH='$mktemp_dir' ; source \"${BATS_TEST_DIRNAME}/env_safety.sh\" ; bs_env_init ; printf '%s' \"$IFS\" | od -An -t u1 | awk '{print \$1}'"
	[ "$status" -eq 0 ]
	[ "$output" -eq 32 ]
}

@test "unit_bs_env_init_disables_filename_globbing_verify_noglob_set" {
	mktemp_dir="$(dirname "$(command -v mktemp)")"
	run timeout 5s bash -c "BS_SAFE_PATH='$mktemp_dir' ; source \"${BATS_TEST_DIRNAME}/env_safety.sh\" ; bs_env_init ; set -o | awk '/noglob/ {print \$2}'"
	[ "$status" -eq 0 ]
	[[ "$output" == *"on"* ]]
}

@test "unit_bs_env_init_enables_set_eu_and_pipefail_if_supported" {
	mktemp_dir="$(dirname "$(command -v mktemp)")"
	# Emit statuses for errexit, nounset, and pipefail if present
	run timeout 5s bash -c "BS_SAFE_PATH='$mktemp_dir' ; source \"${BATS_TEST_DIRNAME}/env_safety.sh\" ; bs_env_init ; set -o | awk '/errexit/ {print \"errexit=\"\$2}; /nounset/ {print \"nounset=\"\$2}; /pipefail/ {print \"pipefail=\"\$2}'"
	[ "$status" -eq 0 ]
	[[ "$output" == *"errexit=on"* ]]
	[[ "$output" == *"nounset=on"* ]]
	if echo "$output" | grep -q "pipefail="; then
		[ "$(echo "$output" | awk -F= '/pipefail/ {print $2}')" = "on" ]
	fi
}
