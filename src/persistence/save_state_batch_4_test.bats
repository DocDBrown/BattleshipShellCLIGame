#!/usr/bin/env bats

setup() {
	TMPROOT="$(mktemp -d)"
	mkdir -p "$TMPROOT/persistence" "$TMPROOT/runtime" "$TMPROOT/util"

	SCRIPT="$TMPROOT/persistence/save_state.sh"
	cp "${BATS_TEST_DIRNAME}/save_state.sh" "$SCRIPT"

	# Mock runtime/paths.sh
	cat >"$TMPROOT/runtime/paths.sh" <<'EOF'
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
	cat >"$TMPROOT/util/checksum.sh" <<'EOF'
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

	OUTFILE="$TMPROOT/saves/explicit.save"
}

teardown() {
	if [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ]; then
		rm -rf -- "$TMPROOT"
	fi
}

@test "Integration: repeated_save_calls_are_idempotent_do_not_produce_partial_writes_and_replace_target_atomically" {
	run timeout 10s bash "$SCRIPT" --state-dir "$TMPROOT" --out "$OUTFILE"
	[ "$status" -eq 0 ]
	[ "$output" = "$OUTFILE" ]

	[ -f "$OUTFILE" ]

	grep -q '^### battleship_shell_script save' "$OUTFILE"

	stored_digest="$(grep '^### Checksum: sha256=' "$OUTFILE" | sed 's/.*=//')"
	[ -n "$stored_digest" ]

	nodigest="$TMPROOT/nodigest.tmp"
	sed '$d' "$OUTFILE" >"$nodigest"
	actual="$(sha256sum "$nodigest" | awk '{print $1}')"
	[ "$stored_digest" = "$actual" ]

	# Ensure no temporary .save.tmp.* artifacts remain in the saves dir
	tmpcount=0
	for f in "$TMPROOT"/saves/.save.tmp.*; do
		if [ -e "$f" ]; then tmpcount=$((tmpcount + 1)); fi
	done
	[ "$tmpcount" -eq 0 ]

	# Run again to ensure idempotent overwrite and valid file remains
	run timeout 10s bash "$SCRIPT" --state-dir "$TMPROOT" --out "$OUTFILE"
	[ "$status" -eq 0 ]
	[ "$output" = "$OUTFILE" ]

	stored_digest2="$(grep '^### Checksum: sha256=' "$OUTFILE" | sed 's/.*=//')"
	sed '$d' "$OUTFILE" >"$nodigest"
	actual2="$(sha256sum "$nodigest" | awk '{print $1}')"
	[ "$stored_digest2" = "$actual2" ]
}
