#!/usr/bin/env bash
# Helper 1: utilities, safe source, logging, callbacks, and small helpers
set -euo pipefail
IFS=$'\n\t'
LC_ALL=C

# Safe source helper: does not exit parent shell if missing
game_flow__safe_source() {
	local f="$1"
	if [[ -f "$f" ]]; then
		# shellcheck disable=SC1090,SC1091
		. "$f"
		return 0
	fi
	return 1
}

# Require helper: return non-zero when missing
game_flow__require() {
	local f="$1"
	if ! game_flow__safe_source "$f"; then
		printf "Required helper not found: %s\n" "$f" >&2
		return 2
	fi
	return 0
}

# Small logger wrappers that prefer project logger but degrade to stderr
game_flow__log_info() {
	local msg_template="$1" params="${2:-{}}"
	if command -v bs_log_info >/dev/null 2>&1; then
		bs_log_info "$msg_template" "$params" || true
	else
		printf "INFO: %s %s\n" "$msg_template" "$params" >&2
	fi
}

game_flow__log_warn() {
	local msg="$1" params="${2:-{}}"
	if command -v bs_log_warn >/dev/null 2>&1; then
		bs_log_warn "$msg" "$params" || true
	else
		printf "WARN: %s %s\n" "$msg" "$params" >&2
	fi
}

game_flow__log_error() {
	local msg="$1" params="${2:-{}}"
	if command -v bs_log_error >/dev/null 2>&1; then
		bs_log_error "$msg" "$params" || true
	else
		printf "ERROR: %s %s\n" "$msg" "$params" >&2
	fi
}

# Load commonly used modules (best-effort)
game_flow__load_common_helpers() {
	local root_dir
	root_dir="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)}"
	game_flow__safe_source "$root_dir/model/ship_rules.sh" || true
	game_flow__safe_source "$root_dir/model/board_state.sh" || true
	# Ensure manual placement is available so tests can see main() and manual_called
	game_flow__safe_source "$root_dir/placement/manual_placement.sh" || true
	game_flow__safe_source "$root_dir/placement/auto_placement.sh" || true
	game_flow__safe_source "$root_dir/tui/tui_renderer.sh" || true
	game_flow__safe_source "$root_dir/tui/tui_prompts.sh" || true
	game_flow__safe_source "$root_dir/game/turn_engine.sh" || true
	game_flow__safe_source "$root_dir/game/stats.sh" || true
	game_flow__safe_source "$root_dir/persistence/save_state.sh" || true
	game_flow__safe_source "$root_dir/persistence/load_state.sh" || true
	game_flow__safe_source "$root_dir/logging/logger.sh" || true
}

# Normalize shooter id for stats token
game_flow__normalize_shooter() {
	case "${1:-}" in
	human | player) printf "player" ;;
	ai) printf "ai" ;;
	*) printf "%s" "${1:-}" ;;
	esac
}

# Callback invoked by turn_engine on every shot result
# Signature: <shooter> <coord> <result> <owner> <ship_name> <shots> <hits> <misses> [remaining]
game_flow__on_shot_result() {
	local shooter="$1" coord="$2" result="$3" owner="$4" ship_name="$5" shots="$6" hits="$7" misses="$8" remaining="${9:-}"
	local shooter_norm
	shooter_norm="$(game_flow__normalize_shooter "$shooter")"

	local stats_result
	case "$result" in
	hit) stats_result="hit" ;;
	miss) stats_result="miss" ;;
	sunk) stats_result="sunk" ;;
	already_shot)
		return 0
		;;
	win)
		stats_result="sunk"
		;;
	*) stats_result="$result" ;;
	esac

	if command -v stats_on_shot >/dev/null 2>&1; then
		stats_on_shot "$shooter_norm" "$stats_result" || true
	fi

	local params
	params="{\"shooter\":\"$shooter_norm\",\"coord\":\"$coord\",\"result\":\"$result\",\"owner\":\"$owner\",\"ship_name\":\"$ship_name\",\"shots\":$shots,\"hits\":$hits,\"misses\":$misses,\"remaining\":\"$remaining\"}"
	game_flow__log_info "shot_result" "$params"

	return 0
}

# Print summary when game ends
game_flow__print_summary_and_exit() {
	if command -v stats_end >/dev/null 2>&1; then
		stats_end || true
	fi
	if command -v stats_summary_text >/dev/null 2>&1; then
		stats_summary_text || true
	fi
}

# Convert zero-based r,c to human coordinate A1..
game_flow__coord_from_rc() {
	local r="$1" c="$2"
	if [[ ! "$r" =~ ^[0-9]+$ || ! "$c" =~ ^[0-9]+$ ]]; then
		return 1
	fi
	local letter
	letter="$(printf '%c' $((65 + r)))"
	printf "%s%d" "$letter" $((c + 1))
}

### Added API: a small, bounded main loop to coordinate prompt -> shoot -> render ###
# game_flow__main_loop <board_size> [max_turns] [p_state_fn] [p_owner_fn] [a_state_fn] [a_owner_fn]
# Returns:
#   0 on normal completion (win or max_turns exhausted),
#   2 on prompt failure,
#   3 on missing dependencies.
game_flow__main_loop() {
	local board_size="${1:-10}"
	local max_turns="${2:-100}"
	local p_state_fn="${3:-manual__player_state}"
	local p_owner_fn="${4:-manual__player_owner}"
	local a_state_fn="${5:-manual__ai_state}"
	local a_owner_fn="${6:-manual__ai_owner}"
	local turns=0

	while ((turns < max_turns)); do
		# Prompt for coordinate
		if ! command -v prompt_coordinate >/dev/null 2>&1; then
			printf "Missing prompt_coordinate\n" >&2
			return 3
		fi
		local coord
		coord="$(prompt_coordinate "${board_size}")" || return 2
		# Sanitize to uppercase (simple canonicalization for tests)
		coord="$(printf "%s" "$coord" | tr '[:lower:]' '[:upper:]')"

		# Ensure turn engine is present
		if ! command -v te_human_shoot >/dev/null 2>&1; then
			printf "Missing te_human_shoot\n" >&2
			return 3
		fi

		# Call turn engine and capture free-form output. The turn engine is expected to
		# emit a token like "RESULT:win" to signal a win; other outputs are tolerated.
		local out
		out="$(te_human_shoot "$coord" 2>/dev/null || true)"
		# Re-emit the turn engine output so tests (and callers) can observe it.
		printf "%s" "$out"

		# After each turn, render if renderer exists
		if command -v tui_render_dual_grid >/dev/null 2>&1; then
			tui_render_dual_grid "${board_size}" "${board_size}" "${p_state_fn}" "${p_owner_fn}" "${a_state_fn}" "${a_owner_fn}" "Turn ${turns}"
		fi

		# Detect win token and handle graceful end
		if [[ "${out}" =~ RESULT:win ]]; then
			# Print final stats and render final status where possible
			game_flow__print_summary_and_exit || true
			if command -v tui_render_dual_grid >/dev/null 2>&1; then
				tui_render_dual_grid "${board_size}" "${board_size}" "${p_state_fn}" "${p_owner_fn}" "${a_state_fn}" "${a_owner_fn}" "You win!"
			fi
			return 0
		fi

		turns=$((turns + 1))
	done

	# Max turns exhausted without an engine-level error: treat as normal completion
	return 0
}

### Added API: initialize AI by difficulty; returns underlying init result or error codes ###
# game_flow__init_ai <difficulty> <board_size> <seed>
game_flow__init_ai() {
	local diff="${1:-easy}"
	local size="${2:-10}"
	local seed="${3:-}"
	case "${diff}" in
	easy)
		if command -v bs_ai_easy_init >/dev/null 2>&1; then
			bs_ai_easy_init "${size}" "${seed}"
			return $?
		fi
		return 2
		;;
	medium)
		if command -v bs_ai_medium_init >/dev/null 2>&1; then
			bs_ai_medium_init "${size}" "${seed}"
			return $?
		fi
		return 2
		;;
	hard)
		if command -v bs_ai_hard_init >/dev/null 2>&1; then
			bs_ai_hard_init "${size}" "${seed}"
			return $?
		fi
		return 2
		;;
	*)
		printf "Unknown difficulty: %s\n" "${diff}" >&2
		return 4
		;;
	esac
}

# End Goals
