#!/usr/bin/env bats

setup() {
	TEST_TMPDIR="$(mktemp -d)"
	# Copy the parser into an isolated tempdir for safe execution/sourcing.
	# The src tree lives under the shell-script directory, so we copy from
	# "${BATS_TEST_DIRNAME}/src/cli/arg_parser.sh" instead of "../src/cli/...".
	cp "${BATS_TEST_DIRNAME}/src/cli/arg_parser.sh" "$TEST_TMPDIR/arg_parser.sh"
	chmod +x "$TEST_TMPDIR/arg_parser.sh"
}

teardown() {
	if [[ -d "$TEST_TMPDIR" ]]; then
		rm -rf -- "$TEST_TMPDIR"
	fi
}

@test "unit_arg_parser_normalize_path_resolves_tilde_and_dotdot_returns_canonical_path" {
	run timeout 5s env HOME="$TEST_TMPDIR" bash -lc "source \"$TEST_TMPDIR/arg_parser.sh\"; normalize_path '~/.config/../mydir//sub/.'"
	[ "$status" -eq 0 ]
	[ "$output" = "$TEST_TMPDIR/mydir/sub" ]
}

@test "unit_arg_parser_invalid_size_non_integer_emits_error_and_exit_code_2" {
	run timeout 5s bash "$TEST_TMPDIR/arg_parser.sh" --size notanint
	[ "$status" -eq 2 ]
	echo "$output" | grep -q "Invalid size: notanint"
}

@test "unit_arg_parser_size_out_of_range_emits_error" {
	run timeout 5s bash "$TEST_TMPDIR/arg_parser.sh" --size 7
	[ "$status" -eq 2 ]
	echo "$output" | grep -q "Size must be between 8 and 12"
}

@test "unit_arg_parser_conflicting_new_and_load_emits_error" {
	run timeout 5s bash "$TEST_TMPDIR/arg_parser.sh" --new --load /some/path
	[ "$status" -eq 2 ]
	echo "$output" | grep -q "Conflicting options: --new and --load"
}

@test "unit_arg_parser_conflicting_color_flags_emit_error" {
	run timeout 5s bash "$TEST_TMPDIR/arg_parser.sh" --no-color --high-contrast
	[ "$status" -eq 2 ]
	echo "$output" | grep -q "Conflicting color flags"
}
