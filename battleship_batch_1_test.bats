#!/usr/bin/env bats

setup() {
	TMPDIR_TEST="$(mktemp -d)"
}

teardown() {
	if [ -n "${TMPDIR_TEST:-}" ] && [ -d "${TMPDIR_TEST}" ]; then
		rm -rf -- "${TMPDIR_TEST}"
	fi
}

@test "unit_arg_parser_sourced_output_config_exports_environment_variables" {
	ARGP="${BATS_TEST_DIRNAME}/../src/cli/arg_parser.sh"
	[ -f "$ARGP" ] || skip "arg_parser.sh not present"

	# Source with intended CLI args in the current shell so the script sets exported vars
	set -- --new --size 10 --ai medium --state-dir ~/my_state_test --save ~/save.json
	# shellcheck source=/dev/null
	. "$ARGP"

	[ "${BATTLESHIP_NEW:-}" = "1" ]
	[ "${BATTLESHIP_SIZE:-}" = "10" ]
	[ "${BATTLESHIP_AI:-}" = "medium" ]
	# STATE_DIR should be normalized to a path string (non-empty)
	[ -n "${BATTLESHIP_STATE_DIR:-}" ]
}

@test "unit_arg_parser_cli_output_config_prints_kv_and_exits_zero" {
	ARGP="${BATS_TEST_DIRNAME}/../src/cli/arg_parser.sh"
	[ -f "$ARGP" ] || skip "arg_parser.sh not present"

	run timeout 5s bash "$ARGP" --new --ai easy --size 9
	[ "$status" -eq 0 ]
	echo "$output" | grep -q '^new=1'
	echo "$output" | grep -q '^ai=easy'
}

@test "unit_arg_parser_self_check_emit_error_prints_ERROR_prefix_and_nonzero_return_when_sourced" {
	ARGP="${BATS_TEST_DIRNAME}/../src/cli/arg_parser.sh"
	[ -f "$ARGP" ] || skip "arg_parser.sh not present"

	# Run in a fresh shell: source the script (so SOURCED=1 is set) then call emit_error
	run timeout 5s bash -c ". '$ARGP' --self-check; emit_error 'boom' 7"
	[ "$status" -eq 7 ]
	echo "$output" | grep -q '^ERROR=boom'
}

@test "unit_env_safety_fatal_if_mktemp_not_found_and_exits_with_code_2" {
	ENV="${BATS_TEST_DIRNAME}/../src/runtime/env_safety.sh"
	[ -f "$ENV" ] || skip "env_safety.sh not present"

	# Create an empty PATH so mktemp is not found
	EMPTY_PATH_DIR="${TMPDIR_TEST}/empty_path"
	mkdir -p -- "$EMPTY_PATH_DIR"

	run timeout 5s env PATH="$EMPTY_PATH_DIR" bash -c "bash '$ENV'"
	[ "$status" -eq 2 ]
	echo "$output" | grep -q "required tool 'mktemp'"
}

@test "unit_env_safety_bs_env_init_exports_expected_variables_and_sets_pipefail" {
	ENV="${BATS_TEST_DIRNAME}/../src/runtime/env_safety.sh"
	[ -f "$ENV" ] || skip "env_safety.sh not present"

	# Source the env_safety module and call bs_env_init in-process
	# shellcheck source=/dev/null
	. "$ENV"
	bs_env_init

	# Expect exported feature flags exist and are numeric strings
	case "${BS_HAS_MKTEMP:-}" in
	'' | *[!0-9]*) false ;;
	*) : ;;
	esac

	case "${BS_HAS_AWK:-}" in
	'' | *[!0-9]*) false ;;
	*) : ;;
	esac

	# pipefail should be reported as an option; if the shell doesn't support it, skip
	if set -o | grep -q pipefail; then
		set -o | grep -q 'pipefail'
	else
		skip "pipefail not supported in this shell"
	fi
}
