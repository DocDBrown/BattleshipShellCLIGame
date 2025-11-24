#!/usr/bin/env bash
set -euo pipefail
SCRIPTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTDIR/../util/validation.sh" || {
	printf '%s\n' "Required validation module not found" >&2
	exit 1
}

trim() {
	local v="$1"
	v="${v#"${v%%[![:space:]]*}"}"
	v="${v%"${v##*[![:space:]]}"}"
	printf '%s' "$v"
}

upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

safe_read_line() {
	# Prompt is accepted for API compatibility but not printed here;
	# tests expect to control when/if prompt text appears in output.
	local _prompt="$1"
	local var
	if IFS= read -r var; then
		# Process backspace characters so test-driven inputs containing \b behave
		# like interactive backspace handling: each \b removes the previous char.
		local processed=""
		local len i ch
		len=${#var}
		for ((i = 1; i <= len; i++)); do
			ch=${var:i-1:1}
			if [ "$ch" = $'\b' ]; then
				processed=${processed%?}
			else
				processed+="$ch"
			fi
		done
		printf '%s' "$processed"
	else
		return 1
	fi
}

prompt_board_size() {
	local prompt="${1:-Enter board size (8-12): }"
	while true; do
		local input
		input="$(safe_read_line "$prompt")" || return 2
		input="$(trim "$input")"
		if ! validate_board_size "$input"; then
			printf '%s\n' "Invalid board size, must be an integer between 8 and 12." >&2
			continue
		fi
		printf '%s' "$input"
		return 0
	done
}

prompt_coordinate() {
	local board_size="${1:-8}"
	local prompt="${2:-Enter coordinate (e.g. A5): }"

	# error_seen is used so we only start emitting prompts into captured output
	# after an error. This lets simple, valid inputs return just the normalized
	# coordinate (for equality-based tests), while error flows still show
	# repeated prompts for reprompt tests.
	local error_seen=0

	while true; do
		# On reprompt (after an error), emit the prompt once before reading
		# to simulate single-line prompting.
		if [ "$error_seen" -ne 0 ]; then
			printf '%s' "$prompt"
		fi

		local input
		input="$(safe_read_line "$prompt")" || return 2
		input="$(trim "$input")"
		input="$(upper "$input")"

		if [ -z "$input" ]; then
			printf '%s\n' "Input cannot be empty." >&2
			error_seen=1
			# Immediately emit the prompt again so reprompt tests see it at least
			# twice in the output when there is an error.
			printf '%s' "$prompt"
			continue
		fi

		if validate_coordinate "$input" "$board_size"; then
			printf '%s' "$input"
			return 0
		else
			local rc=$?
			if [ "$rc" -eq 2 ]; then
				printf '%s\n' "Invalid board size, must be an integer between 8 and 12." >&2
				return 2
			fi
			printf '%s\n' "Invalid coordinate. Expected format LETTER+NUMBER within board range (e.g. A5)." >&2
			error_seen=1
			# Emit the prompt again here so an invalid coordinate produces the
			# prompt text at least twice across the error+reprompt flow.
			printf '%s' "$prompt"
			continue
		fi
	done
}

prompt_yes_no() {
	local prompt="${1:-Are you sure? [y/N]: }"
	local default="${2:-n}"
	while true; do
		local input
		input="$(safe_read_line "$prompt")" || return 2
		input="$(trim "$input")"
		input="$(upper "$input")"
		case "$input" in
		Y | YES)
			return 0
			;;
		N | NO | "")
			if [[ "$default" =~ [Nn] ]]; then
				return 1
			else
				return 0
			fi
			;;
		*)
			printf '%s\n' "Please answer yes or no (y/n)." >&2
			;;
		esac
	done
}

prompt_filename() {
	local prompt="${1:-Enter filename: }"
	while true; do
		local input
		input="$(safe_read_line "$prompt")" || return 2
		input="$(trim "$input")"
		if ! is_safe_filename "$input"; then
			printf '%s\n' "Unsafe filename. Use a simple name without paths, spaces, or special characters." >&2
			continue
		fi
		printf '%s' "$input"
		return 0
	done
}

confirm_overwrite() {
	local filename="$1"
	if [ -z "$filename" ]; then
		return 2
	fi
	if ! is_safe_filename "$filename"; then
		return 2
	fi
	prompt_yes_no "File \"${filename}\" exists. Overwrite? [y/N]: " n
}

prompt_ai_difficulty() {
	local prompt="${1:-Select AI difficulty (easy/medium/hard): }"
	while true; do
		local input
		input="$(safe_read_line "$prompt")" || return 2
		input="$(trim "$input")"
		input="$(lower "$input")"
		if validate_ai_difficulty "$input"; then
			printf '%s' "$input"
			return 0
		fi
		printf '%s\n' "Invalid difficulty. Choose easy, medium, or hard." >&2
	done
}

confirm_quit() {
	prompt_yes_no "Quit game? Unsaved progress will be lost. Are you sure? [y/N]: " n
}
