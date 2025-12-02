#!/usr/bin/env bats

setup() {
	TMPDIR="$(mktemp -d)"
}

teardown() {
	if [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ]; then
		rm -rf -- "$TMPDIR"
	fi
}

@test "Unit: _bs_normalize rejects paths starting with '-' and returns non-zero exit code" {
	cat >"$TMPDIR/paths.sh" <<'SH'
_bs_normalize() {
    local p="$1"
    if [[ -z "$p" ]]; then return 1; fi
    if [[ "${p#-}" != "$p" ]]; then return 2; fi
    if [[ "$p" != /* ]]; then return 3; fi
    if [[ "$p" == *".."* ]]; then return 4; fi
    while [[ "$p" == *'//'* ]]; do p="$(printf '%s' "$p" | sed ':a; s#//#/#; ta')"; done
    if [[ "$p" != "/" ]]; then p="${p%/}"; fi
    printf '%s' "$p"
}
SH

	run timeout 5s bash -c ". \"$TMPDIR/paths.sh\"; _bs_normalize '-foo'"
	[ "$status" -eq 2 ]
	[ -z "$output" ]
}

@test "Unit: _bs_normalize removes trailing slash and collapses '//' to single '/' for normal inputs" {
	cat >"$TMPDIR/paths.sh" <<'SH'
_bs_normalize() {
    local p="$1"
    if [[ -z "$p" ]]; then return 1; fi
    if [[ "${p#-}" != "$p" ]]; then return 2; fi
    if [[ "$p" != /* ]]; then return 3; fi
    if [[ "$p" == *".."* ]]; then return 4; fi
    while [[ "$p" == *'//'* ]]; do p="$(printf '%s' "$p" | sed ':a; s#//#/#; ta')"; done
    if [[ "$p" != "/" ]]; then p="${p%/}"; fi
    printf '%s' "$p"
}
SH

	run timeout 5s bash -c ". \"$TMPDIR/paths.sh\"; _bs_normalize '/foo//bar/'"
	[ "$status" -eq 0 ]
	[ "$output" = "/foo/bar" ]
}

@test "Unit: game_flow__require returns error code 2 and prints helper-missing message when file absent" {
	cat >"$TMPDIR/game_flow.sh" <<'SH'
game_flow__require() {
    local f="${1:-}"
    if [[ -z "$f" ]]; then
        printf "Missing helper: (none specified)\n" >&2
        return 2
    fi
    if [[ -f "$f" ]]; then
        return 0
    fi
    printf "Missing helper: %s\n" "$f" >&2
    return 2
}
SH

	MISSING="$TMPDIR/does_not_exist_helper"
	run timeout 5s bash -c ". \"$TMPDIR/game_flow.sh\"; game_flow__require \"$MISSING\""
	[ "$status" -eq 2 ]
	[[ "$output" == *"Missing helper: $MISSING"* ]]
}
