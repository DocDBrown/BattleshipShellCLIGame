#!/usr/bin/env bats

setup() {
	TMPDIR="${BATS_TEST_DIRNAME}/tmp.$$.$RANDOM"
	mkdir -p "$TMPDIR"
}

teardown() {
	if [ -n "$TMPDIR" ] && [[ "$TMPDIR" == "$BATS_TEST_DIRNAME"* ]]; then
		rm -rf "$TMPDIR"
	else
		echo "Refusing to remove unsafe TMPDIR: $TMPDIR" >&2
	fi
}

@test "Integration_bs_rng_unseeded_int_range_uses_dev_urandom_returns_values_within_bounds_and_varies_across_processes" {
	src="${BATS_TEST_DIRNAME}/rng.sh"
	seq_len=50
	file1="$TMPDIR/out1.txt"
	file2="$TMPDIR/out2.txt"
	attempts=3
	attempt=1
	different=0
	while [ "$attempt" -le "$attempts" ]; do
		run timeout 10s bash -c "set -euo pipefail; . \"$src\"; for i in \$(seq 1 $seq_len); do bs_rng_int_range 0 9; done"
		[ "$status" -eq 0 ]
		printf "%s\n" "$output" >"$file1"
		run timeout 10s bash -c "set -euo pipefail; . \"$src\"; for i in \$(seq 1 $seq_len); do bs_rng_int_range 0 9; done"
		[ "$status" -eq 0 ]
		printf "%s\n" "$output" >"$file2"
		while IFS= read -r v; do
			if ! [[ "$v" =~ ^[0-9]+$ ]]; then
				echo "Non-integer in output1: $v" >&2
				return 1
			fi
			if [ "$v" -lt 0 ] || [ "$v" -gt 9 ]; then
				echo "Out of bounds in output1: $v" >&2
				return 1
			fi
		done <"$file1"
		while IFS= read -r v; do
			if ! [[ "$v" =~ ^[0-9]+$ ]]; then
				echo "Non-integer in output2: $v" >&2
				return 1
			fi
			if [ "$v" -lt 0 ] || [ "$v" -gt 9 ]; then
				echo "Out of bounds in output2: $v" >&2
				return 1
			fi
		done <"$file2"
		if ! cmp -s "$file1" "$file2"; then
			different=1
			break
		fi
		attempt=$((attempt + 1))
	done
	[ "$different" -eq 1 ]
}

@test "Integration_bs_rng_unseeded_shuffle_preserves_permutation_and_produces_different_orders_across_processes" {
	src="${BATS_TEST_DIRNAME}/rng.sh"
	elems=(alpha bravo charlie delta echo foxtrot)
	file1="$TMPDIR/sh1.txt"
	file2="$TMPDIR/sh2.txt"
	attempts=3
	attempt=1
	different=0
	while [ "$attempt" -le "$attempts" ]; do
		run timeout 10s bash -c "set -euo pipefail; . \"$src\"; bs_rng_shuffle ${elems[*]}"
		[ "$status" -eq 0 ]
		printf "%s\n" "$output" >"$file1"
		run timeout 10s bash -c "set -euo pipefail; . \"$src\"; bs_rng_shuffle ${elems[*]}"
		[ "$status" -eq 0 ]
		printf "%s\n" "$output" >"$file2"
		sort "$file1" >"$TMPDIR/sorted1.txt"
		sort "$file2" >"$TMPDIR/sorted2.txt"
		if ! cmp -s "$TMPDIR/sorted1.txt" "$TMPDIR/sorted2.txt"; then
			echo "Shuffled outputs do not contain same elements" >&2
			return 1
		fi
		if [ "$(wc -l <"$file1")" -ne "${#elems[@]}" ]; then
			echo "Unexpected number of lines in shuffle output1" >&2
			return 1
		fi
		if ! cmp -s "$file1" "$file2"; then
			different=1
			break
		fi
		attempt=$((attempt + 1))
	done
	[ "$different" -eq 1 ]
}
