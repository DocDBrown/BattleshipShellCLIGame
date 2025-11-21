#!/usr/bin/env bats

setup() {
	:
}

@test "Unit__bs_normalize_empty_input_returns_error" {
	PATHS="$BATS_TEST_DIRNAME/../runtime/paths.sh"
	[ -f "$PATHS" ] || skip "runtime/paths.sh not found"
	run bash -c "set -euo pipefail; source \"$PATHS\"; _bs_normalize \"\""
	[ "$status" -eq 1 ]
}

@test "Unit__bs_normalize_rejects_leading_dash_paths" {
	PATHS="$BATS_TEST_DIRNAME/../runtime/paths.sh"
	[ -f "$PATHS" ] || skip "runtime/paths.sh not found"
	run bash -c "set -euo pipefail; source \"$PATHS\"; _bs_normalize \"-foo\""
	[ "$status" -eq 2 ]
}

@test "Unit__bs_normalize_rejects_non_absolute_paths" {
	PATHS="$BATS_TEST_DIRNAME/../runtime/paths.sh"
	[ -f "$PATHS" ] || skip "runtime/paths.sh not found"
	run bash -c "set -euo pipefail; source \"$PATHS\"; _bs_normalize \"relative/path\""
	[ "$status" -eq 3 ]
}

@test "Unit__bs_normalize_rejects_paths_containing_dotdot" {
	PATHS="$BATS_TEST_DIRNAME/../runtime/paths.sh"
	[ -f "$PATHS" ] || skip "runtime/paths.sh not found"
	run bash -c "set -euo pipefail; source \"$PATHS\"; _bs_normalize \"/foo/../bar\""
	[ "$status" -eq 4 ]
}

@test "Unit__bs_normalize_collapses_double_slashes_and_trims_trailing_slash" {
	PATHS="$BATS_TEST_DIRNAME/../runtime/paths.sh"
	[ -f "$PATHS" ] || skip "runtime/paths.sh not found"
	run bash -c "set -euo pipefail; source \"$PATHS\"; _bs_normalize \"/foo//bar//\""
	[ "$status" -eq 0 ]
	[ "$output" = "/foo/bar" ]
}
