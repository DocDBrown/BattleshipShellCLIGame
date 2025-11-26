#!/usr/bin/env bats

setup() {
	TMP_WORK_DIR="$(mktemp -d)"
	# Create minimal layout (script expects ../runtime and ../util relative to its location)
	mkdir -p "$TMP_WORK_DIR/src/persistence" "$TMP_WORK_DIR/src/runtime" "$TMP_WORK_DIR/src/util"
	cp "${BATS_TEST_DIRNAME}/save_state.sh" "$TMP_WORK_DIR/src/persistence/save_state.sh"
	chmod +x "$TMP_WORK_DIR/src/persistence/save_state.sh"
	SUT="$TMP_WORK_DIR/src/persistence/save_state.sh"

	# Create a minimal runtime/paths.sh that can be instructed to fail via env
	cat >"$TMP_WORK_DIR/src/runtime/paths.sh" <<'PATHS'
#!/usr/bin/env bash
set -euo pipefail
bs_path_saves_dir() {
  local override="${1-}"
  if [[ "${FORCE_BS_PATH_SAVES_DIR_FAIL:-}" == "1" ]]; then return 1; fi
  local state="${override:-$HOME/.local/state/battleship}"
  local d="${state%/}/saves"
  mkdir -p -- "$d" 2>/dev/null || return 1
  printf '%s\n' "$d"
}
PATHS
	chmod +x "$TMP_WORK_DIR/src/runtime/paths.sh"

	# Create a limited checksum helper which can be toggled to fail
	cat >"$TMP_WORK_DIR/src/util/checksum.sh" <<'CHK'
#!/usr/bin/env bash
set -euo pipefail
bs_checksum_file() {
  if [ "$#" -ne 1 ]; then return 2; fi
  local file="$1"
  if [[ "${TEST_CHECKSUM_MODE:-}" == "fail" ]]; then return 3; fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$file" | awk '{print $1}'
    return 0
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -- "$file" | awk '{print $1}'
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$file"
    return 0
  fi
  return 127
}
CHK
	chmod +x "$TMP_WORK_DIR/src/util/checksum.sh"

	# Prepare a writable state+saves area
	mkdir -p "$TMP_WORK_DIR/state/saves"
}

teardown() {
	if [[ -n "${TMP_WORK_DIR:-}" && -d "$TMP_WORK_DIR" ]]; then
		rm -rf "$TMP_WORK_DIR"
	fi
}

@test "resolve_destination_using_bs_path_saves_dir_and_reject_override_with_path_traversal_segments" {
	# Run with explicit state-dir; expect success and saved path printed inside saves dir
	run timeout 5s bash "$SUT" --state-dir "$TMP_WORK_DIR/state"
	[ "$status" -eq 0 ]
	[[ "$output" =~ ^"$TMP_WORK_DIR/state/saves/" ]]

	# Try to specify an output outside the saves dir and expect rejection (exit 4)
	OTHER="$TMP_WORK_DIR/other/out.save"
	mkdir -p "$TMP_WORK_DIR/other"
	run timeout 5s bash "$SUT" --state-dir "$TMP_WORK_DIR/state" --out "$OTHER"
	[ "$status" -eq 4 ]
	[[ "$output" == *"Output path must be inside saves dir"* ]]
}

@test "decrement_tempfile_on_error_and_atomic_move_calls_mv_only_after_checksum_success" {
	OUT="$TMP_WORK_DIR/state/saves/test.save"
	# Force checksum helper to fail and ensure no final file and no temp artifacts remain
	run timeout 5s env TEST_CHECKSUM_MODE=fail bash "$SUT" --state-dir "$TMP_WORK_DIR/state" --out "$OUT"
	[ "$status" -ne 0 ]
	[[ "$output" == *"Checksum computation failed"* ]]
	[ ! -f "$OUT" ]
	# Ensure no temporary .save.tmp.* files remain
	shopt -s nullglob
	tmpfiles=("$TMP_WORK_DIR/state/saves/.save.tmp."*)
	[ "${#tmpfiles[@]}" -eq 0 ]
	shopt -u nullglob

	# Now allow checksum to succeed and verify final file exists
	run timeout 5s env TEST_CHECKSUM_MODE=ok bash "$SUT" --state-dir "$TMP_WORK_DIR/state" --out "$OUT"
	[ "$status" -eq 0 ]
	[ -f "$OUT" ]
}

@test "propagate_nonzero_exit_when_bs_checksum_file_returns_error" {
	OUT="$TMP_WORK_DIR/state/saves/prop.save"
	run timeout 5s env TEST_CHECKSUM_MODE=fail bash "$SUT" --state-dir "$TMP_WORK_DIR/state" --out "$OUT"
	[ "$status" -ne 0 ]
	[[ "$output" == *"Checksum computation failed"* ]]
}

@test "fail_when_bs_path_saves_dir_is_unwritable_or_creation_fails" {
	export FORCE_BS_PATH_SAVES_DIR_FAIL=1
	run timeout 5s bash "$SUT" --state-dir "$TMP_WORK_DIR/state"
	[ "$status" -eq 3 ]
	[[ "$output" == *"Failed to determine saves directory"* ]]
	unset FORCE_BS_PATH_SAVES_DIR_FAIL
}
