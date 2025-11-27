#!/usr/bin/env bats

teardown() {
	if [ -n "${TEST_TMPDIR:-}" ] && [[ "${TEST_TMPDIR}" = "${BATS_TEST_DIRNAME}"* ]]; then
		rm -rf -- "${TEST_TMPDIR}"
	fi
}

@test "Integration_bs_checksum_file_uses_system_sha256sum_and_writes_only_64char_lowercase_hex_for_real_file" {
	TEST_TMPDIR=$(mktemp -d "${BATS_TEST_DIRNAME}/tmp.XXXX") || fail "mktemp failed"
	file="${TEST_TMPDIR}/data.txt"
	printf 'hello world\n' >"$file"
	script="${BATS_TEST_DIRNAME}/checksum.sh"

	run timeout 5s bash -c "source \"$script\"; bs_checksum_file \"$file\""
	[ "$status" -eq 0 ]
	got="$output"
	[[ "$got" =~ ^[0-9a-f]{64}$ ]] || fail "digest not 64 lowercase hex: $got"

	run timeout 5s sha256sum -- "$file"
	[ "$status" -eq 0 ]
	expected=$(echo "$output" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')

	run timeout 5s bash -c "source \"$script\"; bs_checksum_file \"$file\""
	[ "$status" -eq 0 ]
	[ "$output" = "$expected" ]
}

@test "Integration_bs_checksum_file_falls_back_to_shasum_when_sha256sum_absent_and_outputs_minimal_hex" {
	TEST_TMPDIR=$(mktemp -d "${BATS_TEST_DIRNAME}/tmp.XXXX") || fail "mktemp failed"
	file="${TEST_TMPDIR}/data.txt"
	printf 'hello world\n' >"$file"
	mkdir -p "${TEST_TMPDIR}/bin" || fail "mkdir failed"
	script="${BATS_TEST_DIRNAME}/checksum.sh"

	# Copy only the minimal helpers and shasum into the test bin so detection finds shasum but not sha256sum
	for prog in shasum awk tr grep; do
		p=$(command -v "$prog" 2>/dev/null) || fail "required helper $prog not found"
		cp -- "$p" "${TEST_TMPDIR}/bin/$(basename "$p")" || fail "cp $p failed"
		chmod +x "${TEST_TMPDIR}/bin/$(basename "$p")"
	done

	run timeout 5s bash -c "PATH='${TEST_TMPDIR}/bin'; source \"$script\"; bs_checksum_file \"$file\""
	[ "$status" -eq 0 ]
	got="$output"
	[[ "$got" =~ ^[0-9a-f]{64}$ ]] || fail "digest not 64 lowercase hex: $got"

	run timeout 5s bash -c "PATH='${TEST_TMPDIR}/bin'; shasum -a 256 -- \"$file\""
	[ "$status" -eq 0 ]
	expected=$(echo "$output" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')

	run timeout 5s bash -c "PATH='${TEST_TMPDIR}/bin'; source \"$script\"; bs_checksum_file \"$file\""
	[ "$status" -eq 0 ]
	[ "$output" = "$expected" ]
}

@test "Integration_bs_checksum_file_falls_back_to_openssl_and_strips_prefix_to_emit_only_hex" {
	TEST_TMPDIR=$(mktemp -d "${BATS_TEST_DIRNAME}/tmp.XXXX") || fail "mktemp failed"
	file="${TEST_TMPDIR}/data.txt"
	printf 'hello world\n' >"$file"
	mkdir -p "${TEST_TMPDIR}/bin" || fail "mkdir failed"
	script="${BATS_TEST_DIRNAME}/checksum.sh"

	# Copy only openssl and required helpers into the test bin so detection finds openssl but not sha256sum/shasum
	for prog in openssl awk tr grep; do
		p=$(command -v "$prog" 2>/dev/null) || fail "required helper $prog not found"
		cp -- "$p" "${TEST_TMPDIR}/bin/$(basename "$p")" || fail "cp $p failed"
		chmod +x "${TEST_TMPDIR}/bin/$(basename "$p")"
	done

	run timeout 5s bash -c "PATH='${TEST_TMPDIR}/bin'; source \"$script\"; bs_checksum_file \"$file\""
	[ "$status" -eq 0 ]
	got="$output"
	[[ "$got" =~ ^[0-9a-f]{64}$ ]] || fail "digest not 64 lowercase hex: $got"

	run timeout 5s bash -c "PATH='${TEST_TMPDIR}/bin'; openssl dgst -sha256 -r \"$file\""
	[ "$status" -eq 0 ]
	expected=$(echo "$output" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')

	run timeout 5s bash -c "PATH='${TEST_TMPDIR}/bin'; source \"$script\"; bs_checksum_file \"$file\""
	[ "$status" -eq 0 ]
	[ "$output" = "$expected" ]
}
