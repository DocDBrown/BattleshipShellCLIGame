#!/usr/bin/env bats

@test "Integration_bs_checksum_verify_returns_zero_on_real_match_and_nonzero_on_real_mismatch" {
	# Create a per-test temporary directory inside the test directory
	tmpdir="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp.XXXX")"
	if [ -z "$tmpdir" ]; then
		fail "mktemp failed to create tmpdir"
	fi
	# Ensure we will only remove paths inside the test dir
	case "$tmpdir" in
	"${BATS_TEST_DIRNAME}"*)
		# ok
		;;
	*)
		rm -rf "$tmpdir" 2>/dev/null || true
		fail "tmpdir outside of test directory: $tmpdir"
		;;
	esac

	file="$tmpdir/save.dat"
	file2="$tmpdir/save2.dat"
	printf 'hello world\n' >"$file"
	printf 'different content\n' >"$file2"

	# Compute digest for the first file using the real tool via the library
	run timeout 30s bash -c "set -euo pipefail; source \"${BATS_TEST_DIRNAME}/checksum.sh\"; bs_checksum_file \"$file\""
	[ "$status" -eq 0 ]
	# Normalize output to a single-line lowercase hex string
	digest="$(printf '%s' "$output" | tr -d '\n' | tr '[:upper:]' '[:lower:]')"
	[ -n "$digest" ]

	# Verify should succeed for matching file
	run timeout 30s bash -c "set -euo pipefail; source \"${BATS_TEST_DIRNAME}/checksum.sh\"; bs_checksum_verify \"$digest\" \"$file\""
	[ "$status" -eq 0 ]

	# Verify should fail (non-zero) for a different file
	run timeout 30s bash -c "set -euo pipefail; source \"${BATS_TEST_DIRNAME}/checksum.sh\"; bs_checksum_verify \"$digest\" \"$file2\""
	[ "$status" -ne 0 ]

	# Cleanup only the tmpdir we created, guarded by prefix check
	case "$tmpdir" in
	"${BATS_TEST_DIRNAME}"*)
		rm -rf "$tmpdir"
		;;
	*)
		fail "refusing to remove tmpdir outside test dir"
		;;
	esac
}
