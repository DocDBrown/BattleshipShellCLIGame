#!/usr/bin/env bash
set -euo pipefail

BS_RNG_MODE="auto"
BS_RNG_STATE=0
BS_RNG_MODULO=4294967296

bs_rng_init_from_seed() {
	if [ $# -lt 1 ]; then
		return 2
	fi
	local seed=$1
	BS_RNG_MODE="lcg"
	BS_RNG_STATE=$((seed & 0xFFFFFFFF))
	return 0
}

bs_rng_init_auto() {
	BS_RNG_MODE="auto"
	BS_RNG_STATE=0
	return 0
}

bs_rng_lcg_next() {
	BS_RNG_STATE=$(((BS_RNG_STATE * 1664525 + 1013904223) & 0xFFFFFFFF))
	printf "%u" "$BS_RNG_STATE"
}

bs_rng_get_uint32() {
	if [ "$BS_RNG_MODE" = "lcg" ]; then
		bs_rng_lcg_next
		return 0
	fi
	od -An -tu4 -N4 /dev/urandom | tr -d ' \n'
}

bs_rng_int_range() {
	if [ $# -ne 2 ]; then
		return 2
	fi
	local min=$1
	local max=$2
	if [ "$min" -gt "$max" ]; then
		return 2
	fi
	local span=$((max - min + 1))
	if [ "$span" -le 0 ]; then
		printf "%d\n" "$min"
		return 0
	fi
	if [ "$span" -eq 1 ]; then
		printf "%d\n" "$min"
		return 0
	fi
	local threshold=$(((BS_RNG_MODULO / span) * span))
	while :; do
		local v
		v=$(bs_rng_get_uint32)
		if [ -z "$v" ]; then
			continue
		fi
		if [ "$v" -lt "$threshold" ]; then
			local r=$((v % span))
			printf "%d\n" "$((min + r))"
			return 0
		fi
	done
}

bs_rng_shuffle() {
	local -a arr=()
	if [ $# -gt 0 ]; then
		arr=("$@")
	else
		local i=0
		while IFS= read -r line; do
			arr[i]="$line"
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
		j=$(bs_rng_int_range 0 $i)
		tmp="${arr[i]}"
		arr[i]="${arr[j]}"
		arr[j]="$tmp"
	done
	for item in "${arr[@]}"; do
		printf "%s\n" "$item"
	done
}
