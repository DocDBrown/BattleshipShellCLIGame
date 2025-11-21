#!/usr/bin/env bats

setup() {
	TMPDIR_TEST="$(mktemp -d)"
	SCRIPT="$BATS_TEST_DIRNAME/exit_traps.sh"
}

teardown() {
	rm -rf "$TMPDIR_TEST"
}

@test "unit_cleanup_handles_missing_or_already_removed_temp_paths_gracefully_and_is_idempotent" {
	run bash -c "source \"$SCRIPT\"; p=\"$TMPDIR_TEST/file1\"; touch \"\$p\"; __exit_traps_remove_path_safe \"\$p\"; printf '%s' \$?"
	[ "$status" -eq 0 ]
	[ "$output" = "0" ]
	[ ! -e "$TMPDIR_TEST/file1" ]

	run bash -c "source \"$SCRIPT\"; __exit_traps_remove_path_safe \"$TMPDIR_TEST/file1\"; printf '%s' \$?"
	[ "$status" -eq 0 ]
	[ "$output" = "0" ]
}

@test "unit_atomic_save_does_not_replace_valid_save_when_final_save_exists_and_only_partial_is_present" {
	run bash -c "source \"$SCRIPT\"; final=\"$TMPDIR_TEST/final.txt\"; tmp=\"$TMPDIR_TEST/partial.tmp\"; printf 'FINAL' >\"$TMPDIR_TEST/final.txt\"; printf 'PARTIAL' >\"$TMPDIR_TEST/partial.tmp\"; exit_traps_add_atomic \"\$tmp\" \"\$final\"; __exit_traps_remove_path_safe \"\$tmp\"; printf '%s' \$?"
	[ "$status" -eq 0 ]
	[ "$output" = "0" ]

	run bash -c "cat \"$TMPDIR_TEST/final.txt\""
	[ "$status" -eq 0 ]
	[ "$output" = "FINAL" ]
	[ ! -e "$TMPDIR_TEST/partial.tmp" ]
}

@test "unit_atomic_save_removes_partial_temp_save_when_no_final_save_exists" {
	run bash -c "source \"$SCRIPT\"; tmp=\"$TMPDIR_TEST/only_partial.tmp\"; printf 'PARTIAL' >\"$TMPDIR_TEST/only_partial.tmp\"; exit_traps_add_atomic \"\$tmp\" \"/nonexistent/doesnotmatter\"; __exit_traps_remove_path_safe \"\$tmp\"; printf '%s' \$?"
	[ "$status" -eq 0 ]
	[ "$output" = "0" ]
	[ ! -e "$TMPDIR_TEST/only_partial.tmp" ]
}
