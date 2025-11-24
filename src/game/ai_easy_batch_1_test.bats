#!/usr/bin/env bats

setup() {
	TEST_TMPDIR="$(mktemp -d)"
}

teardown() {
	if [[ -n "${TEST_TMPDIR:-}" && -d "${TEST_TMPDIR}" ]]; then
		rm -f "${TEST_TMPDIR}/rng.sh" "${TEST_TMPDIR}/board_state.sh" "${TEST_TMPDIR}/ai_easy.sh"
		rmdir "${TEST_TMPDIR}" 2>/dev/null || true
	fi
}

make_min_rng_batch_1() {
	cat >"${TEST_TMPDIR}/rng.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

BS_RNG_MODE="auto"
BS_RNG_STATE=1

bs_rng_init_from_seed() {
  if [ "$#" -lt 1 ]; then
    return 2
  fi
  BS_RNG_STATE=$1
  BS_RNG_MODE="lcg"
}

bs_rng_init_auto() {
  BS_RNG_MODE="auto"
  BS_RNG_STATE=1
}

bs_rng_lcg_next() {
  BS_RNG_STATE=$(((BS_RNG_STATE * 1103515245 + 12345) & 0x7fffffff))
  printf "%u" "$BS_RNG_STATE"
}

bs_rng_get_uint32() {
  if [ "$BS_RNG_MODE" = "lcg" ]; then
    bs_rng_lcg_next
    return 0
  fi
  bs_rng_lcg_next
}

bs_rng_int_range() {
  if [ "$#" -ne 2 ]; then
    return 2
  fi
  local min=$1
  local max=$2
  if [ "$min" -gt "$max" ]; then
    return 2
  fi
  local span=$((max - min + 1))
  if [ "$span" -le 1 ]; then
    printf "%d\n" "$min"
    return 0
  fi
  local v
  v=$(bs_rng_get_uint32)
  local r=$((v % span))
  printf "%d\n" $((min + r))
}

bs_rng_shuffle() {
  local -a arr=()
  if [ "$#" -gt 0 ]; then
    arr=("$@")
  else
    local i=0
    while IFS= read -r line; do
      arr[$i]="$line"
      i=$((i + 1))
    done
  fi
  local n=${#arr[@]}
  if [ "$n" -le 1 ]; then
    for item in "${arr[@]}"; do
      printf "%s\n" "$item"
    done
    return 0
  fi
  local i j tmp
  for ((i = n - 1; i > 0; i--)); do
    j=$(bs_rng_int_range 0 "$i")
    tmp="${arr[i]}"
    arr[i]="${arr[j]}"
    arr[j]="$tmp"
  done
  for item in "${arr[@]}"; do
    printf "%s\n" "$item"
  done
}
EOF
}

make_min_board_state_batch_1() {
	cat >"${TEST_TMPDIR}/board_state.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

BS_BOARD_SIZE=0

bs_board_new() {
  local n=${1:-10}
  BS_BOARD_SIZE=$n
  local r c
  for ((r = 0; r < n; r++)); do
    for ((c = 0; c < n; c++)); do
      eval "BS_CELL_${r}_${c}=unknown"
    done
  done
}

bs_board_get_state() {
  local r=$1 c=$2
  if ! [[ "$r" =~ ^[0-9]+$ && "$c" =~ ^[0-9]+$ ]]; then
    return 1
  fi
  if (( r < 0 || r >= BS_BOARD_SIZE || c < 0 || c >= BS_BOARD_SIZE )); then
    return 1
  fi
  local var="BS_CELL_${r}_${c}"
  if [[ -z "${!var+x}" ]]; then
    printf "unknown"
  else
    printf "%s" "${!var}"
  fi
}

bs_board_set_hit() {
  local r=$1 c=$2
  if (( r < 0 || r >= BS_BOARD_SIZE || c < 0 || c >= BS_BOARD_SIZE )); then
    return 1
  fi
  eval "BS_CELL_${r}_${c}=hit"
}

bs_board_set_miss() {
  local r=$1 c=$2
  if (( r < 0 || r >= BS_BOARD_SIZE || c < 0 || c >= BS_BOARD_SIZE )); then
    return 1
  fi
  eval "BS_CELL_${r}_${c}=miss"
}
EOF
}

load_ai_easy_batch_1() {
	make_min_rng_batch_1
	make_min_board_state_batch_1
	cp "${BATS_TEST_DIRNAME}/ai_easy.sh" "${TEST_TMPDIR}/ai_easy.sh"
	# shellcheck disable=SC1091
	. "${TEST_TMPDIR}/rng.sh"
	# shellcheck disable=SC1091
	. "${TEST_TMPDIR}/board_state.sh"
	# shellcheck disable=SC1091
	. "${TEST_TMPDIR}/ai_easy.sh"
}

@test "bs_ai_easy_choose_shot_after_init_returns_coordinate_within_board_bounds" {
	load_ai_easy_batch_1
	bs_board_new 5
	bs_ai_easy_init 5 123
	run bs_ai_easy_choose_shot
	[ "$status" -eq 0 ]
	[[ "$output" =~ ^[0-4]\ [0-4]$ ]]
}

@test "bs_ai_easy_choose_shot_never_repeats_same_coordinate_across_sequential_calls_until_exhaustion" {
	load_ai_easy_batch_1
	bs_board_new 3
	bs_ai_easy_init 3 42
	declare -A seen
	local total=$((3 * 3))
	local i r c key
	for ((i = 0; i < total; i++)); do
		run bs_ai_easy_choose_shot
		[ "$status" -eq 0 ]
		r=${output%% *}
		c=${output##* }
		key="${r},${c}"
		[ -z "${seen[$key]+x}" ]
		seen[$key]=1
		run bs_board_get_state "$r" "$c"
		[ "$status" -eq 0 ]
	done
	run bs_ai_easy_choose_shot
	[ "$status" -ne 0 ]
}

@test "bs_ai_easy_does_not_select_cells_marked_hit_or_miss_by_board_state_after_updates" {
	load_ai_easy_batch_1
	bs_board_new 4
	bs_ai_easy_init 4 7
	declare -A forbidden
	local i sel_r sel_c
	for ((i = 0; i < 3; i++)); do
		run bs_ai_easy_choose_shot
		[ "$status" -eq 0 ]
		sel_r=${output%% *}
		sel_c=${output##* }
		if ((i == 0)); then
			bs_board_set_hit "$sel_r" "$sel_c"
		else
			bs_board_set_miss "$sel_r" "$sel_c"
		fi
		forbidden["${sel_r},${sel_c}"]=1
	done
	for ((i = 0; i < 10; i++)); do
		run bs_ai_easy_choose_shot
		[ "$status" -eq 0 ] || break
		sel_r=${output%% *}
		sel_c=${output##* }
		[ -z "${forbidden["${sel_r},${sel_c}"]+x}" ]
	done
}

@test "bs_ai_easy_when_all_cells_exhausted_subsequent_choose_shot_returns_nonzero_error" {
	load_ai_easy_batch_1
	bs_board_new 2
	bs_ai_easy_init 2 5
	local total=$((2 * 2))
	local i
	for ((i = 0; i < total; i++)); do
		run bs_ai_easy_choose_shot
		[ "$status" -eq 0 ]
	done
	run bs_ai_easy_choose_shot
	[ "$status" -ne 0 ]
	[[ "$output" == *"no available unknown cells"* ]]
}

@test "bs_ai_easy_with_seeded_rng_produces_deterministic_sequence_given_same_seed_and_init" {
	load_ai_easy_batch_1
	bs_board_new 3
	bs_ai_easy_init 3 99
	local seq1=()
	local i
	for ((i = 0; i < 9; i++)); do
		run bs_ai_easy_choose_shot
		[ "$status" -eq 0 ]
		seq1+=("$output")
	done
	run bs_ai_easy_choose_shot
	[ "$status" -ne 0 ]
	setup
	load_ai_easy_batch_1
	bs_board_new 3
	bs_ai_easy_init 3 99
	local seq2=()
	for ((i = 0; i < 9; i++)); do
		run bs_ai_easy_choose_shot
		[ "$status" -eq 0 ]
		seq2+=("$output")
	done
	[ "${#seq1[@]}" -eq "${#seq2[@]}" ]
	for ((i = 0; i < 9; i++)); do
		[ "${seq1[$i]}" = "${seq2[$i]}" ]
	done
}
