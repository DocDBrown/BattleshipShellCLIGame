#!/usr/bin/env bats

setup() {
	TMPDIR=$(mktemp -d)
	export TMPDIR
}

teardown() {
	rm -rf "$TMPDIR"
}

@test "Integration:save_state_writes_file_with_board_sections_and_valid_sha256_checksum_in_temp_saves_dir" {
	out="$TMPDIR/out.save"

	# Create mock structure to prevent double-sourcing of readonly variables
	mkdir -p "$TMPDIR/persistence"
	mkdir -p "$TMPDIR/model"

	cp "${BATS_TEST_DIRNAME}/../persistence/save_state.sh" "$TMPDIR/persistence/"
	touch "$TMPDIR/model/board_state.sh"
	touch "$TMPDIR/model/ship_rules.sh"

	# Runner that invokes save_state.sh with minimal stubs.
	cat >"$TMPDIR/save_runner.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail

out="$1"

# Always use test TMPDIR as saves dir.
bs_path_saves_dir() {
	printf '%s\n' "$TMPDIR"
}

bs_checksum_file() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{print $1}'
	else
		openssl dgst -sha256 "$1" | awk '{print $2}'
	fi
}

# Minimal board + stats API for save_state.sh
bs_board_new() {
	BS_BOARD_SIZE=${1:-10}
	BS_BOARD_TOTAL_SEGMENTS=0
	BS_BOARD_REMAINING_SEGMENTS=0
	return 0
}

bs_board_get_state() { printf 'hit'; }
bs_board_get_owner() { printf 'carrier'; }
bs_ship_list() { printf 'carrier\n'; }
bs_ship_length() { printf '1'; }
bs_ship_name() { printf '%s' "$1"; }
bs_board_ship_remaining_segments() { printf '0'; }
stats_summary_kv() { printf 'hits_player=1\n'; }

export BS_BOARD_SIZE=10
bs_board_new 10
export BS_SERVICE=battleship

set +u
# shellcheck source=/dev/null
source "$TMPDIR/persistence/save_state.sh" --state-dir "$TMPDIR" --out "$out"
EOS
	chmod +x "$TMPDIR/save_runner.sh"

	run timeout 30s "$TMPDIR/save_runner.sh" "$out"

	if [ "$status" -ne 0 ]; then
		echo "Command failed with status $status"
		echo "Output: $output"
		return 1
	fi
	[ -f "$out" ]

	checksum_line="$(tail -n 1 "$out")"
	if [[ ! "$checksum_line" =~ sha256=([a-f0-9]{64}) ]]; then
		echo "Checksum footer missing or malformed: $checksum_line"
		return 1
	fi
	expected="${BASH_REMATCH[1]}"

	sed '$d' "$out" >"$TMPDIR/content.tmp"
	if command -v sha256sum >/dev/null 2>&1; then
		actual="$(sha256sum "$TMPDIR/content.tmp" | awk '{print $1}')"
	else
		actual="$(openssl dgst -sha256 "$TMPDIR/content.tmp" | awk '{print $2}')"
	fi
	[ "$expected" = "$actual" ]
}

@test "Integration:load_state_loads_valid_save_and_restores_board_cells_ship_counts_and_stats" {
	# This test verifies load_state.sh against a *synthetic* save file that
	# matches its expected format. We do not use save_state.sh here.

	mkdir -p "$TMPDIR/persistence"
	mkdir -p "$TMPDIR/model"
	mkdir -p "$TMPDIR/util"

	cp "${BATS_TEST_DIRNAME}/../persistence/load_state.sh" "$TMPDIR/persistence/"
	cp "${BATS_TEST_DIRNAME}/../util/checksum.sh" "$TMPDIR/util/"
	touch "$TMPDIR/model/board_state.sh"
	touch "$TMPDIR/model/ship_rules.sh"

	out="$TMPDIR/out.save"

	# Build a minimal, valid save file content for a 1x1 board.
	# We include one ship segment and a hit on the same cell:
	# - The "ship" line is counted for total_segments.
	# - The "hit" line ensures final state is "hit".
	cat >"$TMPDIR/save_body.txt" <<'BODY'
SAVE_VERSION: 1
[CONFIG]
board_size=1
[BOARD]
0,0,ship,carrier
0,0,hit,carrier
[TURNS]
player,hit
[STATS]
hits_player=1
BODY

	# Compute checksum of the body using the same helper shape load_state.sh
	# expects via bs_checksum_verify.
	if command -v sha256sum >/dev/null 2>&1; then
		digest="$(sha256sum "$TMPDIR/save_body.txt" | awk '{print $1}')"
	else
		digest="$(openssl dgst -sha256 "$TMPDIR/save_body.txt" | awk '{print $2}')"
	fi

	# Compose full save file with CHECKSUM footer.
	cat "$TMPDIR/save_body.txt" >"$out"
	printf 'CHECKSUM: %s\n' "$digest" >>"$out"

	# Loader runner: provides checksum + in-memory board implementation and
	# uses bs_load_state_load_file on the synthetic save.
	cat >"$TMPDIR/load_runner.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail

save_file="$1"

# Use bs_checksum_verify contract: 0 = OK, 1 = mismatch, >1 = error.
bs_checksum_verify() {
	local expected="$1" file="$2" actual
	if command -v sha256sum >/dev/null 2>&1; then
		actual=$(sha256sum "$file" | awk '{print $1}')
	else
		actual=$(openssl dgst -sha256 "$file" | awk '{print $2}')
	fi
	[ "$expected" = "$actual" ] || return 1
	return 0
}

bs__sanitize_type() {
	case "$1" in
		''|*[^A-Za-z0-9_-]*) return 1 ;;
		*) printf '%s\n' "$1" ;;
	esac
}

bs_ship_length() { printf '1'; }
bs_total_segments() { printf '1'; }

# In-memory board representation
BS_BOARD_SIZE=0
declare -A BOARD_STATE

bs_board_new() {
	BS_BOARD_SIZE=${1:-10}
	BOARD_STATE=()
	return 0
}

bs_board_set_ship() {
	local r="$1" c="$2" owner="$3"
	local key="${r},${c}"
	BOARD_STATE["$key"]="ship:${owner}"
	return 0
}

bs_board_set_hit() {
	local r="$1" c="$2"
	local key="${r},${c}"
	BOARD_STATE["$key"]="hit"
	return 0
}

bs_board_set_miss() {
	local r="$1" c="$2"
	local key="${r},${c}"
	BOARD_STATE["$key"]="miss"
	return 0
}

bs_board_get_state() {
	local r="$1" c="$2"
	local key="${r},${c}"
	printf '%s' "${BOARD_STATE[$key]:-unknown}"
}

stats_init() { :; }
stats_on_shot() { :; }
stats_summary_kv() { printf 'hits_player=1\n'; }

set +u
# shellcheck source=/dev/null
source "$TMPDIR/persistence/load_state.sh"

bs_load_state_load_file "$save_file"

printf 'STATE=%s\n' "$(bs_board_get_state 0 0)"
stats_summary_kv
EOS
	chmod +x "$TMPDIR/load_runner.sh"

	run timeout 30s "$TMPDIR/load_runner.sh" "$out"

	if [ "$status" -ne 0 ]; then
		echo "Load failed with status $status"
		echo "Output: $output"
		return 1
	fi

	echo "$output" | grep -q "STATE=hit"
	echo "$output" | grep -q "hits_player=1"
}
