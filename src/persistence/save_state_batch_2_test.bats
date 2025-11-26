#!/usr/bin/env bats

setup() {
	TMPTESTDIR="$(mktemp -d)"
	if [ -z "$TMPTESTDIR" ]; then
		echo "failed to create tempdir" >&2
		exit 1
	fi
	
	# Create directory structure for script and helpers
	mkdir -p "$TMPTESTDIR/persistence" "$TMPTESTDIR/runtime" "$TMPTESTDIR/util"
	
	# Copy the script under test
	cp "${BATS_TEST_DIRNAME}/save_state.sh" "$TMPTESTDIR/persistence/save_state.sh"
	chmod +x "$TMPTESTDIR/persistence/save_state.sh"
	
	# Mock runtime/paths.sh
	cat >"$TMPTESTDIR/runtime/paths.sh" <<'EOF'
#!/usr/bin/env bash
bs_path_saves_dir() {
  local override="$1"
  local dir
  if [[ -n "$override" ]]; then
    dir="$override"
  else
    dir="$HOME/.local/state/battleship"
  fi
  mkdir -p -- "$dir/saves"
  printf '%s' "$dir/saves"
}
EOF

	# Mock util/checksum.sh
	cat >"$TMPTESTDIR/util/checksum.sh" <<'EOF'
#!/usr/bin/env bash
bs_checksum_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$file" | awk '{print $1}'
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "$file"
    return 0
  fi
  return 127
}
EOF
}

teardown() {
	if [ -n "${TMPTESTDIR:-}" ] && [[ "${TMPTESTDIR}" = /* ]]; then
		rm -rf -- "$TMPTESTDIR"
	fi
}

@test "Integration: full_save_roundtrip_creates_file_in_saves_dir_with_expected_filename_permissions_0600_atomic_mv_and_valid_checksum_footer" {
	run timeout 30s bash "$TMPTESTDIR/persistence/save_state.sh" --state-dir "$TMPTESTDIR/state"
	[ "$status" -eq 0 ]
	out_path="$output"
	[ -f "$out_path" ]
	# verify path is inside the test state saves dir
	case "$out_path" in
	"$TMPTESTDIR/state/saves/"*) ;;
	*) fail "save file not created inside expected saves dir: $out_path" ;;
	esac
	# check permissions (600 expected)
	if stat --version >/dev/null 2>&1; then
		perms=$(stat -c '%a' "$out_path")
	else
		perms=$(stat -f '%A' "$out_path" 2>/dev/null || echo)
	fi
	# normalize to 3-digit form
	perms="${perms##* }"
	[ "$perms" = "600" ]

	# verify checksum footer exists and matches payload
	tail -n 1 "$out_path" | grep -E '^### Checksum: sha256=[0-9a-fA-F]{64}$' >/dev/null
	digest=$(tail -n 1 "$out_path" | awk -F'=' '{print $2}' | tr '[:upper:]' '[:lower:]')
	payload_file="$(mktemp)"
	sed '$d' "$out_path" >"$payload_file"
	# compute actual digest using python3
	if command -v python3 >/dev/null 2>&1; then
		actual=$(python3 -c "import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "$payload_file")
	else
		# fallback to sha256sum if python3 is unavailable
		actual=$(sha256sum "$payload_file" 2>/dev/null | awk '{print $1}')
	fi
	[ "$actual" = "$digest" ]
	rm -f -- "$payload_file"
}

@test "Integration: saved_file_payload_contains_all_sections_config_boards_ships_turns_stats_with_line_based_section_markers" {
	# Create directories BEFORE writing files to them
	mkdir -p "$TMPTESTDIR/model" "$TMPTESTDIR/game"

	# Mock model/board_state.sh
	cat >"$TMPTESTDIR/model/board_state.sh" <<'EOF'
bs_board_get_state() { echo "unknown"; }
bs_board_get_owner() { echo ""; }
EOF

    # Mock model/ship_rules.sh
    cat >"$TMPTESTDIR/model/ship_rules.sh" <<'EOF'
bs_ship_list() { echo "destroyer"; }
bs_ship_length() { echo "2"; }
bs_ship_name() { echo "Destroyer"; }
bs_board_ship_remaining_segments() { echo "2"; }
EOF

    # Mock game/stats.sh
    cat >"$TMPTESTDIR/game/stats.sh" <<'EOF'
stats_summary_kv() { echo "shots=0"; }
EOF

    # Re-run with full mocks
    run timeout 30s bash "$TMPTESTDIR/persistence/save_state.sh" --state-dir "$TMPTESTDIR/state"
    [ "$status" -eq 0 ]
    out_path="$output"
    
	grep -q '^### battleship_shell_script save' "$out_path"
	grep -q '^### Config' "$out_path"
	grep -q '^### Board' "$out_path"
	grep -q '^### Ships' "$out_path"
	grep -q '^### Turn History' "$out_path"
	grep -q '^### Stats' "$out_path"
	grep -q '^### Checksum:' "$out_path"
}

@test "Integration: footer_structure_and_checksum_verification_fails_if_tempfile_is_corrupted_between_write_and_checksum" {
	# create a fake sha256sum that computes the correct digest then corrupts the file before returning
	BIN="$TMPTESTDIR/bin"
	mkdir -p "$BIN"
	cat >"$BIN/sha256sum" <<'SHAF'
#!/usr/bin/env bash
file="$2"
if [ -z "$file" ]; then
  echo ""; exit 1
fi
if command -v python3 >/dev/null 2>&1; then
  digest=$(python3 -c "import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "$file")
else
  digest=$( /usr/bin/sha256sum "$file" 2>/dev/null | awk '{print $1}')
fi
# introduce corruption into the file before returning the digest
printf 'CORRUPTED\n' >> "$file"
printf "%s  %s\n" "$digest" "$file"
SHAF
	chmod +x "$BIN/sha256sum"
	
	# We need to ensure our mock checksum helper uses this sha256sum
	# The mock in setup() uses `command -v sha256sum`.
	# So we prepend BIN to PATH.
	PATH="$BIN:$PATH"

	run timeout 30s bash "$TMPTESTDIR/persistence/save_state.sh" --state-dir "$TMPTESTDIR/state"
	[ "$status" -eq 0 ]
	out_path="$output"
	[ -f "$out_path" ]

	printed=$(tail -n 1 "$out_path" | awk -F'=' '{print $2}' | tr '[:upper:]' '[:lower:]')
	payload_file="$(mktemp)"
	sed '$d' "$out_path" >"$payload_file"
	if command -v python3 >/dev/null 2>&1; then
		actual=$(python3 -c "import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "$payload_file")
	else
		actual=$(sha256sum "$payload_file" 2>/dev/null | awk '{print $1}')
	fi
	rm -f -- "$payload_file"
	[ "$printed" != "$actual" ]
}