#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# tui_renderer.sh - library for rendering Battleship boards to a terminal
# Purpose: Provide functions to draw a dual-grid ASCII view, a legend, and a status line.
# Usage: This file is a library; it MUST NOT perform work on source. Callers must source it
# and then call exported functions. Callers must supply board-query functions used below.
# Public functions:
#  - tui_render_dual_grid <rows> <cols> <player_state_fn> <player_owner_fn> <ai_state_fn> <ai_owner_fn> <status>
#  - tui_render_legend
#  - tui_render_status_line <text>
#  - tui_renderer_help
# Notes:
#  - This library does not auto-source terminal_capabilities.sh or accessibility_modes.sh; if
#    those helpers are available in the caller environment, this renderer will use them.
#  - Board query functions must be callable in the current shell and accept two args (row col)
#    using 0-based indices and print a single token: state (unknown|water|ship|hit|miss) or owner.
#  - This library is idempotent and performs no persistent side effects.

# Local helper: check whether a function name is defined in this shell.
tui__require_function() {
	local fn="${1:-}"
	if [ -z "${fn}" ]; then
		return 1
	fi
	if ! command -v "${fn}" >/dev/null 2>&1; then
		return 1
	fi
	return 0
}

# Get an accessibility style string for a semantic role if helper exists.
# Returns empty string on failure.
tui__get_style() {
	local role="${1:-}"
	local out=""
	if command -v bs_accessibility_style_for >/dev/null 2>&1; then
		# Capture but tolerate failures; the accessibility helper is optional.
		out="$(bs_accessibility_style_for "${role}" 2>/dev/null || true)"
	fi
	printf "%s" "${out}"
}

# Map core states to plain ASCII symbols (guaranteed non-color cue).
tui__symbol_for_state() {
	local state="${1:-}"
	case "${state}" in
	ship) printf "#" ;;
	hit) printf "X" ;;
	miss) printf "O" ;;
	unknown | water) printf "~" ;;
	*) printf "?" ;;
	esac
}

# Render a single cell combining accessibility style (if present) with a plain fallback.
# This guarantees meaning even when color/attributes are unavailable.
# Output is a single printing token (no newline).
tui__render_cell() {
	local state="${1:-}" owner="${2:-}"
	local role="water"
	if [ "${state}" = "ship" ]; then role="ship"; fi
	if [ "${state}" = "hit" ]; then role="hit"; fi
	if [ "${state}" = "miss" ]; then role="miss"; fi

	local style
	style="$(tui__get_style "${role}" || true)"
	local sym_plain
	sym_plain="$(tui__symbol_for_state "${state}" "${owner}")"

	if [ -n "${style}" ]; then
		# Accessibility helper typically returns prefix+symbol+reset; use it directly to preserve intent.
		printf "%s" "${style}"
	else
		printf "%s" "${sym_plain}"
	fi
}

# Convert 0-based column index to A,B,...,Z,AA,AB,...; returns 1 on error.
tui__col_label() {
	local idx="${1:-}"
	if ! [[ "${idx}" =~ ^[0-9]+$ ]]; then
		return 1
	fi
	local num=$((idx))
	if ((num >= 0 && num < 26)); then
		printf "%c" "$((65 + num))"
		return 0
	fi
	# For indices >= 26, compute base-26 letters (A..Z, AA...)
	local n=$((num))
	local s=""
	while true; do
		local rem=$((n % 26))
		s="$(printf "%c" $((65 + rem)))${s}"
		n=$((n / 26 - 1))
		if ((n < 0)); then break; fi
	done
	printf "%s" "${s}"
}

# Print a concise legend. Always includes plain symbols so screen readers / monochrome users have clear cues.
tui_render_legend() {
	local hit_style miss_style ship_style water_style
	hit_style="$(tui__get_style hit || true)"
	miss_style="$(tui__get_style miss || true)"
	ship_style="$(tui__get_style ship || true)"
	water_style="$(tui__get_style water || true)"
	# Plain fallback tokens included; caller may pipe or capture stdout for display.
	printf "Legend: %s Hit (X)  %s Miss (O)  %s Ship (#)  %s Water (~)\n" "${hit_style:-X}" "${miss_style:-O}" "${ship_style:-#}" "${water_style:-~}"
}

# Render a single-line status. Uses accessibility status style if provided.
tui_render_status_line() {
	local status="${1:-}"
	local status_style
	status_style="$(tui__get_style status || true)"
	if [ -n "${status_style}" ]; then
		printf "%s %s\n" "${status_style}" "${status}"
	else
		printf "%s\n" "${status}"
	fi
}

# Render two side-by-side grids (player | AI).
# Parameters: rows cols player_state_fn player_owner_fn ai_state_fn ai_owner_fn status
# All indices passed to board functions are 0-based.
# Returns: 0 on success, non-zero for usage/validation failures.
tui_render_dual_grid() {
	if [ "$#" -ne 7 ]; then
		printf "Usage: tui_render_dual_grid <rows> <cols> <player_state_fn> <player_owner_fn> <ai_state_fn> <ai_owner_fn> <status>\n" >&2
		return 2
	fi
	local rows="${1:-}" cols="${2:-}"
	local p_state_fn="${3:-}" p_owner_fn="${4:-}" a_state_fn="${5:-}" a_owner_fn="${6:-}" status="${7:-}"

	if ! [[ "${rows}" =~ ^[0-9]+$ ]] || ! [[ "${cols}" =~ ^[0-9]+$ ]]; then
		printf "rows and cols must be non-negative integers\n" >&2
		return 3
	fi

	# Validate provided query functions exist in caller environment.
	for fn in "${p_state_fn}" "${p_owner_fn}" "${a_state_fn}" "${a_owner_fn}"; do
		if ! tui__require_function "${fn}"; then
			printf "Required function not found: %s\n" "${fn}" >&2
			return 4
		fi
	done

	# Prefer a conservative clear if helper exists.
	if command -v bs_term_clear_screen >/dev/null 2>&1; then
		bs_term_clear_screen || true
	fi

	local header_left header_right sep
	header_left="  "
	for ((c = 0; c < cols; c++)); do
		header_left="${header_left} $(tui__col_label "${c}" 2>/dev/null)"
	done
	sep="    "
	header_right="  "
	for ((c = 0; c < cols; c++)); do
		header_right="${header_right} $(tui__col_label "${c}" 2>/dev/null)"
	done

	printf "%s%s%s\n" "${header_left}" "${sep}" "${header_right}"

	local r c pl_row ar_row
	for ((r = 0; r < rows; r++)); do
		pl_row="$(printf "%2d " $((r + 1)))"
		for ((c = 0; c < cols; c++)); do
			local state owner cell
			state="$("${p_state_fn}" "${r}" "${c}" 2>/dev/null || printf "unknown")"
			owner="$("${p_owner_fn}" "${r}" "${c}" 2>/dev/null || printf "")"
			cell="$(tui__render_cell "${state}" "${owner}")"
			pl_row="${pl_row} ${cell}"
		done

		ar_row="$(printf "%2d " $((r + 1)))"
		for ((c = 0; c < cols; c++)); do
			local state owner cell
			state="$("${a_state_fn}" "${r}" "${c}" 2>/dev/null || printf "unknown")"
			owner="$("${a_owner_fn}" "${r}" "${c}" 2>/dev/null || printf "")"
			cell="$(tui__render_cell "${state}" "${owner}")"
			ar_row="${ar_row} ${cell}"
		done

		printf "%s%s%s\n" "${pl_row}" "${sep}" "${ar_row}"
	done

	tui_render_legend
	tui_render_status_line "${status}"
	return 0
}

# Minimal help for integrators.
tui_renderer_help() {
	printf "Functions exported: tui_render_dual_grid rows cols p_state_fn p_owner_fn a_state_fn a_owner_fn status; tui_render_legend; tui_render_status_line; tui_renderer_help\n"
}

export -f tui_render_dual_grid tui_render_legend tui_render_status_line tui_renderer_help
