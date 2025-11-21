#!/usr/bin/env bats
setup() {
	__tmpdir_batch_3="$(mktemp -d)" || exit 1
}
teardown() {
	if [[ -n "${__tmpdir_batch_3-}" && -d "${__tmpdir_batch_3}" ]]; then
		rm -rf -- "${__tmpdir_batch_3}"
	fi
}
@test "Integration_bs_path_state_dir_from_cli_accepts_safe_CLI_override_and_creates_directory_with_0700" {
	override="${__tmpdir_batch_3}/state-override"
	run timeout 5s bash -c ". \"$BATS_TEST_DIRNAME/paths.sh\"; bs_path_state_dir_from_cli \"$override\""
	[ "$status" -eq 0 ]
	[ -d "$output" ]
	perms=$(stat -c %a -- "$output")
	[ "$perms" -eq 700 ]
}
@test "Integration_helpers_create_saves_logs_and_autosaves_subdirectories_with_0700_under_resolved_state_dir" {
	export XDG_STATE_HOME="${__tmpdir_batch_3}/xdg_state"
	run timeout 5s bash -c ". \"$BATS_TEST_DIRNAME/paths.sh\"; bs_path_saves_dir"
	[ "$status" -eq 0 ]
	saves_dir="$output"
	[ -d "$saves_dir" ]
	perms=$(stat -c %a -- "$saves_dir")
	[ "$perms" -eq 700 ]
	run timeout 5s bash -c ". \"$BATS_TEST_DIRNAME/paths.sh\"; bs_path_log_file"
	[ "$status" -eq 0 ]
	log_file="$output"
	log_dir="$(dirname "$log_file")"
	[ -d "$log_dir" ]
	perms=$(stat -c %a -- "$log_dir")
	[ "$perms" -eq 700 ]
	[[ "$log_file" == */battleship.log ]]
	run timeout 5s bash -c ". \"$BATS_TEST_DIRNAME/paths.sh\"; bs_path_autosave_file"
	[ "$status" -eq 0 ]
	autosave_file="$output"
	autosave_dir="$(dirname "$autosave_file")"
	[ -d "$autosave_dir" ]
	perms=$(stat -c %a -- "$autosave_dir")
	[ "$perms" -eq 700 ]
	[[ "$autosave_file" == */autosave.sav ]]
}
@test "Integration_cli_override_normalization_and_directory_creation_preserves_permissions_and_returns_normalized_path" {
	raw_override="${__tmpdir_batch_3}//nested///path//to///dir//"
	run timeout 5s bash -c ". \"$BATS_TEST_DIRNAME/paths.sh\"; bs_path_state_dir_from_cli \"$raw_override\""
	[ "$status" -eq 0 ]
	norm="$output"
	[ -d "$norm" ]
	perms=$(stat -c %a -- "$norm")
	[ "$perms" -eq 700 ]
	[[ "$norm" != *'..'* ]]
	[[ "$norm" != *'//'* ]]
	[[ "$norm" != */ ]]
}
