#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

manual__safe_source() {
	local f="${1:-}"
	if [[ -f "${f}" ]]; then
		# shellcheck disable=SC1090
		. "${f}"
	else
		printf "%s\n" "Required file not found: ${f}" >&2
		exit 2
	fi
}

manual__safe_source "${SCRIPTDIR}/../model/ship_rules.sh"
manual__safe_source "${SCRIPTDIR}/../util/validation.sh"
manual__safe_source "${SCRIPTDIR}/../model/board_state.sh"
manual__safe_source "${SCRIPTDIR}/placement_validator.sh"
manual__safe_source "${SCRIPTDIR}/../tui/tui_prompts.sh"
manual__safe_source "${SCRIPTDIR}/../tui/tui_renderer.sh"

# Renderer callbacks invoked indirectly by tui_render_dual_grid
# shellcheck disable=SC2317
manual__player_state() { bs_board_get_state "${1:-}" "${2:-}" || printf "unknown"; }
# shellcheck disable=SC2317
manual__player_owner() { bs_board_get_owner "${1:-}" "${2:-}" || printf ""; }
# shellcheck disable=SC2317
manual__ai_state() { printf "unknown"; }
# shellcheck disable=SC2317
manual__ai_owner() { printf ""; }

usage() {
	cat <<'USAGE' >&2
Usage: manual_placement.sh [--board-size N] [-h|--help]
Interactive manual ship placement using TUI helpers. Exit codes: 0=success,2=input error/cancel,3=switched-to-auto
During prompts you may type AUTO to abort and request automatic placement, or R to undo the last placed ship.
USAGE
}

# Parse coordinate like A5 -> print zero-based row and col (row col)
# Standard Battleship: Letter is Row (A=0), Number is Column (1=0)
manual__parse_coord() {
	local coord="${1:-}"
	local letter="${coord:0:1}"
	local number="${coord:1}"

	local row
	case "${letter}" in
		A) row=0 ;;
		B) row=1 ;;
		C) row=2 ;;
		D) row=3 ;;
		E) row=4 ;;
		F) row=5 ;;
		G) row=6 ;;
		H) row=7 ;;
		I) row=8 ;;
		J) row=9 ;;
		K) row=10 ;;
		L) row=11 ;;
		M) row=12 ;;
		N) row=13 ;;
		O) row=14 ;;
		P) row=15 ;;
		Q) row=16 ;;
		R) row=17 ;;
		S) row=18 ;;
		T) row=19 ;;
		U) row=20 ;;
		V) row=21 ;;
		W) row=22 ;;
		X) row=23 ;;
		Y) row=24 ;;
		Z) row=25 ;;
		*) return 1 ;;
	 esac

	local col=$((number - 1))
	printf "%d %d" "${row}" "${col}"
}

# Rebuild board from an array of placement entries formatted as: start_r|start_c|orient|ship
manual__reapply_placements() {
	# Access PLACED from caller scope.
	bs_board_new "${BS_BOARD_SIZE}"
	if [ "${#PLACED[@]}" -eq 0 ]; then
		return 0
	fi

	local entry
	for entry in "${PLACED[@]}"; do
		local sr="${entry%%|*}"
		local rest="${entry#*|}"
		local sc="${rest%%|*}"
		rest="${rest#*|}"
		local orient="${rest%%|*}"
		local ship="${rest#*|}"

		if ! _bs_placement__normalize_orientation "${orient}"; then
			printf "%s\n" "Internal error: invalid orientation while reapplying" >&2
			return 1
		fi

		local i r c len
		len="$(bs_ship_length "${ship}")"
		for ((i = 0; i < len; i++)); do
			r=$((sr + _BS_PL_DR * i))
			c=$((sc + _BS_PL_DC * i))
			# Guard against ((...)) implementations returning 1 on first increment.
			bs_board_set_ship "${r}" "${c}" "${ship}" || true
		done
	done
	return 0
}

# Optional test/helper: dump board stats when requested.
DUMP_STATS=0
manual__maybe_dump_stats() {
	if ((DUMP_STATS)); then
		# Print total placed segments and remaining segments.
		local total="${BS_BOARD_TOTAL_SEGMENTS:-0}"
		local remaining
		remaining="$(bs_board_total_remaining_segments)"
		printf "STATS: total_segments=%s remaining=%s\n" "${total}" "${remaining}"
	fi
}

main() {
	local board_size_arg=""
	while [ "$#" -gt 0 ]; do
		case "$1" in
		-h|--help)
			usage
			return 0
			;;
		--board-size)
			board_size_arg="${2:-}"
			shift 2
			;;
		--board-size=*)
			board_size_arg="${1#*=}"
			shift
			;;
		--dump-stats)
			DUMP_STATS=1
			shift
			;;
		*)
			printf "Unknown argument: %s\n" "$1" >&2
			usage
			return 1
			;;
		esac
	done

	if [ -n "${board_size_arg:-}" ]; then
		if ! validate_board_size "${board_size_arg}"; then
			printf "Invalid board size: %s\n" "${board_size_arg}" >&2
			return 1
		fi
		bs_board_new "${board_size_arg}"
	else
		if ((BS_BOARD_SIZE == 0)); then
			local bs
			bs="$(prompt_board_size "Enter board size (8-12): ")" || {
				printf "Board size prompt cancelled\n" >&2
				manual__maybe_dump_stats
				return 2
			}
			bs_board_new "${bs}"
		fi
	fi

	local -a PLACED=()
	local ship
	# Load ships into array to avoid stdin conflict in loop
	local -a ships=()
	while IFS= read -r ship; do
		[ -n "${ship}" ] && ships+=("${ship}")
	done < <(bs_ship_list)

	local i
	# Use index-based loop to allow going back on undo
	for ((i = 0; i < ${#ships[@]}; i++)); do
		ship="${ships[i]}"
		while true; do
			tui_render_dual_grid "${BS_BOARD_SIZE}" "${BS_BOARD_SIZE}" \
				manual__player_state manual__player_owner \
				manual__ai_state manual__ai_owner \
				"Placing: $(bs_ship_name "${ship}")"

			printf "Placing %s (length %s). Enter starting coordinate, or type AUTO to switch to auto-placement, R to undo last.\n" \
				"$(bs_ship_name "${ship}")" "$(bs_ship_length "${ship}")"

			local raw_coord
			raw_coord="$(safe_read_line "Enter coordinate (e.g. A5): ")" || {
				printf "Input closed\n" >&2
				manual__maybe_dump_stats
				return 2
			}
			raw_coord="$(trim "${raw_coord}")"
			raw_coord="$(upper "${raw_coord}")"

			if [ -z "${raw_coord}" ]; then
				printf "Input cannot be empty\n" >&2
				continue
			fi

			if [ "${raw_coord}" = "AUTO" ] || [ "${raw_coord}" = "A" ]; then
				printf "Switching to auto-placement\n" >&2
				manual__maybe_dump_stats
				return 3
			fi

			if [ "${raw_coord}" = "R" ] || [ "${raw_coord}" = "REPLACE" ]; then
				# Undo last placement
				local keys=("${!PLACED[@]}")
				if (( ${#keys[@]} == 0 )); then
					printf "No previous placement to undo\n" >&2
					continue
				fi
				local last_idx="${keys[-1]}"
				unset "PLACED[$last_idx]"
				# Re-index to avoid holes
				PLACED=("${PLACED[@]}")

				manual__reapply_placements || {
					printf "Failed to reapply placements\n" >&2
					return 1
				}
				printf "Last placement removed\n" >&2

				# Go back to previous ship (i-1). Since for-loop increments i,
				# we set i = i - 2 and let the next i++ bring us to i-1.
				((i -= 2)) || true
				break
			fi

			if ! validate_coordinate "${raw_coord}" "${BS_BOARD_SIZE}"; then
				printf "Invalid coordinate: %s\n" "${raw_coord}" >&2
				continue
			fi

			local coords
			coords="$(manual__parse_coord "${raw_coord}")" || {
				printf "Internal error: failed to parse coordinate %s\n" "${raw_coord}" >&2
				return 1
			}
			local row col
			row="${coords%% *}"
			col="${coords##* }"

			local raw_orient
			raw_orient="$(safe_read_line "Orientation (H/V, default H): ")" || {
				printf "Input closed\n" >&2
				manual__maybe_dump_stats
				return 2
			}
			raw_orient="$(trim "${raw_orient}")"
			raw_orient="${raw_orient:-H}"
			raw_orient="$(upper "${raw_orient}")"

			if [ "${raw_orient}" = "AUTO" ] || [ "${raw_orient}" = "A" ]; then
				printf "Switching to auto-placement\n" >&2
				manual__maybe_dump_stats
				return 3
			fi

			if [ "${raw_orient}" = "R" ]; then
				# Orientation-level undo of last ship
				local keys2=("${!PLACED[@]}")
				if (( ${#keys2[@]} == 0 )); then
					printf "No previous placement to undo\n" >&2
					continue
				fi
				local last_idx2="${keys2[-1]}"
				unset "PLACED[$last_idx2]"
				PLACED=("${PLACED[@]}")

				manual__reapply_placements || {
					printf "Failed to reapply placements\n" >&2
					return 1
				}
				printf "Last placement removed\n" >&2
				((i -= 2)) || true
				break
			fi

			local orient
			case "${raw_orient}" in
				H|HOR*) orient=h ;;
				V|VER*) orient=v ;;
				*)
					printf "Invalid orientation: %s\n" "${raw_orient}" >&2
					continue
					;;
			esac

			if ! bs_placement_validate "${row}" "${col}" "${orient}" "${ship}"; then
				printf "Placement validation failed for %s at %d,%d %s\n" \
					"${ship}" "${row}" "${col}" "${orient}" >&2
				continue
			fi

			if ! _bs_placement__normalize_orientation "${orient}"; then
				printf "Internal orientation normalization failed\n" >&2
				return 1
			fi

			local len j r c
			len="$(bs_ship_length "${ship}")"
			for ((j = 0; j < len; j++)); do
				r=$((row + _BS_PL_DR * j))
				c=$((col + _BS_PL_DC * j))
				# Guard bs_board_set_ship against set -e via arithmetic semantics.
				bs_board_set_ship "${r}" "${c}" "${ship}" || true
			done

			PLACED+=("${row}|${col}|${orient}|${ship}")
			break
		done
	done

	tui_render_dual_grid "${BS_BOARD_SIZE}" "${BS_BOARD_SIZE}" \
		manual__player_state manual__player_owner \
		manual__ai_state manual__ai_owner \
		"All ships placed"

	printf "Manual placement complete\n"
	manual__maybe_dump_stats
	return 0
}

main "$@"
