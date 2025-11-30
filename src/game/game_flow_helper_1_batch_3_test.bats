#!/usr/bin/env bats
# Only load test_helper if present; avoid failures when helper is absent
if [ -f "${BATS_TEST_DIRNAME}/test_helper.bash" ]; then
	load "test_helper"
fi

setup() {
	TMPTEST_DIR="$(mktemp -d)"
	# Ensure cleanup in teardown
	SAVED_TMPDIR="$TMPTEST_DIR"

	# Create minimal repo layout inside TMPTESTDIR
	mkdir -p "$TMPTEST_DIR/persistence" "$TMPTEST_DIR/runtime" "$TMPTEST_DIR/util" "$TMPTEST_DIR/model" "$TMPTEST_DIR/game"

	# Copy the save_state script into test-owned dir
	cp "${BATS_TEST_DIRNAME}/../persistence/save_state.sh" "$TMPTEST_DIR/persistence/save_state.sh"

	# Create runtime/paths.sh implementing bs_path_saves_dir
	cat >"$TMPTEST_DIR/runtime/paths.sh" <<'RPATH'
#!/usr/bin/env bash
bs_path_saves_dir() {
	# If provided, treat first arg as base state dir; otherwise default to cwd/saves
	local state_dir="$1"
	if [[ -n "$state_dir" ]]; then
		printf "%s/saves" "$state_dir"
	else
		printf "%s/saves" "$(pwd)"
	fi
}
export -f bs_path_saves_dir
RPATH

	# Create util/checksum.sh implementing bs_checksum_file and bs_checksum_verify
	cat >"$TMPTEST_DIR/util/checksum.sh" <<'CSUM'
#!/usr/bin/env bash
bs_checksum_file() {
	local file="$1"
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$file" | awk '{print $1}'
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$file" | awk '{print $1}'
	elif command -v openssl >/dev/null 2>&1; then
		openssl dgst -sha256 "$file" | awk '{print $2}'
	else
		return 2
	fi
}

bs_checksum_verify() {
	local expected="$1" file="$2"
	local got
	got="$(bs_checksum_file "$file")" || return 2
	if [[ "${got}" == "${expected}" ]]; then
		return 0
	else
		return 1
	fi
}
export -f bs_checksum_file bs_checksum_verify
CSUM

	# Create a minimal model/board_state.sh used by save_state to emit board lines
	cat >"$TMPTEST_DIR/model/board_state.sh" <<'BOARD'
#!/usr/bin/env bash
BS_BOARD_SIZE=3
bs_board_new() { BS_BOARD_SIZE=${1:-3}; }
bs_board_get_state() { printf "unknown"; }
bs_board_get_owner() { printf ""; }
bs_board_ship_remaining_segments() { printf "0"; }
bs_board_set_ship() { return 0; }
bs_board_set_hit() { return 0; }
bs_board_set_miss() { return 0; }
export -f bs_board_new bs_board_get_state bs_board_get_owner bs_board_ship_remaining_segments bs_board_set_ship bs_board_set_hit bs_board_set_miss
BOARD

	# Create a minimal model/ship_rules.sh
	cat >"$TMPTEST_DIR/model/ship_rules.sh" <<'SR'
#!/usr/bin/env bash
bs_ship_list() { printf "carrier\nbattleship\ncruiser\nsubmarine\ndestroyer\n"; }
bs_ship_length() { case "$1" in carrier) printf 5 ;; battleship) printf 4 ;; cruiser) printf 3 ;; submarine) printf 3 ;; destroyer) printf 2 ;; *) printf 0 ;; esac }
bs_ship_name() { printf "%s" "$1"; }
bs_total_segments() { printf 17; }
bs__sanitize_type() { printf "%s" "${1}"; }
export -f bs_ship_list bs_ship_length bs_ship_name bs_total_segments bs__sanitize_type
SR

	# Minimal game/stats.sh implementing stats_summary_kv and helpers
	cat >"$TMPTEST_DIR/game/stats.sh" <<'GS'
#!/usr/bin/env bash
stats_init() { return 0; }
stats_on_shot() { return 0; }
stats_summary_kv() { printf "start_ts=0\nend_ts=0\n"; }
export -f stats_init stats_on_shot stats_summary_kv
GS

	# Ensure helper scripts are readable
	chmod -R a+r "$TMPTEST_DIR" || true
}

teardown() {
	# Only remove test-owned tempdir
	if [[ -n "$SAVED_TMPDIR" && -d "$SAVED_TMPDIR" ]]; then
		rm -rf -- "$SAVED_TMPDIR"
	fi
}

# Helper: compute checksum over all but the last line of a file
_compute_body_checksum() {
	local file="$1"
	local tmp_body
	tmp_body="$(mktemp)"
	# Copy everything except the last line into a temp file
	# head -n -1 is POSIX-ish enough for our purposes here
	head -n -1 "$file" >"$tmp_body"
	bash -c ". \"$TMPTEST_DIR/util/checksum.sh\"; bs_checksum_file \"$tmp_body\""
	rm -f "$tmp_body"
}

# Test 1: On-demand save creates file inside saves dir and returns path
@test "Integration_OnDemandSave_user_triggers_save_invokes_save_state_within_saves_dir_and_returns_path_to_savefile" {
	# Run the copied save_state script inside the per-test tmp tree
	run timeout 30s bash "$TMPTEST_DIR/persistence/save_state.sh" --state-dir "$TMPTEST_DIR"

	[ "$status" -eq 0 ]
	# Output should be absolute path printed
	file_path="$output"
	test -n "$file_path"

	# Ensure file path is inside the test saves dir
	[[ "$file_path" == "$TMPTEST_DIR/saves"* ]]

	# File must exist
	test -f "$file_path"

	# Compute checksum using the test checksum helper over the body (without footer)
	tail_line="$(tail -n 1 "$file_path")"
	# Expect footer like: ### Checksum: sha256=<hex>
	[[ "$tail_line" =~ sha256=([0-9a-f]{64}) ]]
	embedded="${BASH_REMATCH[1]}"

	sum="$(_compute_body_checksum "$file_path")"
	[ "$sum" = "$embedded" ]
}

# Test 2: Autosave enabled simulation - perform two saves (one per turn) and validate both
@test "Integration_AutosaveEnabled_AfterEachTurn_invokes_save_state_and_creates_valid_savefile_with_sha256_checksum_in_saves_dir" {
	# Ensure saves dir exists
	mkdir -p "$TMPTEST_DIR/saves"

	# Simulate two turns by invoking save_state twice with explicit --out paths to avoid timestamp collision
	out1="$TMPTEST_DIR/saves/turn1.save"
	out2="$TMPTEST_DIR/saves/turn2.save"

	run timeout 30s bash "$TMPTEST_DIR/persistence/save_state.sh" --state-dir "$TMPTEST_DIR" --out "$out1"
	[ "$status" -eq 0 ]
	[ -f "$out1" ]

	run timeout 30s bash "$TMPTEST_DIR/persistence/save_state.sh" --state-dir "$TMPTEST_DIR" --out "$out2"
	[ "$status" -eq 0 ]
	[ -f "$out2" ]

	# Validate checksums for both files (body vs embedded)
	line1="$(tail -n 1 "$out1")"
	[[ "$line1" =~ sha256=([0-9a-f]{64}) ]]
	emb1="${BASH_REMATCH[1]}"
	s1="$(_compute_body_checksum "$out1")"
	[ "$s1" = "$emb1" ]

	line2="$(tail -n 1 "$out2")"
	[[ "$line2" =~ sha256=([0-9a-f]{64}) ]]
	emb2="${BASH_REMATCH[1]}"
	s2="$(_compute_body_checksum "$out2")"
	[ "$s2" = "$emb2" ]

	# Filenames should differ
	[ "$out1" != "$out2" ]
}
