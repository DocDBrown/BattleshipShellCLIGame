#!/usr/bin/env bash
#
# Hard AI for Battleship
# Combines hunt/target strategies with orientation inference.

set -o nounset
set -o pipefail

# -----------------------------------------------------------------------------
# Dependencies
# -----------------------------------------------------------------------------

# Resolve directory of this script so tests can copy ai_hard.sh and create
# rng.sh / board_state.sh alongside it in a temp directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
. "${SCRIPT_DIR}/rng.sh"

# shellcheck source=/dev/null
. "${SCRIPT_DIR}/board_state.sh"

# -----------------------------------------------------------------------------
# Global State
# -----------------------------------------------------------------------------

# "hunt"  = random scouting
# "target"= following up around known hits
export BS_AI_HARD_STATE="hunt"

# Queued target cells (row/col parallel arrays)
# shellcheck disable=SC2034
BS_AI_HARD_TARGET_QUEUE_R=()
# shellcheck disable=SC2034
BS_AI_HARD_TARGET_QUEUE_C=()

# Cells that are part of the *current* ship we’re trying to finish off
# shellcheck disable=SC2034
BS_AI_HARD_HITS_R=()
# shellcheck disable=SC2034
BS_AI_HARD_HITS_C=()

# Visited map is represented as dynamic variables:
#   BS_AI_HARD_VISITED_<r>_<c>=1
# A cell is unvisited if the variable is unset.

# -----------------------------------------------------------------------------
# Initialize / Reset AI State
# -----------------------------------------------------------------------------
# bs_ai_hard_init
#   Idempotent reset of internal state, and clears the visited map.
# -----------------------------------------------------------------------------
bs_ai_hard_init() {
	BS_AI_HARD_STATE="hunt"
	BS_AI_HARD_TARGET_QUEUE_R=()
	BS_AI_HARD_TARGET_QUEUE_C=()
	BS_AI_HARD_HITS_R=()
	BS_AI_HARD_HITS_C=()

	# Clear visited map
	local r
	local c
	local size=${BS_BOARD_SIZE:-10}

	for ((r = 1; r <= size; r++)); do
		for ((c = 1; c <= size; c++)); do
			unset "BS_AI_HARD_VISITED_${r}_${c}"
		done
	done
}

# -----------------------------------------------------------------------------
# Choose next shot
# -----------------------------------------------------------------------------
# bs_ai_hard_choose_shot
#   Echoes "r c" to stdout and returns 0 on success.
#   Returns non-zero and no output when no moves remain.
# -----------------------------------------------------------------------------
bs_ai_hard_choose_shot() {
	local size=${BS_BOARD_SIZE:-10}
	local r
	local c

	# -------------------------------------------------------------
	# Target Mode: consume queued target cells first
	# -------------------------------------------------------------
	while [ "${#BS_AI_HARD_TARGET_QUEUE_R[@]}" -gt 0 ]; do
		# Pop from end (stack behavior to follow lines)
		local idx=$((${#BS_AI_HARD_TARGET_QUEUE_R[@]} - 1))
		r=${BS_AI_HARD_TARGET_QUEUE_R[idx]}
		c=${BS_AI_HARD_TARGET_QUEUE_C[idx]}

		unset 'BS_AI_HARD_TARGET_QUEUE_R[idx]'
		unset 'BS_AI_HARD_TARGET_QUEUE_C[idx]'

		# Compact arrays to remove gaps
		if [ "${#BS_AI_HARD_TARGET_QUEUE_R[@]}" -gt 0 ]; then
			BS_AI_HARD_TARGET_QUEUE_R=("${BS_AI_HARD_TARGET_QUEUE_R[@]}")
			BS_AI_HARD_TARGET_QUEUE_C=("${BS_AI_HARD_TARGET_QUEUE_C[@]}")
		else
			BS_AI_HARD_TARGET_QUEUE_R=()
			BS_AI_HARD_TARGET_QUEUE_C=()
		fi

		local visited_var="BS_AI_HARD_VISITED_${r}_${c}"
		if [ -z "${!visited_var:-}" ]; then
			# Valid unvisited target
			printf "%d %d\n" "$r" "$c"
			return 0
		fi
	done

	# If we reach here, queue is exhausted — switch to hunt
	BS_AI_HARD_STATE="hunt"

	# -------------------------------------------------------------
	# Hunt Mode: random unvisited cell
	# -------------------------------------------------------------
	local -a candidates_r=()
	local -a candidates_c=()
	local count=0

	for ((r = 1; r <= size; r++)); do
		for ((c = 1; c <= size; c++)); do
			local visited="BS_AI_HARD_VISITED_${r}_${c}"
			if [ -z "${!visited:-}" ]; then
				candidates_r[count]=$r
				candidates_c[count]=$c
				count=$((count + 1))
			fi
		done
	done

	if [ "$count" -eq 0 ]; then
		# No moves left
		return 1
	fi

	local rand_idx
	rand_idx="$(bs_rng_int_range 0 $((count - 1)))"

	r=${candidates_r[rand_idx]}
	c=${candidates_c[rand_idx]}

	printf "%d %d\n" "$r" "$c"
	return 0
}

# -----------------------------------------------------------------------------
# Notify AI of result
# -----------------------------------------------------------------------------
# bs_ai_hard_notify_result R C RESULT
#   RESULT ∈ { hit, miss, sink }
#   Updates visited map, hit chains, target queues, and forbidden cells.
# -----------------------------------------------------------------------------
bs_ai_hard_notify_result() {
	local r=$1
	local c=$2
	local result=$3 # hit, miss, sink

	# Mark this cell as visited regardless of outcome
	local visited_var="BS_AI_HARD_VISITED_${r}_${c}"
	printf -v "$visited_var" '%s' 1

	# -------------------------------------------------------------
	# Hit / Sink handling (track ship we’re currently hunting)
	# -------------------------------------------------------------
	if [ "$result" = "hit" ] || [ "$result" = "sink" ]; then
		local already_recorded=0
		local i

		# Avoid double-counting same hit (idempotent updates)
		for ((i = 0; i < ${#BS_AI_HARD_HITS_R[@]}; i++)); do
			if [ "${BS_AI_HARD_HITS_R[i]}" -eq "$r" ] &&
				[ "${BS_AI_HARD_HITS_C[i]}" -eq "$c" ]; then
				already_recorded=1
				break
			fi
		done

		if [ "$already_recorded" -eq 0 ]; then
			BS_AI_HARD_STATE="target"

			# Append to hit chain
			local len=${#BS_AI_HARD_HITS_R[@]}
			BS_AI_HARD_HITS_R[len]=$r
			BS_AI_HARD_HITS_C[len]=$c

			# Infer orientation from first two hits in this chain
			local orientation="unknown"
			local hits_count=${#BS_AI_HARD_HITS_R[@]}
			if [ "$hits_count" -ge 2 ]; then
				local r1=${BS_AI_HARD_HITS_R[0]}
				local c1=${BS_AI_HARD_HITS_C[0]}
				local r2=${BS_AI_HARD_HITS_R[1]}
				local c2=${BS_AI_HARD_HITS_C[1]}

				if [ "$r1" -eq "$r2" ]; then
					orientation="horizontal"
				elif [ "$c1" -eq "$c2" ]; then
					orientation="vertical"
				fi
			fi

			# Build new target cells around this chain
			local -a next_targets_r=()
			local -a next_targets_c=()
			local t_count=0

			_bs_ai_hard_add_target() {
				local tr=$1
				local tc=$2
				local size_local=${BS_BOARD_SIZE:-10}

				if ((tr >= 1 && tr <= size_local && tc >= 1 && tc <= size_local)); then
					local v_var="BS_AI_HARD_VISITED_${tr}_${tc}"
					if [ -z "${!v_var:-}" ]; then
						next_targets_r[t_count]=$tr
						next_targets_c[t_count]=$tc
						t_count=$((t_count + 1))
					fi
				fi
			}

			if [ "$orientation" = "horizontal" ]; then
				# Extend along row for all hits in chain
				for ((i = 0; i < ${#BS_AI_HARD_HITS_R[@]}; i++)); do
					local hr=${BS_AI_HARD_HITS_R[i]}
					local hc=${BS_AI_HARD_HITS_C[i]}
					_bs_ai_hard_add_target "$hr" $((hc - 1))
					_bs_ai_hard_add_target "$hr" $((hc + 1))
				done
			elif [ "$orientation" = "vertical" ]; then
				# Extend along column for all hits in chain
				for ((i = 0; i < ${#BS_AI_HARD_HITS_R[@]}; i++)); do
					local hr=${BS_AI_HARD_HITS_R[i]}
					local hc=${BS_AI_HARD_HITS_C[i]}
					_bs_ai_hard_add_target $((hr - 1)) "$hc"
					_bs_ai_hard_add_target $((hr + 1)) "$hc"
				done
			else
				# No orientation yet: just 4 neighbors of this hit
				_bs_ai_hard_add_target $((r - 1)) "$c"
				_bs_ai_hard_add_target $((r + 1)) "$c"
				_bs_ai_hard_add_target "$r" $((c - 1))
				_bs_ai_hard_add_target "$r" $((c + 1))
			fi

			# Once orientation is known, discard any older queued random targets
			if [ "$orientation" != "unknown" ]; then
				BS_AI_HARD_TARGET_QUEUE_R=()
				BS_AI_HARD_TARGET_QUEUE_C=()
			fi

			# Append new targets to queue (stack semantics: we pop from end)
			local k
			for ((k = 0; k < t_count; k++)); do
				local qlen=${#BS_AI_HARD_TARGET_QUEUE_R[@]}
				BS_AI_HARD_TARGET_QUEUE_R[qlen]=${next_targets_r[k]}
				BS_AI_HARD_TARGET_QUEUE_C[qlen]=${next_targets_c[k]}
			done
		fi
	fi

	# -------------------------------------------------------------
	# Sink handling: mark neighbors as forbidden and clear chain
	# -------------------------------------------------------------
	if [ "$result" = "sink" ]; then
		local size=${BS_BOARD_SIZE:-10}
		local dr
		local dc
		local nr
		local nc
		local i2

		# Mark all neighbors (including diagonals) of every hit in this ship
		for ((i2 = 0; i2 < ${#BS_AI_HARD_HITS_R[@]}; i2++)); do
			local hr=${BS_AI_HARD_HITS_R[i2]}
			local hc=${BS_AI_HARD_HITS_C[i2]}

			for dr in -1 0 1; do
				for dc in -1 0 1; do
					# Skip the cell itself; it is already visited
					if [ "$dr" -eq 0 ] && [ "$dc" -eq 0 ]; then
						continue
					fi
					nr=$((hr + dr))
					nc=$((hc + dc))
					if ((nr >= 1 && nr <= size && nc >= 1 && nc <= size)); then
						local v_var="BS_AI_HARD_VISITED_${nr}_${nc}"
						printf -v "$v_var" '%s' 1
					fi
				done
			done
		done

		# Clear hits tracking for this ship
		BS_AI_HARD_HITS_R=()
		BS_AI_HARD_HITS_C=()
	fi
}
