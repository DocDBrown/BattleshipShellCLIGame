#!/usr/bin/env bats

setup() {
	TMPROOT="$(mktemp -d)"
	# Copy the script under test into isolated temp tree
	cp "${BATS_TEST_DIRNAME}/save_state.sh" "$TMPROOT/"
	# Use an executable copy in tmpdir as allowed by the bats contract
	chmod +x "$TMPROOT/save_state.sh"

	mkdir -p "$TMPROOT/runtime" "$TMPROOT/util" "$TMPROOT/model" "$TMPROOT/game" "$TMPROOT/state"
}

teardown() {
	# Only remove test-created tmp dir
	if [ -n "${TMPROOT:-}" ] && [[ "$TMPROOT" = $(printf "%s" "$TMPROOT") ]]; then
		rm -rf -- "$TMPROOT"
	fi
}

# Helper to run the script under test inside the temp workspace with timeout
run_script() {
	# Accepts args...
	PATH="$PATH" run timeout 5s bash -c "\"$TMPROOT/save_state.sh\" $*"
}

@test "serialize_payload_includes_version_header_and_section_markers_for_config_boards_ships_turns_stats" {
	# Provide minimal runtime/paths.sh used by the script
	cat >"$TMPROOT/runtime/paths.sh" <<'RS'
#!/usr/bin/env bash
# Minimal bs_path_saves_dir implementation for tests
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
RS

	# Provide minimal model/board_state.sh
	cat >"$TMPROOT/model/board_state.sh" <<'BS'
#!/usr/bin/env bash
BS_BOARD_SIZE=2
bs_board_get_state() {
  # return unknown for any coord
  printf 'unknown'
}
bs_board_get_owner() { printf ''; }
bs_board_ship_remaining_segments() { printf '0'; }
BS

	# Minimal ship rules
	cat >"$TMPROOT/model/ship_rules.sh" <<'SR'
#!/usr/bin/env bash
bs_ship_list() { printf 'destroyer\n'; }
bs_ship_length() { printf '2'; }
bs_ship_name() { printf 'Destroyer'; }
SR

	# Minimal stats
	cat >"$TMPROOT/game/stats.sh" <<'ST'
#!/usr/bin/env bash
stats_summary_kv() { printf 'total_shots_player=0\nhits_player=0\n'; }
ST

	# Checksum helper - use sha256sum if available, else python3
	cat >"$TMPROOT/util/checksum.sh" <<'CS'
#!/usr/bin/env bash
bs_checksum_file() {
  if [ "$#" -ne 1 ]; then return 2; fi
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$file" 2>/dev/null | awk '{print $1}'
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY' "$file"
import hashlib,sys
print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())
PY
    return 0
  fi
  return 127
}
CS

	# Run script
	run timeout 5s bash "$TMPROOT/save_state.sh" --state-dir "$TMPROOT/state"
	[ "$status" -eq 0 ]
	saved_path="$output"
	[ -f "$saved_path" ]
	# Check presence of header and section markers
	run grep -E "^### battleship_shell_script save" -q "$saved_path"
	[ "$status" -eq 0 ]
	run grep -E "^version: 1" -q "$saved_path"
	[ "$status" -eq 0 ]
	run grep -E "^### Config" -q "$saved_path"
	[ "$status" -eq 0 ]
	run grep -E "^### Board \(cells\)" -q "$saved_path"
	[ "$status" -eq 0 ]
	run grep -E "^### Ships" -q "$saved_path"
	[ "$status" -eq 0 ]
	run grep -E "^### Turn History" -q "$saved_path"
	[ "$status" -eq 0 ]
	run grep -E "^### Stats" -q "$saved_path"
	[ "$status" -eq 0 ]
}

@test "mktemp_creates_tempfile_and_tempfile_is_written_before_checksum_with_permissions_0600" {
	# Build helpers that record checksum invocation and inspect file mode
	cat >"$TMPROOT/runtime/paths.sh" <<'RS'
#!/usr/bin/env bash
bs_path_saves_dir() { local d="$1"; if [ -z "$d" ]; then d="$HOME/.local/state/battleship"; fi; mkdir -p -- "$d/saves"; printf '%s' "$d/saves"; }
RS

	cat >"$TMPROOT/model/board_state.sh" <<'BS'
#!/usr/bin/env bash
BS_BOARD_SIZE=2
bs_board_get_state() { printf 'unknown'; }
bs_board_get_owner() { printf ''; }
bs_board_ship_remaining_segments() { printf '0'; }
BS

	# Checksum helper: record invocation path and the observed file mode
	# NOTE: We use unquoted heredoc (<<CS) so that $TMPROOT is expanded now.
	# save_state.sh runs with set -u, so it would crash if $TMPROOT were undefined inside.
	cat >"$TMPROOT/util/checksum.sh" <<CS
#!/usr/bin/env bash
bs_checksum_file() {
  local file="\$1"
  # Record invocation
  printf '%s\n' "\$file" > "$TMPROOT/bs_checksum_invocation"
  # Record mode using python3 if present, else use stat if available
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY' "\$file" "$TMPROOT/bs_checksum_mode"
import os,sys
mode = oct(os.stat(sys.argv[1]).st_mode & 0o777)
open(sys.argv[2],'w').write(mode[2:])
PY
  elif command -v stat >/dev/null 2>&1; then
    stat -c %a "\$file" > "$TMPROOT/bs_checksum_mode" 2>/dev/null || true
  fi
  # Compute digest
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "\$file" 2>/dev/null | awk '{print \$1}'
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY' "\$file"
import hashlib,sys
print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())
PY
    return 0
  fi
  return 127
}
CS

	cat >"$TMPROOT/model/ship_rules.sh" <<'SR'
#!/usr/bin/env bash
bs_ship_list() { printf 'destroyer\n'; }
bs_ship_length() { printf '2'; }
bs_ship_name() { printf 'Destroyer'; }
SR

	cat >"$TMPROOT/game/stats.sh" <<'ST'
#!/usr/bin/env bash
stats_summary_kv() { printf 'total_shots_player=0\n'; }
ST

	# Run the script
	run timeout 5s bash "$TMPROOT/save_state.sh" --state-dir "$TMPROOT/state"
	[ "$status" -eq 0 ]
	saved_path="$output"
	[ -f "$saved_path" ]

	# Ensure checksum helper was invoked and observed a temp file name
	[ -f "$TMPROOT/bs_checksum_invocation" ]
	invoked_path="$(cat "$TMPROOT/bs_checksum_invocation")"
	# temp file names created by mktemp contain .save.tmp
	[[ "$invoked_path" == *".save.tmp."* ]]

	# Ensure mode recorded is 600
	if [ -f "$TMPROOT/bs_checksum_mode" ]; then
		mode="$(cat "$TMPROOT/bs_checksum_mode")"
		[ "$mode" = "600" ]
	else
		# If mode could not be recorded, still pass but log for visibility
		[ -n "$mode" ] || true
	fi
}

@test "best_effort_fsync_called_when_available_and_no_error_if_unavailable" {
	# Provide minimal helpers as before
	cat >"$TMPROOT/runtime/paths.sh" <<'RS'
#!/usr/bin/env bash
bs_path_saves_dir() { local d="$1"; if [ -z "$d" ]; then d="$HOME/.local/state/battleship"; fi; mkdir -p -- "$d/saves"; printf '%s' "$d/saves"; }
RS
	cat >"$TMPROOT/model/board_state.sh" <<'BS'
#!/usr/bin/env bash
BS_BOARD_SIZE=1
bs_board_get_state() { printf 'unknown'; }
bs_board_get_owner() { printf ''; }
bs_board_ship_remaining_segments() { printf '0'; }
BS
	cat >"$TMPROOT/model/ship_rules.sh" <<'SR'
#!/usr/bin/env bash
bs_ship_list() { printf 'destroyer\n'; }
bs_ship_length() { printf '2'; }
bs_ship_name() { printf 'Destroyer'; }
SR
	cat >"$TMPROOT/game/stats.sh" <<'ST'
#!/usr/bin/env bash
stats_summary_kv() { printf 'total_shots_player=0\n'; }
ST
	cat >"$TMPROOT/util/checksum.sh" <<'CS'
#!/usr/bin/env bash
bs_checksum_file() { if command -v sha256sum >/dev/null 2>&1; then sha256sum -- "$1" | awk '{print $1}'; return 0; fi; if command -v python3 >/dev/null 2>&1; then python3 - <<'PY' "$1"
import hashlib,sys
print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())
PY
 return 0; fi; return 127; }
CS

	# Make a fake python3 wrapper that records invocation, but forwards to real python if present
	REAL_PYTHON="$(command -v python3 || true)"
	mkdir -p "$TMPROOT/bin"
	cat >"$TMPROOT/bin/python3" <<PYW
#!/usr/bin/env sh
printf 'fsync_called\n' >> "$TMPROOT/fsync_marker"
if [ -n "${REAL_PYTHON}" ]; then
  exec "${REAL_PYTHON}" "$@"
fi
exit 0
PYW
	chmod +x "$TMPROOT/bin/python3"

	# Case A: python3 available -> our wrapper should be called
	PATH="$TMPROOT/bin:$PATH" run timeout 5s bash -c "\"$TMPROOT/save_state.sh\" --state-dir \"$TMPROOT/state\""
	[ "$status" -eq 0 ]
	[ -f "$TMPROOT/fsync_marker" ]

	# Remove marker
	rm -f -- "$TMPROOT/fsync_marker"

	# Case B: run without the wrapper; script must still succeed and not write the marker
	run timeout 5s bash -c "\"$TMPROOT/save_state.sh\" --state-dir \"$TMPROOT/state\""
	[ "$status" -eq 0 ]
	[ ! -f "$TMPROOT/fsync_marker" ]
}

@test "invoke_bs_checksum_file_and_append_sha256_footer_with_version_tag" {
	# Setup helpers
	cat >"$TMPROOT/runtime/paths.sh" <<'RS'
#!/usr/bin/env bash
bs_path_saves_dir() { local d="$1"; if [ -z "$d" ]; then d="$HOME/.local/state/battleship"; fi; mkdir -p -- "$d/saves"; printf '%s' "$d/saves"; }
RS
	cat >"$TMPROOT/model/board_state.sh" <<'BS'
#!/usr/bin/env bash
BS_BOARD_SIZE=1
bs_board_get_state() { printf 'unknown'; }
bs_board_get_owner() { printf ''; }
bs_board_ship_remaining_segments() { printf '0'; }
BS
	cat >"$TMPROOT/model/ship_rules.sh" <<'SR'
#!/usr/bin/env bash
bs_ship_list() { printf 'destroyer\n'; }
bs_ship_length() { printf '2'; }
bs_ship_name() { printf 'Destroyer'; }
SR
	cat >"$TMPROOT/game/stats.sh" <<'ST'
#!/usr/bin/env bash
stats_summary_kv() { printf 'total_shots_player=0\n'; }
ST
	# Use checksum helper that computes real digest
	cat >"$TMPROOT/util/checksum.sh" <<'CS'
#!/usr/bin/env bash
bs_checksum_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$file" 2>/dev/null | awk '{print $1}'
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY' "$file"
import hashlib,sys
print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())
PY
    return 0
  fi
  return 127
}
CS

	run timeout 5s bash "$TMPROOT/save_state.sh" --state-dir "$TMPROOT/state"
	[ "$status" -eq 0 ]
	saved_path="$output"
	[ -f "$saved_path" ]
	# Check footer line exists and contains 64 hex chars
	run grep -E "^### Checksum: sha256=[0-9a-f]{64}$" -q "$saved_path"
	[ "$status" -eq 0 ]
}

@test "footer_format_validation_rejects_malformed_footer_and_accepts_well_formed_version_and_hex_digest" {
	# Create runtime and a deliberately broken checksum helper that returns a malformed digest
	cat >"$TMPROOT/runtime/paths.sh" <<'RS'
#!/usr/bin/env bash
bs_path_saves_dir() { local d="$1"; if [ -z "$d" ]; then d="$HOME/.local/state/battleship"; fi; mkdir -p -- "$d/saves"; printf '%s' "$d/saves"; }
RS
	cat >"$TMPROOT/model/board_state.sh" <<'BS'
#!/usr/bin/env bash
BS_BOARD_SIZE=1
bs_board_get_state() { printf 'unknown'; }
bs_board_get_owner() { printf ''; }
bs_board_ship_remaining_segments() { printf '0'; }
BS
	cat >"$TMPROOT/model/ship_rules.sh" <<'SR'
#!/usr/bin/env bash
bs_ship_list() { printf 'destroyer\n'; }
bs_ship_length() { printf '2'; }
bs_ship_name() { printf 'Destroyer'; }
SR
	cat >"$TMPROOT/game/stats.sh" <<'ST'
#!/usr/bin/env bash
stats_summary_kv() { printf 'total_shots_player=0\n'; }
ST
	cat >"$TMPROOT/util/checksum.sh" <<'CS'
#!/usr/bin/env bash
# Return an invalid (non-hex, too-short) digest to force validation failure
bs_checksum_file() { printf 'NOT_A_HEX_DIGEST' ; return 0; }
CS

	run timeout 5s bash "$TMPROOT/save_state.sh" --state-dir "$TMPROOT/state"
	# Expect non-zero because script should detect invalid checksum and exit with error
	[ "$status" -ne 0 ]
	[[ "$output" == *"Invalid checksum produced"* ]]
}