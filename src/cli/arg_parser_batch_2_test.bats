#!/usr/bin/env bats

setup() {
	SCRIPT="$BATS_TEST_DIRNAME/arg_parser.sh"
}

@test "unit_reject_non_numeric_seed_exits_nonzero_with_error" {
	run timeout 5s bash "$SCRIPT" --seed notanumber
	# should fail
	[ "$status" -ne 0 ]
	# message should indicate invalid seed
	[[ "$output" == *"Invalid seed: notanumber"* ]]
}

@test "unit_parse_color_flags_emit_color_mode_key_and_exits_zero" {
	run timeout 5s bash "$SCRIPT" --high-contrast
	[ "$status" -eq 0 ]
	# color_mode key must be present and set to high-contrast
	grep -x "color_mode=high-contrast" <<<"$output"
}

@test "unit_accept_save_with_file_argument_emits_normalized_save_path_and_exits_zero" {
	TMPDIR=$(mktemp -d)
	file="$TMPDIR/./save.txt"
	# create no repo files other than our temp dir
	run timeout 5s bash "$SCRIPT" --save "$file"
	[ "$status" -eq 0 ]
	# normalized path should remove the ./ segment
	expected="$TMPDIR/save.txt"
	grep -x "save_file=$expected" <<<"$output"
	# cleanup only what we created
	rm -rf "$TMPDIR"
}

@test "unit_error_when_save_missing_argument_exits_nonzero_with_clear_message" {
	run timeout 5s bash "$SCRIPT" --save
	[ "$status" -ne 0 ]
	# check for the precise missing-value message
	[[ "$output" == *"Missing value for --save"* ]]
}

@test "unit_emit_echo_safe_key_value_lines_for_all_supplied_options_format_check" {
	TMPDIR=$(mktemp -d)
	file="$TMPDIR/./savefile.txt"
	run timeout 5s bash "$SCRIPT" --new --size 9 --ai medium --seed 42 --no-color --state-dir "$TMPDIR/./" --save "$file" --doctor
	[ "$status" -eq 0 ]
	# verify presence of expected keys with correct values
	grep -x "new=1" <<<"$output"
	grep -x "size=9" <<<"$output"
	grep -x "ai=medium" <<<"$output"
	grep -x "seed=42" <<<"$output"
	grep -x "no_color=1" <<<"$output"
	grep -x "doctor=1" <<<"$output"
	# normalized state_dir and save_file should point to TMPDIR without ./
	grep -x "state_dir=$TMPDIR" <<<"$output"
	grep -x "save_file=$TMPDIR/savefile.txt" <<<"$output"
	# ensure each output line is echo-safe key=value
	while IFS= read -r line; do
		if [ -z "$line" ]; then continue; fi
		if ! [[ "$line" =~ ^[a-z_]+=.*$ ]]; then
			echo "Line not in key=value form: $line"
			rm -rf "$TMPDIR"
			return 1
		fi
	done <<<"$output"
	# cleanup only what we created
	rm -rf "$TMPDIR"
}
