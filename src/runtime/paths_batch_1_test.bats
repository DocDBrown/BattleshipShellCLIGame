#!/usr/bin/env bats

setup() {
	TESTROOT="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp.XXXXXX")"
}

teardown() {
	if [[ -n "${TESTROOT-}" && "${TESTROOT}" == "${BATS_TEST_DIRNAME}"* && -d "${TESTROOT}" ]]; then
		rm -rf -- "${TESTROOT}"
	fi
}

@test "Unit_bs_path_config_dir_from_cli_resolves_config_subdir_normalized_with_XDG_and_fallback" {
	XDG_CONFIG_HOME="${TESTROOT}/xdg_config//"
	HOME_OVERRIDE="${TESTROOT}/home//"

	run timeout 5s bash -c "export XDG_CONFIG_HOME='${XDG_CONFIG_HOME}'; export HOME='${HOME_OVERRIDE}'; . \"${BATS_TEST_DIRNAME}/paths.sh\"; bs_path_config_dir_from_cli"
	[ "$status" -eq 0 ]
	expected="$(printf '%s' "${XDG_CONFIG_HOME}/battleship" | sed ':a; s#//#/#; ta' | sed 's#/$##')"
	[ "$output" = "${expected}" ]

	run timeout 5s bash -c "unset XDG_CONFIG_HOME; export HOME='${HOME_OVERRIDE}'; . \"${BATS_TEST_DIRNAME}/paths.sh\"; bs_path_config_dir_from_cli"
	[ "$status" -eq 0 ]
	expected2="$(printf '%s' "${HOME_OVERRIDE%/}/.config/battleship" | sed ':a; s#//#/#; ta' | sed 's#/$##')"
	[ "$output" = "${expected2}" ]
}

@test "Unit_bs_path_cache_dir_from_cli_resolves_cache_subdir_normalized_with_XDG_and_fallback" {
	XDG_CACHE_HOME="${TESTROOT}/xdg_cache//"
	HOME_OVERRIDE="${TESTROOT}/home//"

	run timeout 5s bash -c "export XDG_CACHE_HOME='${XDG_CACHE_HOME}'; export HOME='${HOME_OVERRIDE}'; . \"${BATS_TEST_DIRNAME}/paths.sh\"; bs_path_cache_dir_from_cli"
	[ "$status" -eq 0 ]
	expected="$(printf '%s' "${XDG_CACHE_HOME}/battleship" | sed ':a; s#//#/#; ta' | sed 's#/$##')"
	[ "$output" = "${expected}" ]

	run timeout 5s bash -c "unset XDG_CACHE_HOME; export HOME='${HOME_OVERRIDE}'; . \"${BATS_TEST_DIRNAME}/paths.sh\"; bs_path_cache_dir_from_cli"
	[ "$status" -eq 0 ]
	expected2="$(printf '%s' "${HOME_OVERRIDE%/}/.cache/battleship" | sed ':a; s#//#/#; ta' | sed 's#/$##')"
	[ "$output" = "${expected2}" ]
}

@test "Unit_path_helpers_return_correct_child_paths_for_saves_logs_and_autosaves_without_IO" {
	STATE_OVERRIDE="${TESTROOT}/state//"

	run timeout 5s bash -c "export HOME='${TESTROOT}/home'; . \"${BATS_TEST_DIRNAME}/paths.sh\"; bs_path_saves_dir '${STATE_OVERRIDE}'"
	[ "$status" -eq 0 ]
	expected_saves="$(printf '%s' "${STATE_OVERRIDE}/saves" | sed ':a; s#//#/#; ta' | sed 's#/$##')"
	[ "$output" = "${expected_saves}" ]
	[ -d "${output}" ]

	run timeout 5s bash -c "export HOME='${TESTROOT}/home'; . \"${BATS_TEST_DIRNAME}/paths.sh\"; bs_path_log_file '${STATE_OVERRIDE}'"
	[ "$status" -eq 0 ]
	expected_log="$(printf '%s' "${STATE_OVERRIDE}/logs/battleship.log" | sed ':a; s#//#/#; ta' | sed 's#/$##')"
	[ "$output" = "${expected_log}" ]
	[ -d "$(dirname "${output}")" ]

	run timeout 5s bash -c "export HOME='${TESTROOT}/home'; . \"${BATS_TEST_DIRNAME}/paths.sh\"; bs_path_autosave_file '${STATE_OVERRIDE}'"
	[ "$status" -eq 0 ]
	expected_autosave="$(printf '%s' "${STATE_OVERRIDE}/autosaves/autosave.sav" | sed ':a; s#//#/#; ta' | sed 's#/$##')"
	[ "$output" = "${expected_autosave}" ]
	[ -d "$(dirname "${output}")" ]
}
