#!/usr/bin/env bats

setup() {
	# ensure cleanup variable is set per test
	TMPDIR_TO_CLEAN=""
}

teardown() {
	if [[ -n "${TMPDIR_TO_CLEAN}" && -e "${TMPDIR_TO_CLEAN}" ]]; then
		rm -rf -- "${TMPDIR_TO_CLEAN}"
	fi
}

@test "Unit__bs_normalize_root_remains_single_slash" {
	run timeout 5s bash -c "source \"${BATS_TEST_DIRNAME}/../runtime/paths.sh\"; _bs_normalize \"/\""
	[ "$status" -eq 0 ]
	[ "$output" = "/" ]
}

@test "Unit__bs_make_dir_secure_empty_argument_returns_error" {
	run timeout 5s bash -c "source \"${BATS_TEST_DIRNAME}/../runtime/paths.sh\"; _bs_make_dir_secure \"\""
	# function returns 1 for empty argument
	[ "$status" -eq 1 ]
}

@test "Unit__bs_make_dir_secure_rejects_symlink_input" {
	tmpdir="$(mktemp -d)"
	TMPDIR_TO_CLEAN="$tmpdir"
	target="$tmpdir/target_file"
	touch "$target"
	link="$tmpdir/symlink"
	ln -s "$target" "$link"

	run timeout 5s bash -c "source \"${BATS_TEST_DIRNAME}/../runtime/paths.sh\"; _bs_make_dir_secure \"$link\""
	# function returns 2 when path is a symlink
	[ "$status" -eq 2 ]
}

@test "Unit__bs_make_dir_secure_rejects_existing_non_directory" {
	tmpdir="$(mktemp -d)"
	TMPDIR_TO_CLEAN="$tmpdir"
	file="$tmpdir/not_a_dir"
	touch "$file"

	run timeout 5s bash -c "source \"${BATS_TEST_DIRNAME}/../runtime/paths.sh\"; _bs_make_dir_secure \"$file\""
	# function returns 3 when path exists but is not a directory
	[ "$status" -eq 3 ]
}

@test "Unit__bs_make_dir_secure_creates_directory_and_sets_0700_permissions" {
	tmpdir="$(mktemp -d)"
	TMPDIR_TO_CLEAN="$tmpdir"
	target_dir="$tmpdir/new_secure_dir/sub"

	run timeout 5s bash -c "source \"${BATS_TEST_DIRNAME}/../runtime/paths.sh\"; _bs_make_dir_secure \"$target_dir\""
	[ "$status" -eq 0 ]
	[ -d "$target_dir" ]
	# Verify permissions are 0700; prefer stat -c for GNU, fall back to stat -f for BSD
	perms="$(stat -c %a "$target_dir" 2>/dev/null || stat -f %A "$target_dir" 2>/dev/null || echo unknown)"
	[ "$perms" = "700" ]
}
