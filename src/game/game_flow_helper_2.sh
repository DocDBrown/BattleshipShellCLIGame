#!/usr/bin/env bash
# Helper 2: game lifecycle (start/load) and the interactive/non-interactive run loop
set -euo pipefail
IFS=$'\n\t'
LC_ALL=C

# Exit/persistence control variables (test-friendly hooks)
GAME_FLOW__AUTOSAVE_FLAG=0
GAME_FLOW__EXIT_SAVE_SCRIPT=""

# Internal: on-exit handler invoked by trap. Attempts to persist state when configured.
# This is defensive: it never aborts the exit, and tolerates missing helpers.
game_flow__on_exit() {
	# Prevent recursion if invoked multiple times
	trap - INT TERM EXIT

	# If an explicit save script path was provided, attempt to invoke it
	if [[ "${GAME_FLOW__AUTOSAVE_FLAG:-0}" -ne 0 && -n "${GAME_FLOW__EXIT_SAVE_SCRIPT:-}" ]]; then
		if [[ -x "${GAME_FLOW__EXIT_SAVE_SCRIPT}" ]]; then
			# Best-effort: call save helper with an --out argument pointing to a file
			local outpath
			outpath="${GAME_FLOW__EXIT_SAVE_SCRIPT}.out"
			# Invoke but ignore failures; we must not prevent shutdown
			"${GAME_FLOW__EXIT_SAVE_SCRIPT}" --out "${outpath}" >/dev/null 2>&1 || true
		fi
	fi

	# Always print a minimal summary if available (best-effort)
	if command -v game_flow__print_summary_and_exit >/dev/null 2>&1; then
		game_flow__print_summary_and_exit || true
	fi
}

# Start new game with automatic placement
# Usage: game_flow_start_new <size> <autosave_flag> [exit_save_script]
game_flow_start_new() {
	local size="$1" autosave_flag="$2" save_script="${3:-}"

	if [[ -z "$size" || ! "$size" =~ ^[0-9]+$ ]]; then
		printf "Invalid board size: %s\n" "$size" >&2
		return 3
	fi

	if ! command -v bs_board_new >/dev/null 2>&1; then
		printf "Required board_state helper missing\n" >&2
		return 2
	fi

	bs_board_new "$size" || {
		printf "Failed to initialize board of size %s\n" "$size" >&2
		return 4
	}

	if command -v bs_auto_place_fleet >/dev/null 2>&1; then
		if ! bs_auto_place_fleet --verbose 200 >/dev/null 2>&1; then
			game_flow__log_warn "auto_place_failed" "{}"
			printf "Auto placement failed\n" >&2
			return 5
		fi
	else
		printf "Auto-placement unavailable; manual placement not supported by this coordinator\n" >&2
		return 6
	fi

	if command -v stats_init >/dev/null 2>&1; then
		stats_init || true
		stats_start || true
	fi

	if command -v te_init >/dev/null 2>&1; then
		te_init "$size" || true
	fi

	if command -v te_set_on_shot_result_callback >/dev/null 2>&1; then
		te_set_on_shot_result_callback game_flow__on_shot_result || true
	fi

	# Configure exit/persistence hooks for this run
	GAME_FLOW__AUTOSAVE_FLAG=0
	if [[ "${autosave_flag}" =~ ^[0-9]+$ ]] && [[ "${autosave_flag}" -ne 0 ]]; then
		GAME_FLOW__AUTOSAVE_FLAG=1
	fi
	GAME_FLOW__EXIT_SAVE_SCRIPT="${save_script:-}"

	# Install trap that will attempt to persist state on INT/TERM/EXIT
	trap 'game_flow__on_exit' INT TERM EXIT

	game_flow__run_loop "$autosave_flag"
}

# Load existing save file
# Usage: game_flow_load_save <save_file> [exit_save_script]
game_flow_load_save() {
	local save_file="$1" save_script="${2:-}"
	if [[ -z "$save_file" ]]; then
		printf "Missing save file path\n" >&2
		return 1
	fi
	if ! command -v bs_load_state_load_file >/dev/null 2>&1; then
		printf "Loading helper not available\n" >&2
		return 2
	fi
	if ! bs_load_state_load_file "$save_file"; then
		printf "Failed to load save: %s\n" "$save_file" >&2
		return 3
	fi
	if command -v te_set_on_shot_result_callback >/dev/null 2>&1; then
		te_set_on_shot_result_callback game_flow__on_shot_result || true
	fi

	# Configure exit/persistence hooks for loaded game
	GAME_FLOW__AUTOSAVE_FLAG=0
	GAME_FLOW__EXIT_SAVE_SCRIPT="${save_script:-}"
	trap 'game_flow__on_exit' INT TERM EXIT

	game_flow__run_loop 0
}

# Main interactive/non-interactive turn loop
game_flow__run_loop() {
	local autosave_flag="$1"
	local board_size="${BS_BOARD_SIZE:-10}"

	if ! command -v tui_render_dual_grid >/dev/null 2>&1 || ! command -v prompt_coordinate >/dev/null 2>&1; then
		printf "TUI helpers not available; cannot run interactive loop\n" >&2
		return 2
	fi

	local interactive=1
	if [ ! -t 0 ]; then
		interactive=0
	fi

	while true; do
		tui_render_dual_grid "$board_size" "$board_size" bs_board_get_state bs_board_get_owner bs_board_get_state bs_board_get_owner "Your turn"

		if command -v bs_board_is_win >/dev/null 2>&1; then
			if [[ "$(bs_board_is_win)" == "true" ]]; then
				game_flow__log_info "game_end" "{}"
				printf "All ship segments destroyed. You win!\n"
				game_flow__print_summary_and_exit
				return 0
			fi
		fi

		local coord=""
		if [[ "$interactive" -eq 1 ]]; then
			coord="$(prompt_coordinate "$board_size" "Enter coordinate (e.g. A5): ")" || {
				printf "Input closed or invalid\n" >&2
				return 2
			}
		else
			local found=0 r c st
			for ((r = 0; r < board_size && found == 0; r++)); do
				for ((c = 0; c < board_size && found == 0; c++)); do
					st="$(bs_board_get_state "$r" "$c" 2>/dev/null || printf 'unknown')"
					if [[ "$st" == "unknown" || "$st" == "water" ]]; then
						coord="$(game_flow__coord_from_rc "$r" "$c")"
						found=1
					fi
				done
			done
			if [[ $found -eq 0 ]]; then
				printf "No available unknown cells. Exiting.\n"
				game_flow__print_summary_and_exit
				return 0
			fi
		fi

		if command -v te_human_shoot >/dev/null 2>&1; then
			if ! te_human_shoot "$coord"; then
				game_flow__log_warn "shot_failed" "{\"coord\":\"$coord\"}"
			fi
		else
			printf "turn_engine missing; cannot process shot\n" >&2
			return 2
		fi

		if [[ "$autosave_flag" -ne 0 ]]; then
			if command -v bs_path_saves_dir >/dev/null 2>&1 && [[ -f "${REPO_ROOT:-.}/persistence/save_state.sh" ]]; then
				local outdir
				outdir="$(bs_path_saves_dir 2>/dev/null || true)"
				if [[ -n "$outdir" ]]; then
					local tmpfile
					tmpfile="$(mktemp -p "$outdir" .autosave.XXXXXX)" || true
					chmod 0600 "$tmpfile" 2>/dev/null || true
					if ! "${REPO_ROOT:-.}/persistence/save_state.sh" --out "$tmpfile" >/dev/null 2>&1; then
						rm -f -- "$tmpfile" 2>/dev/null || true
						game_flow__log_warn "autosave_failed" "{}"
					else
						game_flow__log_info "autosave_ok" "{\"path\":\"$tmpfile\"}"
					fi
				fi
			fi
		fi
	done
}

### Minimal helper implementations to make coordinator test-friendly ###

# Convert zero-based row/col to standard coordinate (A1 style)
# Usage: game_flow__coord_from_rc <row_zero_based> <col_zero_based>
game_flow__coord_from_rc() {
	local r="${1-}" c="${2-}"
	if [[ -z "$r" || -z "$c" ]]; then
		return 1
	fi
	if [[ ! "$r" =~ ^[0-9]+$ ]] || [[ ! "$c" =~ ^[0-9]+$ ]]; then
		return 1
	fi
	local letter
	letter=$(printf "%c" $((65 + r))) || return 1
	printf "%s%d" "$letter" $((c + 1))
	return 0
}

# Default on-shot-result callback placeholder (safe no-op)
game_flow__on_shot_result() {
	# Arguments: shooter coord result owner ship_name shots hits misses [remaining]
	# Tests or higher-level coordinators can override this by defining their own function
	return 0
}

# Print game summary and return (do not exit process) to keep test harness stable
game_flow__print_summary_and_exit() {
	if command -v stats_summary_text >/dev/null 2>&1; then
		stats_summary_text || true
	fi
	return 0
}

# Logging helpers that try to use the project's logger when available
game_flow__log_info() {
	local k="$1" p="${2:-}"
	if command -v bs_log_info >/dev/null 2>&1; then
		bs_log_info "$k" "$p" || true
	else
		printf "INFO: %s %s\n" "$k" "$p" >/dev/null 2>&1 || true
	fi
}

game_flow__log_warn() {
	local k="$1" p="${2:-}"
	if command -v bs_log_warn >/dev/null 2>&1; then
		bs_log_warn "$k" "$p" || true
	else
		printf "WARN: %s %s\n" "$k" "$p" >/dev/null 2>&1 || true
	fi
}

