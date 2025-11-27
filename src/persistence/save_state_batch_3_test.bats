#!/usr/bin/env bats

setup() {
	TMPDIR=$(mktemp -d)
	mkdir -p "$TMPDIR/persistence" "$TMPDIR/runtime" "$TMPDIR/util"
	# Copy the script under test into an isolated test workspace
	cp "${BATS_TEST_DIRNAME}/save_state.sh" "$TMPDIR/persistence/save_state.sh"

	# Mock runtime/paths.sh
	cat >"$TMPDIR/runtime/paths.sh" <<'EOF'
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
	cat >"$TMPDIR/util/checksum.sh" <<'EOF'
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

	STATE_DIR="$TMPDIR/state"
	mkdir -p "$STATE_DIR"
}

teardown() {
	# Only remove the test-owned temporary directory
	case "$TMPDIR" in
	/*) rm -rf -- "$TMPDIR" ;;
	*) : ;;
	esac
}

@test "Integration: final_path_and_filename_are_within_bs_path_saves_dir_and_not_outside_even_with_override_absent_or_malicious" {
	# run without --out to let the script choose an internal saves path
	run timeout 5s bash "$TMPDIR/persistence/save_state.sh" --state-dir "$STATE_DIR"
	[ "$status" -eq 0 ]
	out="$output"
	dir="$(dirname "$out")"
	[ "$dir" = "$STATE_DIR/saves" ]
	[ -f "$out" ]

	# Attempt to override out to an absolute path outside the saves dir (malicious)
	run timeout 5s bash "$TMPDIR/persistence/save_state.sh" --state-dir "$STATE_DIR" --out "/etc/passwd"
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "Output path must be inside saves dir"
}

@test "Integration: handle_missing_checksum_tool_or_unavailable_checksum_implementation_by_returning_error_and_leaving_no_incomplete_target_file" {
	# Remove checksum helper to simulate missing implementation
	rm -f "$TMPDIR/util/checksum.sh"

	run timeout 5s bash "$TMPDIR/persistence/save_state.sh" --state-dir "$STATE_DIR"
	# script is expected to exit with code 2 when checksum helper is not available
	[ "$status" -eq 2 ]

	# Ensure no files (including temporary files) were left in the saves directory
	if [ -d "$STATE_DIR/saves" ]; then
		files=$(ls -A "$STATE_DIR/saves" 2>/dev/null || true)
	else
		files=""
	fi
	[ -z "$files" ]
}

@test "Integration: tempfile_permissions_are_0600_under_varied_umask_and_tempfile_is_removed_on_failure" {
	# Ensure saved file permissions are 0600 under a variety of umasks
	for u in 0022 0077; do
		run timeout 5s bash -c "umask $u; exec bash \"$TMPDIR/persistence/save_state.sh\" --state-dir \"$STATE_DIR\""
		[ "$status" -eq 0 ]
		out="$output"
		[ -f "$out" ]
		perms=$(stat -c %a "$out")
		[ "$perms" -eq 600 ]
		rm -f "$out"
	done

	# Now simulate failure (missing checksum) and ensure temporary files are removed under varied umasks
	for u in 0022 0077; do
		rm -f "$TMPDIR/util/checksum.sh"
		run timeout 5s bash -c "umask $u; exec bash \"$TMPDIR/persistence/save_state.sh\" --state-dir \"$STATE_DIR\""
		[ "$status" -eq 2 ]
		# No temporary files left in the saves directory
		shopt -s nullglob 2>/dev/null || true
		tmpfiles=("$STATE_DIR/saves/"*.save.tmp.*)
		[ "${#tmpfiles[@]}" -eq 0 ]
	done
}
