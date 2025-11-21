#!/usr/bin/env bash
# help_text.sh - Static and semi-static help and version text for battleship_shell_script
# This module does NOT parse CLI arguments or perform environment detection.
# It provides functions that the main battleship.sh should call based on parsed flags.

# Package-provided metadata (packagers may override these at build time)
: "${BATTLESHIP_APP_NAME:=battleship_shell_script}"
: "${BATTLESHIP_APP_VERSION:=0.0.0}"
: "${BATTLESHIP_BUILD_DATE:=}"
: "${BATTLESHIP_COMMIT_SHA:=}"

# Accessibility/config toggles: callers may set these environment variables before sourcing/calling.
: "${BATTLESHIP_NO_COLOR:=0}"
: "${BATTLESHIP_HIGH_CONTRAST:=0}"
: "${BATTLESHIP_MONOCHROME:=0}"
: "${BATTLESHIP_STATE_DIR:=${HOME}/.local/share/battleship}"

# Minimal, controlled ANSI. No automatic terminal probing; callers control NO_COLOR/MONOCROME.
if [ "${BATTLESHIP_NO_COLOR}" != "1" ] && [ "${BATTLESHIP_MONOCHROME}" != "1" ]; then
	_BS_BOLD="\033[1m"
	_BS_RESET="\033[0m"
else
	_BS_BOLD=""
	_BS_RESET=""
fi

battleship_help_usage_short() {
	printf "%s\n" "Usage: battleship.sh <command> [options]"
	printf "%s\n" "Commands: new, load, play, help, version"
	printf "%s\n" "Run 'battleship.sh help' or 'battleship.sh help --long' for detailed guidance."
}

battleship_help_board_sizes() {
	printf "%s\n" "Board sizes (examples):"
	printf "  %s\n" "small    : 6x6  (faster games, fewer ships)"
	printf "  %s\n" "standard : 10x10 (classic play, balanced)"
	printf "  %s\n" "large    : 12x12 (longer games, more strategy)"
	printf "%s\n" "Ship counts and layouts vary by size; use 'battleship.sh new --size <size>' to choose."
}

battleship_help_ai_levels() {
	printf "%s\n" "AI difficulty levels:"
	printf "  %s\n" "easy   : random shots, good for learning"
	printf "  %s\n" "normal : mixes hunting and targeting heuristics"
	printf "  %s\n" "hard   : stronger heuristics, fewer mistakes"
	printf "  %s\n" "genius : advanced pattern recognition and optimal play (may take more CPU)"
	printf "%s\n" "Select AI with '--ai <level>' when creating or starting a match."
}

battleship_help_examples() {
	printf "%s\n" "Examples:"
	printf "  %s\n" "battleship.sh new --size standard --ai normal   # create a standard game vs normal AI"
	printf "  %s\n" "battleship.sh new --size small --ai easy       # quick practice game"
	printf "  %s\n" "battleship.sh load /path/to/save.json           # resume a previously saved match"
	printf "  %s\n" "battleship.sh play --local                      # start an interactive local match"
}

battleship_help_accessibility() {
	printf "%s\n" "Accessibility and display toggles (these are flags usable by the top-level CLI):"
	printf "  %s\n" "--no-color       : disable ANSI colors and bold formatting"
	printf "  %s\n" "--high-contrast  : prefer high-contrast palettes for color-capable terminals"
	printf "  %s\n" "--monochrome     : force purely monochrome output, disables color/attributes"
	printf "%s\n" "These toggles must be applied by the launcher; this module respects the corresponding environment variables when set."
}

battleship_help_privacy_and_state() {
	printf "%s\n" "Privacy & state:"
	printf "%s\n" "This application is designed to operate offline by default and does not phone home or report telemetry."
	printf "%s\n" "Game state and user files are stored under the state directory (default: %s)." "${BATTLESHIP_STATE_DIR}"
	printf "%s\n" "You may override the state directory by setting the BATTLESHIP_STATE_DIR environment variable prior to launch."
	printf "%s\n" "Sensitive data is not collected or transmitted by this component; if you integrate it into a larger service, review that service\'s privacy practices."
}

battleship_help_long() {
	printf "%s\n" "${_BS_BOLD}Battleship - Detailed Help${_BS_RESET}"
	battleship_help_usage_short
	printf "\n"
	battleship_help_board_sizes
	printf "\n"
	battleship_help_ai_levels
	printf "\n"
	battleship_help_examples
	printf "\n"
	battleship_help_accessibility
	printf "\n"
	battleship_help_privacy_and_state
}

battleship_help_version() {
	local name="${BATTLESHIP_APP_NAME}"
	local ver="${BATTLESHIP_APP_VERSION}"
	printf "%s\n" "${name} ${ver}"
	if [ -n "${BATTLESHIP_BUILD_DATE}" ]; then
		printf "%s\n" "Build date: ${BATTLESHIP_BUILD_DATE}"
	fi
	if [ -n "${BATTLESHIP_COMMIT_SHA}" ]; then
		printf "%s\n" "Commit: ${BATTLESHIP_COMMIT_SHA}"
	fi
}

# Convenience entry point: callers may invoke this to print the default long help.
battleship_print_help() {
	battleship_help_long
}

# End of help_text.sh
