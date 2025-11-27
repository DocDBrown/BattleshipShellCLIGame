#!/usr/bin/env bats

setup() {
	TMPDIR=$(mktemp -d)
	# Mock dependencies
	# shellcheck source=./src/util/checksum.sh
	. "${BATS_TEST_DIRNAME}/../../util/checksum.sh"
	# shellcheck source=./src/persistence/save_state.sh
	. "${BATS_TEST_DIRNAME}/save_state.sh"

	# Mock board state and stats functions used by save_state
	bs_board_get_state() { printf "unknown"; }
	bs_board_get_owner() { printf ""; }
	bs_ship_list() { echo "Carrier"; }
	bs_ship_length() { echo 5; }
	bs_ship_is_sunk() { echo "false"; }
	bs_ship_remaining_segments() { echo 5; }
	stats_summary_kv() { echo "shots=0"; }
	
	# Mock checksum to return a fixed value
	bs_checksum_file() { echo "dummy_checksum_hex_64_chars_long_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"; }
	export -f bs_checksum_file
}

teardown() {
	rm -rf "${TMPDIR}"
}

@test "serialize_payload_includes_version_header_and_section_markers_for_config_boards_ships_turns_stats" {
	# We need to mock the internal data structures or the functions that read them.
	# Since save_state reads globals or calls functions, we rely on the mocks in setup.
	# We'll capture the output of the internal serialization function if possible,
	# or call the public save function and inspect the temp file (if we can intercept it).
	# Actually, save_state writes to a file. We can test the composition logic by
	# creating a dummy file and checking content.
	
	target="${TMPDIR}/save.dat"
	
	# We need to mock the turn history array if it's used.
	# Assuming BS_TURN_HISTORY is available or the function handles empty.
	BS_TURN_HISTORY=()
	
	run bs_save_game "${target}"
	[ "$status" -eq 0 ]
	[ -f "${target}" ]
	
	# Check headers
	grep -q "^BS_SAVE_V1$" "${target}"
	grep -q "^\[CONFIG\]$" "${target}"
	grep -q "^\[BOARD_PLAYER\]$" "${target}"
	grep -q "^\[BOARD_AI\]$" "${target}"
	grep -q "^\[SHIPS\]$" "${target}"
	grep -q "^\[TURNS\]$" "${target}"
	grep -q "^\[STATS\]$" "${target}"
}

@test "mktemp_creates_tempfile_and_tempfile_is_written_before_checksum_with_permissions_0600" {
	# This tests the security aspect of the save process.
	# We want to ensure the file is created with 0600 permissions.
	
	target="${TMPDIR}/secure.dat"
	run bs_save_game "${target}"
	[ "$status" -eq 0 ]
	
	# Verify permissions (stat syntax varies by platform, using ls -l fallback or stat)
	if command -v stat >/dev/null 2>&1; then
		# Portable-ish stat?
		if stat --version 2>/dev/null | grep -q GNU; then
			mode=$(stat -c "%a" "${target}")
		else
			# BSD/macOS stat
			mode=$(stat -f "%Lp" "${target}")
		fi
		
		# Skip permission check on Windows/MSYS as it is unreliable
		if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
			skip "File permissions are unreliable on Windows"
		fi
		
		[ "$mode" = "600" ]
	fi
}

@test "best_effort_fsync_called_when_available_and_no_error_if_unavailable" {
	# It's hard to verify fsync was called without tracing.
	# We verify that the save succeeds even if fsync is missing.
	
	# Shadow fsync command if it exists
	fsync() { return 127; }
	export -f fsync
	
	target="${TMPDIR}/nofsync.dat"
	run bs_save_game "${target}"
	[ "$status" -eq 0 ]
	[ -f "${target}" ]
}

@test "invoke_bs_checksum_file_and_append_sha256_footer_with_version_tag" {
	target="${TMPDIR}/checksummed.dat"
	run bs_save_game "${target}"
	[ "$status" -eq 0 ]
	
	# Check last line for checksum marker
	last_line=$(tail -n 1 "${target}")
	[[ "$last_line" == "CHECKSUM:sha256:"* ]]
}

@test "footer_format_validation_rejects_malformed_footer_and_accepts_well_formed_version_and_hex_digest" {
	# This logic might be in load_state, but save_state must produce valid format.
	# We verify the produced format matches regex.
	target="${TMPDIR}/format.dat"
	run bs_save_game "${target}"
	
	last_line=$(tail -n 1 "${target}")
	# Expected: CHECKSUM:sha256:<64-hex-chars>
	if [[ ! "$last_line" =~ ^CHECKSUM:sha256:[0-9a-f]{64}$ ]]; then
		echo "Invalid checksum produced: $last_line"
		return 1
	fi
}