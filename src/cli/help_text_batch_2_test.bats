#!/usr/bin/env bats

setup() {
	TMPDIR="$(mktemp -d)"
	export BATTLESHIP_STATE_DIR="${TMPDIR}/state"
	mkdir -p "${BATTLESHIP_STATE_DIR}"
	export BATTLESHIP_NO_COLOR=1
	export BATTLESHIP_MONOCHROME=1
}

teardown() {
	rm -rf "${TMPDIR}"
}

@test "unit_print_version_includes_app_name_and_app_version_always" {
	run timeout 5s bash -c 'export BATTLESHIP_APP_NAME="testname"; export BATTLESHIP_APP_VERSION="1.2.3"; source "'"${BATS_TEST_DIRNAME}"'/help_text.sh"; battleship_help_version'
	[ "$status" -eq 0 ]
	[[ "$output" == *"testname 1.2.3"* ]]
}

@test "unit_print_version_includes_optional_build_date_or_commit_when_present" {
	run timeout 5s bash -c 'export BATTLESHIP_APP_NAME="myapp"; export BATTLESHIP_APP_VERSION="9.9.9"; export BATTLESHIP_BUILD_DATE="2025-11-19"; export BATTLESHIP_COMMIT_SHA="deadbeef"; source "'"${BATS_TEST_DIRNAME}"'/help_text.sh"; battleship_help_version'
	[ "$status" -eq 0 ]
	[[ "$output" == *"myapp 9.9.9"* ]]
	[[ "$output" == *"Build date: 2025-11-19"* ]]
	[[ "$output" == *"Commit: deadbeef"* ]]
}

@test "unit_functions_do_not_parse_arguments_and_ignore_passed_arguments_for_all_exported_functions" {
	funcs=(battleship_help_usage_short battleship_help_board_sizes battleship_help_ai_levels battleship_help_examples battleship_help_accessibility battleship_help_privacy_and_state battleship_help_long battleship_print_help)
	for f in "${funcs[@]}"; do
		cmd='export BATTLESHIP_NO_COLOR=1; export BATTLESHIP_MONOCHROME=1; export BATTLESHIP_STATE_DIR="'"${BATTLESHIP_STATE_DIR}"'"; source "'"${BATS_TEST_DIRNAME}"'/help_text.sh"; '"${f}"
		run timeout 5s bash -c "$cmd"
		[ "$status" -eq 0 ]
		out1="$output"

		cmd_with_args='export BATTLESHIP_NO_COLOR=1; export BATTLESHIP_MONOCHROME=1; export BATTLESHIP_STATE_DIR="'"${BATTLESHIP_STATE_DIR}"'"; source "'"${BATS_TEST_DIRNAME}"'/help_text.sh"; '"${f}"' extra arguments to be ignored'
		run timeout 5s bash -c "$cmd_with_args"
		[ "$status" -eq 0 ]
		out2="$output"

		[ "$out1" = "$out2" ]
	done
}
