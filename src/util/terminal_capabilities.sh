#!/usr/bin/env bash
# Terminal capabilities detection for battleship_shell_script
# Intended to be sourced by other scripts; does not perform rendering.

set -u

# External overrides (set by caller if needed): BS_NO_COLOR, BS_HIGH_CONTRAST, BS_MONOCHROME
BS_TERM_PROBED=0
BS_TERM_COLORS=0
BS_TERM_HAS_COLOR=0
BS_TERM_IS_MONOCHROME=0
BS_TERM_HAS_BOLD=0
BS_TERM_HAS_STANDOUT=0
BS_TERM_CLEAR_SEQ=""
BS_TERM_RESET_SEQ=""
BS_TERM_NAME=""

bs__sanitize_term() {
	local t="${1-}"
	printf "%s" "${t}" | tr -cd '[:print:]'
}

bs__has_tput() {
	command -v tput >/dev/null 2>&1
}

bs__safe_tput() {
	if bs__has_tput && [ -n "${TERM-}" ]; then
		tput "$@" 2>/dev/null || true
	fi
}

bs_term_probe() {
	if [ "${BS_TERM_PROBED:-0}" -ne 0 ]; then
		return 0
	fi
	BS_TERM_PROBED=1
	BS_TERM_NAME="$(bs__sanitize_term "${TERM-}")"

	# Respect explicit disable/monochrome env flags
	if [ -n "${NO_COLOR-}" ] || [ -n "${BS_NO_COLOR-}" ] || [ -n "${BS_MONOCHROME-}" ]; then
		BS_TERM_HAS_COLOR=0
		BS_TERM_IS_MONOCHROME=1
	else
		# Prefer COLORTERM hint for truecolor
		case "${COLORTERM-}" in
		truecolor | 24bit)
			BS_TERM_COLORS=16777216
			;;
		*)
			BS_TERM_COLORS=0
			;;
		esac

		if [ -z "${BS_TERM_COLORS}" ] || [ "${BS_TERM_COLORS}" -eq 0 ]; then
			if bs__has_tput && [ -n "${BS_TERM_NAME}" ]; then
				local cols
				cols="$(bs__safe_tput colors || echo 0)"
				case "$cols" in
				'' | *[!0-9]*) cols=0 ;;
				esac
				BS_TERM_COLORS="$cols"
			fi
		fi

		if [ "${BS_TERM_COLORS:-0}" -ge 8 ]; then
			BS_TERM_HAS_COLOR=1
			BS_TERM_IS_MONOCHROME=0
		else
			BS_TERM_HAS_COLOR=0
			BS_TERM_IS_MONOCHROME=1
		fi
	fi

	# Bold and standout capabilities
	if [ "${BS_TERM_HAS_COLOR}" -eq 1 ] && bs__has_tput; then
		local b s
		b="$(bs__safe_tput bold || true)"
		s="$(bs__safe_tput smso || true)"
		if [ -n "$b" ]; then BS_TERM_HAS_BOLD=1; else BS_TERM_HAS_BOLD=0; fi
		if [ -n "$s" ]; then BS_TERM_HAS_STANDOUT=1; else BS_TERM_HAS_STANDOUT=0; fi
	else
		BS_TERM_HAS_BOLD=0
		BS_TERM_HAS_STANDOUT=0
	fi

	# Clear and reset sequences (conservative fallbacks)
	if bs__has_tput && [ -n "${BS_TERM_NAME}" ]; then
		BS_TERM_CLEAR_SEQ="$(bs__safe_tput clear || true)"
		BS_TERM_RESET_SEQ="$(bs__safe_tput sgr0 || true)"
	fi
	if [ -z "${BS_TERM_CLEAR_SEQ}" ]; then
		case "${BS_TERM_NAME}" in
		"" | dumb | unknown)
			BS_TERM_CLEAR_SEQ=""
			;;
		*)
			BS_TERM_CLEAR_SEQ="$(printf '\033[H\033[2J')"
			;;
		esac
	fi
	if [ -z "${BS_TERM_RESET_SEQ}" ]; then
		BS_TERM_RESET_SEQ="$(printf '\033[0m')"
	fi

	# Apply explicit monochrome/high-contrast overrides
	if [ -n "${BS_MONOCHROME-}" ]; then
		BS_TERM_HAS_COLOR=0
		BS_TERM_IS_MONOCHROME=1
		BS_TERM_HAS_BOLD=0
		BS_TERM_HAS_STANDOUT=0
		BS_TERM_CLEAR_SEQ=""
		BS_TERM_RESET_SEQ=""
	fi
	if [ -n "${BS_HIGH_CONTRAST-}" ]; then
		if [ "${BS_TERM_HAS_COLOR}" -eq 1 ]; then
			BS_TERM_HAS_BOLD=1
			BS_TERM_HAS_STANDOUT=1
		fi
	fi
}

bs_term_supports_color() {
	bs_term_probe
	if [ "${BS_TERM_HAS_COLOR:-0}" -eq 1 ]; then
		return 0
	fi
	return 1
}

bs_term_high_contrast_scheme() {
	bs_term_probe
	if [ -n "${BS_HIGH_CONTRAST-}" ]; then
		return 0
	fi
	return 1
}

bs_term_clear_screen() {
	bs_term_probe
	if [ -n "${BS_TERM_CLEAR_SEQ}" ]; then
		printf "%s" "${BS_TERM_CLEAR_SEQ}"
		return 0
	fi
	# Very conservative fallback for basic terminals and screen readers: no control sequences and no added newlines
	return 0
}

# Export a small, stable surface for callers
export BS_TERM_PROBED BS_TERM_COLORS BS_TERM_HAS_COLOR BS_TERM_IS_MONOCHROME BS_TERM_HAS_BOLD BS_TERM_HAS_STANDOUT BS_TERM_CLEAR_SEQ BS_TERM_RESET_SEQ BS_TERM_NAME
