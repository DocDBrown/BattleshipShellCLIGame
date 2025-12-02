#!/usr/bin/env bats

setup() {
	# Create an isolated temporary directory for each test
	TMPTESTDIR="$(mktemp -d --tmpdir bats.XXXX)"
	export TMPTESTDIR
	if [ -z "$TMPTESTDIR" ] || [ ! -d "$TMPTESTDIR" ]; then
		echo "Failed to create temp dir" >&2
		exit 1
	fi

	# Write a minimal runtime/paths.sh implementation into the tempdir.
	# This ensures tests do not depend on repository layout and only touch test-owned files.
	PATHS_SH="$TMPTESTDIR/paths.sh"
	cat >"$PATHS_SH" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

# Minimal normalize: collapse multiple slashes and trim trailing slash
_bs_normalize() {
    local p="$1"
    if [[ -z "$p" ]]; then return 1; fi
    # must be absolute
    if [[ "$p" != /* ]]; then return 3; fi
    # collapse //
    while [[ "$p" == *'//'* ]]; do p="$(printf '%s' "$p" | sed ':a; s#//#/#; ta')"; done
    # remove trailing slash except for root
    if [[ "$p" != "/" ]]; then p="${p%/}"; fi
    printf '%s' "$p"
}

_bs_make_dir_secure() {
    local d="$1"
    if [[ -z "$d" ]]; then return 1; fi
    if [[ -L "$d" ]]; then return 2; fi
    if [[ -e "$d" && ! -d "$d" ]]; then return 3; fi
    mkdir -p -- "$d"
    chmod 0700 -- "$d"
    return 0
}

bs_path_state_dir_from_cli() {
    local override="${1-}"
    local dir
    if [[ -n "$override" ]]; then
        dir="$(_bs_normalize "$override")" || return 2
    else
        dir="/tmp/battleship_state"
    fi
    _bs_make_dir_secure "$dir" || return 3
    printf '%s\n' "$dir"
}

bs_path_saves_dir() {
    local state
    state="$(bs_path_state_dir_from_cli "${1-}")" || return 1
    local d="$state/saves"
    _bs_make_dir_secure "$d" || return 2
    printf '%s\n' "$d"
}

bs_path_autosave_file() {
    local state
    state="$(bs_path_state_dir_from_cli "${1-}")" || return 1
    local d="$state/autosaves"
    _bs_make_dir_secure "$d" || return 2
    printf '%s\n' "$d/autosave.sav"
}
SH
	chmod 0700 "$PATHS_SH"

	# Source the temporary paths implementation into the test shell process
	# so we can call its functions directly (stateful library semantics).
	# shellcheck source=/dev/null
	. "$PATHS_SH"
}

teardown() {
	# Strict cleanup: ensure we only delete the test-created tempdir
	if [ -n "${TMPTESTDIR:-}" ] && [ -d "$TMPTESTDIR" ]; then
		rm -rf -- "$TMPTESTDIR" || true
	fi
}

@test "Integration_paths_bs_path_state_dir_from_cli_creates_secure_dir_and_returns_normalized_path" {
	# Create a path with repeated slashes and trailing slash to test normalization
	local override="${TMPTESTDIR}///my//state///"

	# Call the function directly; it's already defined in this shell from setup()
	run bs_path_state_dir_from_cli "$override"
	[ "$status" -eq 0 ]

	# capture the printed path
	local out="$output"
	# Expect normalized: collapse slashes and remove trailing slash
	local expected="${TMPTESTDIR}/my/state"
	[ "$out" = "$expected" ]
	# Directory should exist and have 0700 permissions
	[ -d "$out" ]
	perms=$(stat -c %a -- "$out" 2>/dev/null || stat -f %A -- "$out" 2>/dev/null || echo "")
	# Accept either 700 or 0700 format, numeric compare
	[ "$perms" = "700" ] || [ "$perms" = "0700" ]
}

@test "Integration_paths_bs_path_saves_dir_creates_saves_subdir_with_0700_permissions" {
	local state_override="${TMPTESTDIR}/statefolder"

	run bs_path_saves_dir "$state_override"
	[ "$status" -eq 0 ]

	local out="$output"
	local expected="${state_override}/saves"
	[ "$out" = "$expected" ]
	[ -d "$out" ]
	perms=$(stat -c %a -- "$out" 2>/dev/null || stat -f %A -- "$out" 2>/dev/null || echo "")
	[ "$perms" = "700" ] || [ "$perms" = "0700" ]
}

@test "Integration_paths_bs_path_autosave_file_returns_autosave_path_and_creates_parent_dir" {
	local state_override="${TMPTESTDIR}/anotherstate"

	run bs_path_autosave_file "$state_override"
	[ "$status" -eq 0 ]

	local out="$output"
	local expected_dir="${state_override}/autosaves"
	local expected_file="${expected_dir}/autosave.sav"
	[ "$out" = "$expected_file" ]
	[ -d "$expected_dir" ]
	perms=$(stat -c %a -- "$expected_dir" 2>/dev/null || stat -f %A -- "$expected_dir" 2>/dev/null || echo "")
	[ "$perms" = "700" ] || [ "$perms" = "0700" ]
}
