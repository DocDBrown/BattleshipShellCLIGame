#!/usr/bin/env bats

setup() {
	TEST_TMPDIR="$(mktemp -d)"
	if [ -z "${TEST_TMPDIR}" ]; then
		echo "failed to create tmpdir"
		exit 1
	fi
}

teardown() {
	if [ -n "${TEST_TMPDIR:-}" ] && [ -d "${TEST_TMPDIR}" ]; then
		rm -rf -- "${TEST_TMPDIR}"
	fi
	unset TEST_TMPDIR
}

@test "Integration_symlink_temp_paths_removed_as_symlinks_not_targets_and_cleanup_does_not_remove_link_targets" {
	dir="$TEST_TMPDIR/symlink_test"
	mkdir -p "$dir"
	target="$dir/target.txt"
	printf "hello" >"$target"
	link="$dir/link.txt"
	ln -s "$target" "$link"
	# Invoke the removal helper in a subshell that sources the SUT so module settings do not affect this test shell
	run bash -c "source \"$BATS_TEST_DIRNAME/exit_traps.sh\" && __exit_traps_remove_path_safe \"$link\""
	[ "$status" -eq 0 ]
	# the symlink must be removed
	[ ! -e "$link" ]
	# the target file must remain intact with its content
	[ -f "$target" ]
	run cat "$target"
	[ "$status" -eq 0 ]
	[ "$output" = "hello" ]
}

@test "Integration_partial_atomic_save_not_overwrite_existing_valid_save_and_cleanup_leaves_valid_save_intact" {
	dir="$TEST_TMPDIR/atomic_test"
	mkdir -p "$dir"
	target="$dir/save.json"
	printf '{"ok":true}' >"$target"
	tmp="$dir/save.json.tmp"
	printf '{"partial":true}' >"$tmp"
	# Register and remove the temporary file via the removal helper in a subshell
	run bash -c "source \"$BATS_TEST_DIRNAME/exit_traps.sh\" && __exit_traps_remove_path_safe \"$tmp\""
	[ "$status" -eq 0 ]
	# tmp must be removed, target must remain unchanged
	[ ! -e "$tmp" ]
	[ -f "$target" ]
	run cat "$target"
	[ "$status" -eq 0 ]
	[ "$output" = '{"ok":true}' ]
}
