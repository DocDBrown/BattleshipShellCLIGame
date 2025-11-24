#!/usr/bin/env bash
# ai_hard.sh
# Hard AI for Battleship
# Combines hunt/target strategies with orientation inference.

set -o nounset
set -o pipefail

# Dependencies
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/rng.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/board_state.sh"

# Global State
export BS_AI_HARD_STATE="hunt" # hunt or target
# shellcheck disable=SC2034
BS_AI_HARD_TARGET_QUEUE_R=()
# shellcheck disable=SC2034
BS_AI_HARD_TARGET_QUEUE_C=()
# shellcheck disable=SC2034
BS_AI_HARD_HITS_R=()
# shellcheck disable=SC2034
BS_AI_HARD_HITS_C=()

# Initialize/Reset AI State
bs_ai_hard_init() {
	BS_AI_HARD_STATE="hunt"
	BS_AI_HARD_TARGET_QUEUE_R=()
	BS_AI_HARD_TARGET_QUEUE_C=()
	BS_AI_HARD_HITS_R=()
	BS_AI_HARD_HITS_C=()

	# Clear visited map
	local r c
	local size=${BS_BOARD_SIZE:-10}
	for ((r = 1; r <= size; r++)); do
		for ((c = 1; c <= size; c++)); do
			unset "BS_AI_HARD_VISITED_${r}_${c}"
		done
	done
}

# Choose next shot coordinates
# Returns "r c" on stdout
bs_ai_hard_choose_shot() {
	local size=${BS_BOARD_SIZE:-10}
	local r c

	# Target Mode: Process Queue
	while [ ${#BS_AI_HARD_TARGET_QUEUE_R[@]} -gt 0 ]; do
		# Pop from end (Stack behavior to follow lines)
		local idx=$((${#BS_AI_HARD_TARGET_QUEUE_R[@]} - 1))
		r=${BS_AI_HARD_TARGET_QUEUE_R[idx]}
		c=${BS_AI_HARD_TARGET_QUEUE_C[idx]}

		# Remove from queue
		unset "BS_AI_HARD_TARGET_QUEUE_R[idx]"
		unset "BS_AI_HARD_TARGET_QUEUE_C[idx]"
		# Compact arrays
		BS_AI_HARD_TARGET_QUEUE_R=("${BS_AI_HARD_TARGET_QUEUE_R[@]}")
		BS_AI_HARD_TARGET_QUEUE_C=("${BS_AI_HARD_TARGET_QUEUE_C[@]}")

		# Check if already visited
		local visited_var="BS_AI_HARD_VISITED_${r}_${c}"
		if [ -z "${!visited_var:-}" ]; then
			printf "%d %d\n" "$r" "$c"
			return 0
		fi
	done

	# Hunt Mode (or empty queue)
	BS_AI_HARD_STATE="hunt"

	# Identify all unvisited cells
	local candidates_r=()
	local candidates_c=()
	local count=0

	for ((r = 1; r <= size; r++)); do
		for ((c = 1; c <= size; c++)); do
			local visited_var="BS_AI_HARD_VISITED_${r}_${c}"
			if [ -z "${!visited_var:-}" ]; then
				candidates_r[count]=$r
				candidates_c[count]=$c
				count=$((count + 1))
			fi
		done
	done

	if [ "$count" -eq 0 ]; then
		return 1 # No moves left
	fi

	# Random selection
	local rand_idx
	rand_idx=$(bs_rng_int_range 0 $((count - 1)))

	r=${candidates_r[rand_idx]}
	c=${candidates_c[rand_idx]}

	printf "%d %d\n" "$r" "$c"
}

# Notify AI of result
# Usage: bs_ai_hard_notify_result R C RESULT
bs_ai_hard_notify_result() {
	local r=$1
	local c=$2
	local result=$3 # hit, miss, sink

	local visited_var="BS_AI_HARD_VISITED_${r}_${c}"
	eval "${visited_var}=1"

	if [ "$result" = "hit" ] || [ "$result" = "sink" ]; then
		# Check if this hit is already recorded to avoid duplicate processing
		local already_recorded=0
		local i
		for ((i = 0; i < ${#BS_AI_HARD_HITS_R[@]}; i++)); do
			if [ "${BS_AI_HARD_HITS_R[i]}" -eq "$r" ] && [ "${BS_AI_HARD_HITS_C[i]}" -eq "$c" ]; then
				already_recorded=1
				break
			fi
		done

		if [ "$already_recorded" -eq 0 ]; then
			BS_AI_HARD_STATE="target"

			# Add to hits list
			local hlen=${#BS_AI_HARD_HITS_R[@]}
			BS_AI_HARD_HITS_R[hlen]=$r
			BS_AI_HARD_HITS_C[hlen]=$c

			# Infer orientation
			local orientation="unknown"
			if [ "$hlen" -ge 1 ]; then
				# Check first two hits in current chain
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

			# Generate potential targets
			local next_targets_r=()
			local next_targets_c=()
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
				# Add neighbors of ALL hits in chain
				local j
				for ((j = 0; j < ${#BS_AI_HARD_HITS_R[@]}; j++)); do
					local hr=${BS_AI_HARD_HITS_R[j]}
					local hc=${BS_AI_HARD_HITS_C[j]}
					_bs_ai_hard_add_target "$hr" "$((hc - 1))"
					_bs_ai_hard_add_target "$hr" "$((hc + 1))"
				done
			elif [ "$orientation" = "vertical" ]; then
				local j
				for ((j = 0; j < ${#BS_AI_HARD_HITS_R[@]}; j++)); do
					local hr=${BS_AI_HARD_HITS_R[j]}
					local hc=${BS_AI_HARD_HITS_C[j]}
					_bs_ai_hard_add_target "$((hr - 1))" "$hc"
					_bs_ai_hard_add_target "$((hr + 1))" "$hc"
				done
			else
				# Unknown: add all 4 neighbors of THIS hit
				_bs_ai_hard_add_target "$((r - 1))" "$c"
				_bs_ai_hard_add_target "$((r + 1))" "$c"
				_bs_ai_hard_add_target "$r" "$((c - 1))"
				_bs_ai_hard_add_target "$r" "$((c + 1))"
			fi

			# If orientation found, clear random queue to focus on line
			if [ "$orientation" != "unknown" ]; then
				BS_AI_HARD_TARGET_QUEUE_R=()
				BS_AI_HARD_TARGET_QUEUE_C=()
			fi

			# Push new targets to queue
			local k
			for ((k = 0; k < t_count; k++)); do
				local len=${#BS_AI_HARD_TARGET_QUEUE_R[@]}
				BS_AI_HARD_TARGET_QUEUE_R[len]=${next_targets_r[k]}
				BS_AI_HARD_TARGET_QUEUE_C[len]=${next_targets_c[k]}
			done
		fi
	fi

	if [ "$result" = "sink" ]; then
		# Ship sunk. Mark neighbors as visited (forbidden) to avoid touching ships.
		local size=${BS_BOARD_SIZE:-10}
		local i dr dc nr nc
		for ((i = 0; i < ${#BS_AI_HARD_HITS_R[@]}; i++)); do
			local hr=${BS_AI_HARD_HITS_R[i]}
			local hc=${BS_AI_HARD_HITS_C[i]}
			for dr in -1 0 1; do
				for dc in -1 0 1; do
					if [ "$dr" -eq 0 ] && [ "$dc" -eq 0 ]; then continue; fi
					nr=$((hr + dr))
					nc=$((hc + dc))
					if ((nr >= 1 && nr <= size && nc >= 1 && nc <= size)); then
						local v_var="BS_AI_HARD_VISITED_${nr}_${nc}"
						eval "${v_var}=1"
					fi
				done
			done
		done

		# Clear hits tracking for this ship.
		BS_AI_HARD_HITS_R=()
		BS_AI_HARD_HITS_C=()
	fi
}