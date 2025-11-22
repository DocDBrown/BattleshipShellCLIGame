#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/../util/validation.sh" ]; then
	# shellcheck disable=SC1091
	source "${SCRIPT_DIR}/../util/validation.sh"
else
	echo "error: validation.sh not found" >&2
	exit 1
fi

trim() {
	local s="$1"
	s="${s#"${s%%[![:space:]]*}"}"
	s="${s%"${s##*[![:space:]]}"}"
	printf '%s' "$s"
}

uppercase() {
	if [ -z "${1-}" ]; then
		printf ''
		return 0
	fi
	printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

read_prompt() {
	local prompt="$1"
	local input
	printf "%s " "$prompt"
	if ! read -r input; then
		return 1
	fi
	printf '%s' "$input"
}

tui_prompt_coordinate() {
	local size="${2:-10}"
	if ! _validate_board_size "$size" >/dev/null 2>&1; then
		return 2
	fi
	local max_ord=$((65 + size - 1))
	local max_letter
	max_letter=$(printf '%c' "$max_ord")
	local prompt="${1:-Enter coordinate (e.g. A1)}"
	local input
	while true; do
		input="$(read_prompt "${prompt} [A-${max_letter}, 1-${size}]:")" || return 1
		input="$(trim "$input")"
		input="$(uppercase "$input")"
		if validate_coordinate "$input" "$size"; then
			printf '%s\n' "$input"
			return 0
		else
			printf 'Invalid coordinate. Use a letter A-%s and a number 1-%s (example: A1). Try again.\n' "$max_letter" "$size"
		fi
	done
}

tui_prompt_yes_no() {
	local message="${1:-Confirm?}"
	local default="${2:-}"
	local prompt
	case "$default" in
	y | Y | yes | Yes) prompt="[Y/n]" ;;
	n | N | no | No) prompt="[y/N]" ;;
	*) prompt="[y/n]" ;;
	esac
	local input
	while true; do
		input="$(read_prompt "${message} ${prompt}")" || return 1
		input="$(trim "$input")"
		input="$(uppercase "$input")"
		if [ -z "$input" ]; then
			case "$default" in
			y | Y | yes | Yes) return 0 ;;
			n | N | no | No) return 1 ;;
			*) printf 'Please answer y or n.\n' ;;
			esac
		fi
		case "$input" in
		Y | YES) return 0 ;;
		N | NO) return 1 ;;
		*) printf 'Please answer y or n.\n' ;;
		esac
	done
}

tui_prompt_ai_difficulty() {
	local prompt="${1:-Choose AI difficulty (easy|medium|hard)}"
	local input
	while true; do
		input="$(read_prompt "${prompt}:")" || return 1
		input="$(trim "$input")"
		input="$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')"
		if validate_ai_difficulty "$input"; then
			printf '%s\n' "$input"
			return 0
		else
			printf 'Invalid difficulty. Acceptable: easy, medium, hard.\n'
		fi
	done
}

tui_prompt_orientation() {
	local prompt="${1:-Choose orientation (H/V)}"
	local input
	while true; do
		input="$(read_prompt "${prompt} [H/V]:")" || return 1
		input="$(trim "$input")"
		input="$(uppercase "$input")"
		case "$input" in
		H | V)
			printf '%s\n' "$input"
			return 0
			;;
		HORIZONTAL)
			printf 'H\n'
			return 0
			;;
		VERTICAL)
			printf 'V\n'
			return 0
			;;
		*) printf 'Invalid choice. Enter H or V.\n' ;;
		esac
	done
}

tui_prompt_filename_for_save() {
	local default="${1:-savegame}"
	local prompt="${2:-Enter save filename}"
	local input
	while true; do
		input="$(read_prompt "${prompt} [default: ${default}]:")" || return 1
		input="$(trim "$input")"
		if [ -z "$input" ]; then input="$default"; fi
		if ! is_safe_filename "$input"; then
			printf 'Unsafe filename. Use alphanumeric, hyphen or underscore; no path separators, leading dashes, spaces, or .. sequences.\n'
			continue
		fi
		if [ -e "${input}" ]; then
			if tui_prompt_yes_no "File \"${input}\" exists. Overwrite?" "n"; then
				printf '%s\n' "$input"
				return 0
			else
				printf 'Choose a different filename.\n'
				continue
			fi
		fi
		printf '%s\n' "$input"
		return 0
	done
}

export -f trim uppercase read_prompt tui_prompt_coordinate tui_prompt_yes_no tui_prompt_ai_difficulty tui_prompt_orientation tui_prompt_filename_for_save
