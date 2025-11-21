#!/usr/bin/env bash
set -euo pipefail
SOURCED=0
if [ "${BASH_SOURCE[0]}" != "$0" ]; then SOURCED=1; fi
NEW=0
LOAD_FILE=""
SIZE=""
AI=""
SEED=""
NO_COLOR=0
HIGH_CONTRAST=0
MONOCHROME=0
STATE_DIR="${PATHS_DEFAULT_STATE_DIR:-${BATTLESHIP_STATE_DIR:-${HOME}/.battleship_state}}"
SAVE_FILE=""
VERSION=0
HELP=0
DOCTOR=0
SELF_CHECK=0
normalize_path() {
	local p="$1"
	if [ -z "$p" ]; then
		printf '%s' ""
		return 0
	fi
	if [[ "$p" == ~* ]]; then p="${HOME}${p:1}"; fi
	local abs=0
	if [[ "$p" == /* ]]; then abs=1; fi
	IFS='/' read -ra parts <<<"$p"
	local -a out=()
	local part
	for part in "${parts[@]}"; do
		if [ -z "$part" ] || [ "$part" == "." ]; then
			continue
		fi
		if [ "$part" == ".." ]; then
			if [ "${#out[@]}" -gt 0 ]; then
				unset 'out[${#out[@]}-1]'
			else
				if [ "$abs" -eq 0 ]; then out+=(..); fi
			fi
		else
			out+=("$part")
		fi
	done
	local joined
	if [ "${#out[@]}" -eq 0 ]; then
		if [ "$abs" -eq 1 ]; then joined="/"; else joined="."; fi
	else
		joined="$(printf '/%s' "${out[@]}")"
		if [ "$abs" -eq 0 ]; then joined="${joined:1}"; fi
	fi
	printf '%s' "$joined"
}
is_integer() {
	case "$1" in
	'' | *[!0-9-]*) return 1 ;;
	*) return 0 ;;
	esac
}
emit_error() {
	local msg="$1"
	local code="${2:-1}"
	if [ "$SELF_CHECK" -eq 1 ]; then
		printf 'ERROR=%s\n' "$msg" >&2
	else
		printf '%s\n' "$msg" >&2
	fi
	if [ "$SOURCED" -eq 1 ]; then
		return "$code"
	else
		exit "$code"
	fi
}
parse_arg_value() {
	if [ "${2:-}" == "" ]; then emit_error "Missing value for $1" 2; fi
}
while [ "${#}" -gt 0 ]; do
	case "$1" in
	--new)
		NEW=1
		shift
		;;
	--load)
		parse_arg_value --load "${2:-}"
		LOAD_FILE="$(normalize_path "$2")"
		shift 2
		;;
	--size)
		parse_arg_value --size "${2:-}"
		if ! is_integer "$2"; then emit_error "Invalid size: $2" 2; fi
		SIZE="$2"
		shift 2
		;;
	--ai)
		parse_arg_value --ai "${2:-}"
		case "$2" in
		easy | medium | hard) AI="$2" ;;
		*) emit_error "Invalid ai level: $2" 2 ;;
		esac
		shift 2
		;;
	--seed)
		parse_arg_value --seed "${2:-}"
		if ! is_integer "$2"; then emit_error "Invalid seed: $2" 2; fi
		SEED="$2"
		shift 2
		;;
	--no-color)
		NO_COLOR=1
		shift
		;;
	--high-contrast)
		HIGH_CONTRAST=1
		shift
		;;
	--monochrome)
		MONOCHROME=1
		shift
		;;
	--state-dir)
		parse_arg_value --state-dir "${2:-}"
		STATE_DIR="$(normalize_path "$2")"
		shift 2
		;;
	--save)
		parse_arg_value --save "${2:-}"
		SAVE_FILE="$(normalize_path "$2")"
		shift 2
		;;
	--version)
		VERSION=1
		ACTION="version"
		shift
		;;
	--help)
		HELP=1
		ACTION="help"
		shift
		;;
	--doctor)
		DOCTOR=1
		ACTION="doctor"
		shift
		;;
	--self-check)
		SELF_CHECK=1
		shift
		;;
	--)
		shift
		break
		;;
	*)
		emit_error "Unknown argument: $1" 2
		;;
	esac
done
if [ "$NEW" -eq 1 ] && [ -n "$LOAD_FILE" ]; then emit_error "Conflicting options: --new and --load" 2; fi
if [ -n "$SIZE" ]; then
	if ! is_integer "$SIZE"; then emit_error "Size must be integer" 2; fi
	if [ "$SIZE" -lt 8 ] || [ "$SIZE" -gt 12 ]; then emit_error "Size must be between 8 and 12" 2; fi
fi
if [ -n "$SEED" ]; then
	if ! is_integer "$SEED"; then emit_error "Seed must be integer" 2; fi
fi
if [ "$NO_COLOR" -eq 1 ] && { [ "$HIGH_CONTRAST" -eq 1 ] || [ "$MONOCHROME" -eq 1 ]; }; then
	emit_error "Conflicting color flags" 2
fi
if [ "$HIGH_CONTRAST" -eq 1 ] && [ "$MONOCHROME" -eq 1 ]; then
	emit_error "Conflicting color flags: --high-contrast and --monochrome" 2
fi
if [ -z "${ACTION:-}" ]; then
	if [ "$VERSION" -eq 1 ]; then ACTION="version"; fi
	if [ "$HELP" -eq 1 ]; then ACTION="help"; fi
fi
# Normalize the state dir default so callers always receive a canonical path
STATE_DIR="$(normalize_path "$STATE_DIR")"
# Derive a single canonical color mode for callers/tests
COLOR_MODE="auto"
if [ "$NO_COLOR" -eq 1 ]; then
	COLOR_MODE="none"
elif [ "$HIGH_CONTRAST" -eq 1 ]; then
	COLOR_MODE="high-contrast"
elif [ "$MONOCHROME" -eq 1 ]; then
	COLOR_MODE="monochrome"
fi
output_config() {
	if [ "$SOURCED" -eq 1 ]; then
		export BATTLESHIP_NEW="$NEW"
		export BATTLESHIP_LOAD_FILE="$LOAD_FILE"
		export BATTLESHIP_SIZE="$SIZE"
		export BATTLESHIP_AI="$AI"
		export BATTLESHIP_SEED="$SEED"
		export BATTLESHIP_NO_COLOR="$NO_COLOR"
		export BATTLESHIP_HIGH_CONTRAST="$HIGH_CONTRAST"
		export BATTLESHIP_MONOCHROME="$MONOCHROME"
		export BATTLESHIP_STATE_DIR="$STATE_DIR"
		export BATTLESHIP_SAVE_FILE="$SAVE_FILE"
		export BATTLESHIP_VERSION="$VERSION"
		export BATTLESHIP_HELP="$HELP"
		export BATTLESHIP_DOCTOR="$DOCTOR"
		export BATTLESHIP_SELF_CHECK="$SELF_CHECK"
		export BATTLESHIP_ACTION="${ACTION:-}"
		export BATTLESHIP_COLOR_MODE="$COLOR_MODE"
	else
		printf 'new=%s\n' "$NEW"
		printf 'load_file=%s\n' "$LOAD_FILE"
		printf 'size=%s\n' "$SIZE"
		printf 'ai=%s\n' "$AI"
		printf 'seed=%s\n' "$SEED"
		printf 'no_color=%s\n' "$NO_COLOR"
		printf 'high_contrast=%s\n' "$HIGH_CONTRAST"
		printf 'monochrome=%s\n' "$MONOCHROME"
		printf 'state_dir=%s\n' "$STATE_DIR"
		printf 'save_file=%s\n' "$SAVE_FILE"
		printf 'version=%s\n' "$VERSION"
		printf 'help=%s\n' "$HELP"
		printf 'doctor=%s\n' "$DOCTOR"
		printf 'self_check=%s\n' "$SELF_CHECK"
		printf 'action=%s\n' "${ACTION:-}"
		printf 'color_mode=%s\n' "$COLOR_MODE"
	fi
}
output_config
if [ "$SOURCED" -eq 1 ]; then
	return 0
fi
exit 0
