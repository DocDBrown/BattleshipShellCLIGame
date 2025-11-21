#!/usr/bin/env bats

setup() {
	TEST_TMPDIR=""
}

teardown() {
	if [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ]; then
		rm -rf "$TEST_TMPDIR"
	fi
}

@test "Integration_resolve_state_dir_via_paths_sh_and_emit_normalized_state_dir_without_creating_directory" {
	# Create an isolated temporary directory for test paths
	TEST_TMPDIR=$(mktemp -d)
	# Ensure cleanup will remove only this directory
	[ -d "$TEST_TMPDIR" ]

	raw_path="$TEST_TMPDIR/./a/../b"
	# Run the script with the PATHS_DEFAULT_STATE_DIR environment variable set
	run timeout 30s bash "${BATS_TEST_DIRNAME}/arg_parser.sh"
	# Ensure script executed successfully when no env var set
	[ "$status" -eq 0 ]

	# Run again with PATHS_DEFAULT_STATE_DIR set to a raw, non-normalized absolute path
	PATHS_DEFAULT_STATE_DIR="$raw_path" run timeout 30s bash "${BATS_TEST_DIRNAME}/arg_parser.sh"
	[ "$status" -eq 0 ]
	state_default=$(printf '%s\n' "$output" | grep '^state_dir=' | cut -d= -f2-)
	# Now call with explicit --state-dir using the same raw value
	run timeout 30s bash "${BATS_TEST_DIRNAME}/arg_parser.sh" --state-dir "$raw_path"
	[ "$status" -eq 0 ]
	state_explicit=$(printf '%s\n' "$output" | grep '^state_dir=' | cut -d= -f2-)

	# The normalized value derived from the default should equal the normalized explicit value
	[ "$state_default" = "$state_explicit" ]

	# The script must not create the directory as part of parsing
	[ ! -e "$state_default" ]
}

@test "Integration_explicit_state_dir_overrides_paths_sh_default_and_emits_normalized_path" {
	# Isolated temp dir for inputs
	TEST_TMPDIR=$(mktemp -d)
	[ -d "$TEST_TMPDIR" ]

	default_raw="$TEST_TMPDIR/./default/../d"
	explicit_raw="$TEST_TMPDIR/./explicit/../e"

	# When PATHS_DEFAULT_STATE_DIR is set, the default normalization should be returned if no explicit arg
	PATHS_DEFAULT_STATE_DIR="$default_raw" run timeout 30s bash "${BATS_TEST_DIRNAME}/arg_parser.sh"
	[ "$status" -eq 0 ]
	state_default=$(printf '%s\n' "$output" | grep '^state_dir=' | cut -d= -f2-)

	# When an explicit --state-dir is provided it should override the PATHS_DEFAULT_STATE_DIR value
	PATHS_DEFAULT_STATE_DIR="$default_raw" run timeout 30s bash "${BATS_TEST_DIRNAME}/arg_parser.sh" --state-dir "$explicit_raw"
	[ "$status" -eq 0 ]
	state_overridden=$(printf '%s\n' "$output" | grep '^state_dir=' | cut -d= -f2-)

	# The overridden result should match running with only the explicit argument
	run timeout 30s bash "${BATS_TEST_DIRNAME}/arg_parser.sh" --state-dir "$explicit_raw"
	[ "$status" -eq 0 ]
	state_explicit_only=$(printf '%s\n' "$output" | grep '^state_dir=' | cut -d= -f2-)

	[ "$state_overridden" = "$state_explicit_only" ]

	# Parsing must not create the directory
	[ ! -e "$state_overridden" ]
}
