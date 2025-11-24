#!/usr/bin/env bash

# Global state for the Easy AI
# Guard against resetting if sourced multiple times
if [[ -z "${BS_AI_EASY_INITIALIZED+x}" ]]; then
	BS_AI_EASY_INITIALIZED=0
fi
if [[ -z "${BS_AI_EASY_REMAINING_SHOTS+x}" ]]; then
	BS_AI_EASY_REMAINING_SHOTS=()
fi

# Path to the state file, exported so subshells (e.g., BATS 'run') can access it
export BS_AI_EASY_STATE_FILE=""

# Initialize the AI with board size and a random seed
bs_ai_easy_init() {
	local size="${1:-}"
	local seed="${2:-}"

	# Validate board size first (if provided) to match test expectations for specific error codes
	# Test expects exit code 3 for invalid size like "-5"
	if [[ -n "$size" ]] && [[ ! "$size" =~ ^[1-9][0-9]*$ ]]; then
		return 3
	fi

	# Check for missing arguments
	if [[ -z "$size" || -z "$seed" ]]; then
		return 2
	fi

	# Initialize the RNG dependency if available
	if command -v bs_rng_init_from_seed >/dev/null; then
		bs_rng_init_from_seed "$seed"
	fi

	# Generate a list of all possible coordinates (row:col)
	local -a all_coords=()
	local r c
	for ((r = 0; r < size; r++)); do
		for ((c = 0; c < size; c++)); do
			all_coords+=("${r}:${c}")
		done
	done

	# Shuffle the coordinates using the RNG dependency
	local shuffled_output
	shuffled_output=$(printf "%s\n" "${all_coords[@]}" | bs_rng_shuffle)

	# Populate the in-memory array (required by some tests)
	BS_AI_EASY_REMAINING_SHOTS=()
	while IFS= read -r line; do
		BS_AI_EASY_REMAINING_SHOTS+=("$line")
	done <<<"$shuffled_output"

	# Persist the shots to a temporary file to support subshell execution (BATS 'run')
	if [[ -z "$BS_AI_EASY_STATE_FILE" || ! -f "$BS_AI_EASY_STATE_FILE" ]]; then
		BS_AI_EASY_STATE_FILE=$(mktemp)
		export BS_AI_EASY_STATE_FILE
	fi
	printf "%s\n" "${BS_AI_EASY_REMAINING_SHOTS[@]}" >"$BS_AI_EASY_STATE_FILE"

	BS_AI_EASY_INITIALIZED=1
	export BS_AI_EASY_INITIALIZED
	return 0
}

# Choose the next shot coordinate
bs_ai_easy_choose_shot() {
	# Ensure AI is initialized
	if [[ "${BS_AI_EASY_INITIALIZED:-0}" -ne 1 ]]; then
		printf "AI not initialized\n" >&2
		return 2
	fi

	# Ensure state file exists
	if [[ -z "$BS_AI_EASY_STATE_FILE" || ! -f "$BS_AI_EASY_STATE_FILE" ]]; then
		# If we are in a subshell where INITIALIZED is 1 but file is gone, it's an error
		printf "AI state lost\n" >&2
		return 2
	fi

	local temp_file
	temp_file=$(mktemp)

	local found_r="" found_c=""
	local r c state coord

	# Read through the state file to find the first valid shot
	while IFS= read -r coord; do
		# If we already found a shot, just preserve the rest of the lines
		if [[ -n "$found_r" ]]; then
			echo "$coord" >>"$temp_file"
			continue
		fi

		r="${coord%%:*}"
		c="${coord##*:}"

		# Check board state to avoid shooting at already hit/miss cells
		state=$(bs_board_get_state "$r" "$c")

		if [[ "$state" == "hit" || "$state" == "miss" ]]; then
			# Skip this coordinate (effectively removing it from the list)
			continue
		fi

		# Found a valid shot
		found_r="$r"
		found_c="$c"
		# We do NOT write this coordinate to temp_file, effectively removing it
	done <"$BS_AI_EASY_STATE_FILE"

	# Atomically update the state file
	mv "$temp_file" "$BS_AI_EASY_STATE_FILE"

	if [[ -n "$found_r" ]]; then
		printf "%d %d\n" "$found_r" "$found_c"
		return 0
	fi

	# No valid shots remaining
	printf "no available unknown cells\n" >&2
	return 1
}
