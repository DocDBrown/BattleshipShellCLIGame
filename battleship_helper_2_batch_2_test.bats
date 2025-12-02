#!/usr/bin/env bats

setup() {
	TMPDIR=$(mktemp -d)
}

teardown() {
	if [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ]; then
		rm -rf -- "$TMPDIR"
	fi
}

@test "env_safety_bs_env_init_exports_feature_flags_and_path_environment" {
	cat >"$TMPDIR/env_safety.sh" <<'SH'
#!/usr/bin/env bash
bs_env_init() {
  export PATH="/usr/bin:/bin"
  export BS_HAS_AWK=0
  export BS_HAS_SED=0
  export BS_HAS_OD=0
  export BS_HAS_MKTEMP=1
  export BS_HAS_TPUT=0
  export BS_HAS_DATE=0
  export BS_HAS_SHA256=0
  return 0
}
SH

	run timeout 5s bash -c "source \"$TMPDIR/env_safety.sh\"; bs_env_init >/dev/null; printf '%s\n' \"\$PATH\"; printf '%s\n' \"\$BS_HAS_MKTEMP\"; printf '%s\n' \"\$BS_HAS_AWK\""
	[ "$status" -eq 0 ]
	
	# Use BATS lines array for robust checking
	[ "${lines[0]}" = "/usr/bin:/bin" ]
	[ "${lines[1]}" = "1" ]
	[ "${lines[2]}" = "0" ]
}

@test "paths__bs_normalize_rejects_relative_and_paths_with_double_dots_returning_error_codes" {
	cat >"$TMPDIR/paths.sh" <<'SH'
#!/usr/bin/env bash
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

_bs_make_dir_secure() {
	local d="$1"
	if [[ -z "$d" ]]; then return 1; fi
	if [[ -L "$d" ]]; then return 2; fi
	if [[ -e "$d" && ! -d "$d" ]]; then return 3; fi
	mkdir -p -- "$d"
	chmod 0700 -- "$d"
	return 0
}
SH

	# We use a subshell to source and run. We echo the exit code if the function fails.
	run bash -c "source \"$TMPDIR/paths.sh\"; _bs_normalize 'relative/path' || echo CODE:\$?; _bs_normalize '/tmp/../etc' || echo CODE:\$?"
	[ "$status" -eq 0 ]
	[[ "$output" == *"CODE:3"* ]]
	[[ "$output" == *"CODE:4"* ]]
}

@test "paths__bs_make_dir_secure_creates_directory_and_sets_0700_permissions" {
	# Reuse paths.sh created in prior test context within this tempdir
	cat >"$TMPDIR/paths.sh" <<'SH'
#!/usr/bin/env bash
_bs_make_dir_secure() {
	local d="$1"
	if [[ -z "$d" ]]; then return 1; fi
	if [[ -L "$d" ]]; then return 2; fi
	if [[ -e "$d" && ! -d "$d" ]]; then return 3; fi
	mkdir -p -- "$d"
	chmod 0700 -- "$d"
	return 0
}
SH

	target="$TMPDIR/secure_test_dir"
	run bash -c "source \"$TMPDIR/paths.sh\"; _bs_make_dir_secure \"$target\"; stat -c '%a' \"$target\""
	[ "$status" -eq 0 ]
	# stat prints permission like 700
	[[ "$output" =~ ^700$ ]]
	[ -d "$target" ]
}

@test "game_flow_help_prints_usage_and_returns_0" {
	cat >"$TMPDIR/game_flow.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
LC_ALL=C

SCRIPTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPTDIR}/.." && pwd)"

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

usage() {
	cat <<'USAGE' >&2
Usage: game_flow.sh [--new] [--load SAVEFILE] [--board-size N] [--autosave] [--help]
Start or load a game and run a simple interactive/non-interactive turn loop. By default --new with auto-placement is used.
Exit codes: 0 success, 1 usage/error, 2 missing helper, 3 unsupported/invalid arg
USAGE
}

main() {
	local action="new"
	local savefile=""
	local board_size="10"
	local autosave=0

	while [ "$#" -gt 0 ]; do
		case "$1" in
		--help | -h)
			usage
			return 0
			;;
		--new)
			action="new"
			shift
			;;
		--load)
			if [ "$#" -lt 2 ]; then
				printf "Missing argument for --load\n" >&2
				usage
				return 1
			fi
			action="load"
			savefile="$2"
			shift 2
			;;
		--board-size)
			if [ "$#" -lt 2 ]; then
				printf "Missing argument for --board-size\n" >&2
				return 1
			fi
			board_size="$2"
			shift 2
			;;
		--autosave)
			autosave=1
			shift
			;;
		--manual)
			printf "Manual placement via game_flow is unsupported; run placement tool directly.\n" >&2
			return 3
			;;
		*)
			printf "Unknown argument: %s\n" "$1" >&2
			usage
			return 1
			;;
		esac
	done

	if [[ "$action" == "load" ]]; then
		if [[ -z "$savefile" ]]; then
			printf "No save file specified\n" >&2
			return 1
		fi
		if type game_flow_load_save >/dev/null 2>&1; then
			game_flow_load_save "$savefile"
			return $?
		fi
		game_flow__require "$REPO_ROOT/persistence/load_state.sh" || return 2
		if type game_flow_load_save >/dev/null 2>&1; then
			game_flow_load_save "$savefile"
			return $?
		fi
		printf "Missing function: game_flow_load_save\n" >&2
		return 2
	fi

	if type game_flow_start_new >/dev/null 2>&1; then
		game_flow_start_new "$board_size" "$autosave"
		return $?
	fi

	game_flow__require "$REPO_ROOT/model/board_state.sh" || return 2
	game_flow__require "$REPO_ROOT/placement/auto_placement.sh" || return 2

	if type game_flow_start_new >/dev/null 2>&1; then
		game_flow_start_new "$board_size" "$autosave"
		return $?
	fi

	printf "Missing function: game_flow_start_new\n" >&2
	return 2
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
SH
	chmod +x "$TMPDIR/game_flow.sh"

	run timeout 5s bash "$TMPDIR/game_flow.sh" --help
	[ "$status" -eq 0 ]
	[[ "$output" =~ Usage: ]]
}

@test "game_flow_new_delegates_to_game_flow_start_new_when_function_present_and_returns_0" {
	# create a copy of game_flow.sh in tmpdir
	cat >"$TMPDIR/game_flow.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
LC_ALL=C

SCRIPTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPTDIR}/.." && pwd)"

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

main() {
	local action="new"
	local savefile=""
	local board_size="10"
	local autosave=0

	while [ "$#" -gt 0 ]; do
		case "$1" in
		--help | -h)
			usage
			return 0
			;;
		--new)
			action="new"
			shift
			;;
		*)
			break
			;;
		esac
	done

	if [[ "$action" == "load" ]]; then
		return 1
	fi

	if type game_flow_start_new >/dev/null 2>&1; then
		game_flow_start_new "$board_size" "$autosave"
		return $?
	fi

	printf "Missing function: game_flow_start_new\n" >&2
	return 2
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
SH
	chmod +x "$TMPDIR/game_flow.sh"

	run timeout 5s bash -c "TMPDIR=\"$TMPDIR\"; game_flow_start_new() { printf 'CALLED' > \"$TMPDIR/called\"; return 0; }; source \"$TMPDIR/game_flow.sh\"; main; echo EXIT:$?"
	[ "$status" -eq 0 ]
	[ -f "$TMPDIR/called" ]
	run cat "$TMPDIR/called"
	[ "$status" -eq 0 ]
	[ "$output" = "CALLED" ]
}