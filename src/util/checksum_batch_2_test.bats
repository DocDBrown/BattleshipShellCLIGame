#!/usr/bin/env bats

setup() {
	TMPDIR=$(mktemp -d)
	# Create a dummy file for checksumming
	echo "test content" >"${TMPDIR}/testfile.txt"
	# Expected sha256 for "test content\n"
	# Linux/macOS: 6ae8a75555209fd6c44157c0aed8016e763ff435a19cf186f76863140143ff72
	EXPECTED="6ae8a75555209fd6c44157c0aed8016e763ff435a19cf186f76863140143ff72"

	# Source the library under test
	# shellcheck source=./src/util/checksum.sh
	. "${BATS_TEST_DIRNAME}/checksum.sh"
}

teardown() {
	rm -rf "${TMPDIR}"
}

fail() {
	printf "%s\n" "$1" >&2
	return 1
}

@test "Integration_bs_checksum_file_uses_system_sha256sum_and_writes_only_64char_lowercase_hex_for_real_file" {
	# This test assumes sha256sum or shasum is available in the environment.
	# It verifies the output format is strictly the hash, no filenames or newlines.
	run bs_checksum_file "${TMPDIR}/testfile.txt"
	[ "$status" -eq 0 ]
	[ "$output" = "$EXPECTED" ]
}

@test "Integration_bs_checksum_file_falls_back_to_shasum_when_sha256sum_absent_and_outputs_minimal_hex" {
	# Mock sha256sum to be absent by defining a function that returns 127,
	# forcing the logic to try shasum (if available) or openssl.
	# Note: We can't easily 'unset' a command, but we can shadow it.
	sha256sum() { return 127; }
	export -f sha256sum

	# Check if shasum exists before asserting fallback behavior
	if ! command -v shasum >/dev/null 2>&1; then
		skip "shasum not found, cannot test fallback"
	fi

	run bs_checksum_file "${TMPDIR}/testfile.txt"
	[ "$status" -eq 0 ]
	[ "$output" = "$EXPECTED" ]
}

@test "Integration_bs_checksum_file_falls_back_to_openssl_and_strips_prefix_to_emit_only_hex" {
	# Mock both sha256sum and shasum to fail
	sha256sum() { return 127; }
	shasum() { return 127; }
	export -f sha256sum shasum

	# Check if openssl exists
	if ! command -v openssl >/dev/null 2>&1; then
		skip "openssl not found, cannot test fallback"
	fi

	run bs_checksum_file "${TMPDIR}/testfile.txt"
	[ "$status" -eq 0 ]
	# Verify format is strictly hex
	got="$output"
	[[ "$got" =~ ^[0-9a-f]{64}$ ]] || fail "digest not 64 lowercase hex: $got"
	[ "$got" = "$EXPECTED" ]
}