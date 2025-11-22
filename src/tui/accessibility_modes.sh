#!/usr/bin/env bash
# Accessibility modes for battleship_shell_script
# Sourced by TUI renderer. Provides mode detection, runtime switching, and role->style mapping.

set -u

_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
if [ -f "${_script_dir}/../util/terminal_capabilities.sh" ]; then
	# We still source this for compatibility, but we do not depend on its functions
	. "${_script_dir}/../util/terminal_capabilities.sh"
else
	. "./src/util/terminal_capabilities.sh" || true
fi

BS_ACCESS_MODE="${BS_ACCESS_MODE-}"
BS_ACCESS_MODE_LOCK=0

# Internal helper: determine whether the environment supports color.
# This is intentionally self-contained and does NOT call bs_term_probe or bs_term_supports_color,
# so it is safe under `set -u` and independent of terminal_capabilities.sh internals.
bs_accessibility_term_supports_color() {
	# Explicit monochrome / no-color hints always force no color.
	if [ -n "${BS_MONOCHROME-}" ] || [ -n "${NO_COLOR-}" ] || [ -n "${BS_NO_COLOR-}" ]; then
		return 1
	fi

	# If an external probe has run and set BS_TERM_PROBED / BS_TERM_HAS_COLOR, honor that.
	if [ "${BS_TERM_PROBED-0}" -eq 1 ]; then
		if [ "${BS_TERM_HAS_COLOR-0}" -eq 1 ]; then
			return 0
		else
			return 1
		fi
	fi

	# Heuristic fallback based on TERM / COLORTERM when no explicit probe state is present.
	# TERM=dumb => no color
	case "${TERM-}" in
	dumb | '')
		# Treat dumb / empty as non-color by default
		return 1
		;;
	esac

	# If COLORTERM is set (e.g. truecolor), assume color support.
	if [ -n "${COLORTERM-}" ]; then
		return 0
	fi

	# Default: for non-dumb terminals, assume color support.
	return 0
}

bs_accessibility_probe() {
	# Only skip probing when an explicit mode has been set and the mode is locked;
	# otherwise re-evaluate capabilities so runtime changes and test-time environment
	# overrides are observed.
	if [ -n "${BS_ACCESS_MODE-}" ] && [ "${BS_ACCESS_MODE_LOCK:-0}" -ne 0 ]; then
		return 0
	fi

	local has_color=0
	if bs_accessibility_term_supports_color; then
		has_color=1
	fi

	# If the user explicitly exported BS_ACCESS_MODE before probing, honor it when
	# compatible with discovered capabilities; otherwise, normalize it.
	if [ -n "${BS_ACCESS_MODE-}" ]; then
		case "${BS_ACCESS_MODE}" in
		color)
			if [ "$has_color" -eq 1 ]; then
				return 0
			else
				BS_ACCESS_MODE="monochrome"
			fi
			;;
		high-contrast)
			if [ "$has_color" -eq 1 ]; then
				return 0
			else
				BS_ACCESS_MODE="monochrome"
			fi
			;;
		monochrome)
			return 0
			;;
		*)
			BS_ACCESS_MODE="monochrome"
			;;
		esac
	fi

	# Respect explicit disable/monochrome env hints
	if [ -n "${BS_MONOCHROME-}" ] || [ -n "${NO_COLOR-}" ] || [ -n "${BS_NO_COLOR-}" ]; then
		BS_ACCESS_MODE="monochrome"
		return 0
	fi

	# High contrast explicit request (only valid if color is available)
	if [ -n "${BS_HIGH_CONTRAST-}" ] && [ "$has_color" -eq 1 ]; then
		BS_ACCESS_MODE="high-contrast"
		return 0
	fi

	# Capability-based default
	if [ "$has_color" -eq 1 ]; then
		BS_ACCESS_MODE="color"
	else
		BS_ACCESS_MODE="monochrome"
	fi
}

bs_accessibility_current_mode() {
	bs_accessibility_probe
	printf "%s" "${BS_ACCESS_MODE}"
}

bs_accessibility_set_mode() {
	local mode="${1-}"

	# If mode is locked, deny changes
	if [ "${BS_ACCESS_MODE_LOCK:-0}" -ne 0 ]; then
		return 1
	fi

	# Respect global monochrome/NO_COLOR hints for manual toggles too:
	# when any of these are set, refuse to switch into a color-dependent mode.
	if [ "${mode}" != "monochrome" ] &&
		{ [ -n "${BS_MONOCHROME-}" ] || [ -n "${NO_COLOR-}" ] || [ -n "${BS_NO_COLOR-}" ]; }; then
		return 1
	fi

	case "$mode" in
	color)
		BS_ACCESS_MODE="color"
		return 0
		;;
	high-contrast)
		BS_ACCESS_MODE="high-contrast"
		return 0
		;;
	monochrome)
		BS_ACCESS_MODE="monochrome"
		return 0
		;;
	*)
		return 2
		;;
	esac
}

bs_accessibility_toggle_lock() {
	BS_ACCESS_MODE_LOCK=$((1 - ${BS_ACCESS_MODE_LOCK:-0}))
}

# Return a style sequence and symbol for a semantic role. Roles: hit miss ship water status
bs_accessibility_style_for() {
	local role="${1-}"
	bs_accessibility_probe
	local reset="${BS_TERM_RESET_SEQ:-}"
	local prefix=""
	local sym=""

	case "${BS_ACCESS_MODE:-monochrome}" in
	color)
		case "$role" in
		hit) prefix="\033[31m" sym="X" ;;
		miss) prefix="\033[36m" sym="o" ;;
		ship) prefix="\033[33m" sym="S" ;;
		water) prefix="\033[34m" sym="~" ;;
		status) prefix="\033[1m\033[37m" sym="" ;;
		*) prefix="" sym="" ;;
		esac
		;;
	high-contrast)
		case "$role" in
		hit) prefix="\033[1m\033[41m\033[97m" sym="✖" ;;
		miss) prefix="\033[1m\033[46m\033[30m" sym="•" ;;
		ship) prefix="\033[1m\033[43m\033[30m" sym="█" ;;
		water) prefix="\033[1m\033[44m\033[97m" sym="·" ;;
		status) prefix="\033[1m" sym="" ;;
		*) prefix="" sym="" ;;
		esac
		;;
	monochrome | *)
		case "$role" in
		hit) prefix="" sym="X" ;;
		miss) prefix="" sym="o" ;;
		ship) prefix="" sym="S" ;;
		water) prefix="" sym="~" ;;
		status) prefix="" sym="*" ;;
		*) prefix="" sym="" ;;
		esac
		reset=""
		;;
	esac

	printf "%s%s%s" "$prefix" "$sym" "$reset"
}

# Emit simple key=value pairs for renderer consumption
bs_accessibility_map_all() {
	bs_accessibility_probe
	printf "hit=%s\n" "$(bs_accessibility_style_for hit)"
	printf "miss=%s\n" "$(bs_accessibility_style_for miss)"
	printf "ship=%s\n" "$(bs_accessibility_style_for ship)"
	printf "water=%s\n" "$(bs_accessibility_style_for water)"
	printf "status=%s\n" "$(bs_accessibility_style_for status)"
}

# Interactive prompt for live switching; returns 0 on mode set, 1 on quit
bs_accessibility_interactive_prompt() {
	bs_accessibility_probe
	printf "\nAccessibility modes: (c)olor (h)igh-contrast (m)onochrome (q)uit\n"
	while true; do
		printf "Select mode: " >&2
		IFS= read -rn1 key
		printf "\n" >&2
		case "${key}" in
		c | C)
			bs_accessibility_set_mode color && return 0
			;;
		h | H)
			bs_accessibility_set_mode high-contrast && return 0
			;;
		m | M)
			bs_accessibility_set_mode monochrome && return 0
			;;
		q | Q | "")
			return 1
			;;
		*)
			printf "Ignored\n" >&2
			;;
		esac
	done
}

export -f \
	bs_accessibility_probe \
	bs_accessibility_current_mode \
	bs_accessibility_set_mode \
	bs_accessibility_style_for \
	bs_accessibility_map_all \
	bs_accessibility_interactive_prompt \
	bs_accessibility_toggle_lock
