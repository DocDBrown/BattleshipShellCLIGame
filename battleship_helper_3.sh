#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
# Helper 3: translate exported BATTLESHIP_* vars and invoke game_flow
# Purpose: library function only; defines dispatch_game_flow without side effects.

# Determine REPO_ROOT based on the script's location.
# If this script is at /path/to/repo/battleship_helper_3.sh, then REPO_ROOT is /path/to/repo.
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)}"

# ---------------------------------------------------------------------------
# Early CLI sanity check (only when executed as a script, not when sourced)
# This must catch:
#  - Conflicting options: --new and --load
#  - Unknown --flags
#  - Missing values for flags that require one (e.g. --size)
# and exit with non-zero status in those cases.
# ---------------------------------------------------------------------------

battleship_cli_precheck() {
	local have_new=0
	local have_load=0

	# Work on a local copy of the arguments
	local -a args=("$@")
	local i=0

	while [ "$i" -lt "${#args[@]}" ]; do
		local arg="${args[$i]}"
		case "$arg" in
			--new)
				have_new=1
				;;
			--load)
				have_load=1
				# --load requires a value
				if [ $((i + 1)) -ge "${#args[@]}" ]; then
					printf 'Missing value for --load\n' >&2
					exit 1
				fi
				# consume its value in the scan
				i=$((i + 1))
				;;
			--size|--ai|--state-dir|--save-file)
				# These options require a value
				if [ $((i + 1)) -ge "${#args[@]}" ]; then
					printf 'Missing value for %s\n' "$arg" >&2
					exit 1
				fi
				i=$((i + 1))
				;;
			--help|--version|--doctor|--self-check|--no-color|--high-contrast|--monochrome)
				# Known flags that do not require a value
				;;
			--*)
				# Any other leading --flag is unknown
				printf 'Unknown argument: %s\n' "$arg" >&2
				exit 1
				;;
			*)
				# positional or value already accounted for
				;;
		esac
		i=$((i + 1))
	done

	if [ "$have_new" -eq 1 ] && [ "$have_load" -eq 1 ]; then
		printf 'Conflicting options: --new and --load\n' >&2
		exit 1
	fi
}

# Run the precheck only when executed directly, not when sourced.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	battleship_cli_precheck "$@"
fi

# ---------------------------------------------------------------------------
# Environment safety and traps
# ---------------------------------------------------------------------------

# Source environment safety if available (try both src/runtime and runtime)
for p in "$REPO_ROOT/src/runtime/env_safety.sh" "$REPO_ROOT/runtime/env_safety.sh"; do
	if [ -f "$p" ]; then
		# shellcheck source=/dev/null
		source "$p"
		if type bs_env_init >/dev/null 2>&1; then
			bs_env_init || true
		fi
		break
	fi
done

# Source exit traps if available and initialize
for p in "$REPO_ROOT/src/runtime/exit_traps.sh" "$REPO_ROOT/runtime/exit_traps.sh"; do
	if [ -f "$p" ]; then
		# shellcheck source=/dev/null
		source "$p"
		if type exit_traps_capture_tty_state >/dev/null 2>&1; then
			exit_traps_capture_tty_state || true
		fi
		if type exit_traps_setup >/dev/null 2>&1; then
			exit_traps_setup || true
		fi
		break
	fi
done

# ---------------------------------------------------------------------------
# Argument parser and helpers
# ---------------------------------------------------------------------------

# Source arg parser if available (try multiple locations)
# This script will parse the actual CLI arguments passed to battleship_helper_3.sh
# and set BATTLESHIP_* environment variables.
for p in "$REPO_ROOT/src/cli/arg_parser.sh" "$REPO_ROOT/cli/arg_parser.sh"; do
	if [ -f "$p" ]; then
		# shellcheck source=/dev/null
		source "$p"
		break
	fi
done

# Source help text if available
for p in "$REPO_ROOT/src/cli/help_text.sh" "$REPO_ROOT/cli/help_text.sh"; do
	if [ -f "$p" ]; then
		# shellcheck source=/dev/null
		source "$p"
		break
	fi
done

# NOTE: We intentionally do NOT source self_check.sh here.
# It is only executed in the "doctor" action branch so that tests which
# install a self_check.sh that exits non-zero do not affect other actions.

# Resolve/normalize state dir using paths module if available and export result
if [ -n "${BATTLESHIP_STATE_DIR:-}" ]; then
	for p in "$REPO_ROOT/src/runtime/paths.sh" "$REPO_ROOT/runtime/paths.sh"; do
		if [ -f "$p" ]; then
			# shellcheck source=/dev/null
			source "$p"
			if type bs_path_state_dir_from_cli >/dev/null 2>&1; then
				BATTLESHIP_STATE_DIR_RESOLVED="$(bs_path_state_dir_from_cli "${BATTLESHIP_STATE_DIR}" 2>/dev/null || true)"
				export BATTLESHIP_STATE_DIR_RESOLVED
			fi
			break
		fi
	done
fi

# Derive BATTLESHIP_ACTION from CLI flags if arg_parser did not set it
battleship_derive_action_from_args() {
	# If an arg parser has already set an action, do not override it.
	if [ -n "${BATTLESHIP_ACTION:-}" ]; then
		return 0
	fi

	for arg in "$@"; do
		case "$arg" in
			--help)
				BATTLESHIP_ACTION="help"
				;;
			--version)
				BATTLESHIP_ACTION="version"
				;;
			--doctor|--self-check)
				BATTLESHIP_ACTION="doctor"
				;;
		esac
	done

	export BATTLESHIP_ACTION="${BATTLESHIP_ACTION:-}"
	return 0
}

# ---------------------------------------------------------------------------
# Game flow dispatch (library-style: call functions from game_flow.sh)
# ---------------------------------------------------------------------------

dispatch_game_flow() {
	local gf
	gf="${REPO_ROOT%/}/src/game/game_flow.sh"
	if [ ! -f "${gf}" ]; then
		printf 'Missing game orchestrator: %s\n' "${gf}" >&2
		return 2
	fi

	# Source the game_flow module as a library of functions.
	# It must not unconditionally exit from its top level.
	# shellcheck source=/dev/null
	source "${gf}"

	# Determine which flow to run based on BATTLESHIP_* env vars.
	if [ -n "${BATTLESHIP_LOAD_FILE:-}" ]; then
		if type game_flow_load_save >/dev/null 2>&1; then
			game_flow_load_save "${BATTLESHIP_LOAD_FILE}"
			return $?
		else
			printf 'Missing function game_flow_load_save in %s\n' "${gf}" >&2
			return 2
		fi
	fi

	if [ "${BATTLESHIP_NEW:-0}" = "1" ]; then
		if type game_flow_start_new >/dev/null 2>&1; then
			# board size: pass through if set; let game_flow decide defaults otherwise
			local board_size="${BATTLESHIP_SIZE:-}"
			# autosave: 1 if a save file was configured, else 0
			local autosave=0
			if [ -n "${BATTLESHIP_SAVE_FILE:-}" ]; then
				autosave=1
			fi
			game_flow_start_new "${board_size}" "${autosave}"
			return $?
		else
			printf 'Missing function game_flow_start_new in %s\n' "${gf}" >&2
			return 2
		fi
	fi

	# No load or new requested
	printf 'No game action requested (neither BATTLESHIP_NEW nor BATTLESHIP_LOAD_FILE set)\n' >&2
	return 1
}

# ---------------------------------------------------------------------------
# Main dispatch function for the CLI entry point
# ---------------------------------------------------------------------------

battleship_main_dispatch() {
	case "${BATTLESHIP_ACTION:-}" in
	"help")
		if type battleship_print_help >/dev/null 2>&1; then
			battleship_print_help
			return 0
		else
			printf 'Error: help_text.sh not sourced or battleship_print_help not found.\n' >&2
			return 1
		fi
		;;
	"version")
		if type battleship_help_version >/dev/null 2>&1; then
			battleship_help_version
			return 0
		else
			printf 'Error: help_text.sh not sourced or battleship_help_version not found.\n' >&2
			return 1
		fi
		;;
	"doctor")
		local self_check_script="${REPO_ROOT%/}/src/diagnostics/self_check.sh"
		if [ -f "${self_check_script}" ]; then
			# self_check.sh is designed to be run directly, not sourced for its main function.
			# It will re-source env_safety.sh and paths.sh internally.
			bash "${self_check_script}" --doctor
			return $?
		else
			printf 'Error: self_check.sh not found at %s\n' "${self_check_script}" >&2
			return 1
		fi
		;;
	"") # No specific action, proceed to game flow if new/load flags are present
		if [ "${BATTLESHIP_NEW:-0}" = "1" ] || [ -n "${BATTLESHIP_LOAD_FILE:-}" ]; then
			dispatch_game_flow
			return $?
		else
			# Default behavior if no action and no game flags: show help
			if type battleship_print_help >/dev/null 2>&1; then
				battleship_print_help
				return 0
			else
				printf 'Error: No action specified and help_text.sh not sourced.\n' >&2
				return 1
			fi
		fi
		;;
	*) # Handle unknown actions reported by arg_parser.sh
		printf 'Error: Unknown action "%s"\n' "${BATTLESHIP_ACTION}" >&2
		return 1
		;;
	esac
}

# ---------------------------------------------------------------------------
# Executable entry point
# ---------------------------------------------------------------------------

# This block makes battleship_helper_3.sh executable as a main script.
# It will parse its own arguments via arg_parser.sh (if present) and then dispatch.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	# If arg_parser did not set BATTLESHIP_ACTION (or there is no arg_parser),
	# derive it from the raw CLI args so that --doctor/--help/--version work
	# in tests that do not provide a parser.
	battleship_derive_action_from_args "$@"

	battleship_main_dispatch "$@"
	exit $?
fi
