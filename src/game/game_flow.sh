#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
LC_ALL=C

# Entrypoint: argument parsing, environment, and orchestration. Helper implementations are in helper files.
SCRIPTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPTDIR}/.." && pwd)"

# Lightweight require helper: checks presence of a file and reports a
# consistent error code without exiting the shell when sourced.
# Usage: game_flow__require "/abs/path/to/helper.sh"
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

	# best-effort: load common helpers for model/placement/tui/engine/persistence/logger
	# The helper loader is intentionally optional at load-time; call and tolerate failure.
	if type game_flow__load_common_helpers >/dev/null 2>&1; then
		game_flow__load_common_helpers || true
	fi

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

		# If a loader implementation is already supplied (e.g., by tests or a higher-level
		# orchestrator), use it directly without requiring helper files.
		if type game_flow_load_save >/dev/null 2>&1; then
			game_flow_load_save "$savefile"
			return $?
		fi

		# Fallback: require loader helper and then look again for the implementation.
		game_flow__require "$REPO_ROOT/persistence/load_state.sh" || return 2
		if type game_flow_load_save >/dev/null 2>&1; then
			game_flow_load_save "$savefile"
			return $?
		fi

		printf "Missing function: game_flow_load_save\n" >&2
		return 2
	fi

	# new game path:
	# If an orchestration function is already supplied (e.g., by tests or a higher-level
	# module that has set up the environment), delegate to it directly.
	if type game_flow_start_new >/dev/null 2>&1; then
		game_flow_start_new "$board_size" "$autosave"
		return $?
	fi

	# Fallback: require core helpers and then try again for a start handler.
	game_flow__require "$REPO_ROOT/model/board_state.sh" || return 2
	game_flow__require "$REPO_ROOT/placement/auto_placement.sh" || return 2

	if type game_flow_start_new >/dev/null 2>&1; then
		game_flow_start_new "$board_size" "$autosave"
		return $?
	fi

	printf "Missing function: game_flow_start_new\n" >&2
	return 2
}

# Only invoke main when the script is executed directly, not when sourced by tests or other code.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
