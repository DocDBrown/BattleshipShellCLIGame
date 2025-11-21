#!/usr/bin/env bats

setup() {
	TMPDIR="$BATS_TEST_DIRNAME/tmp.$$.$RANDOM"
	mkdir -p "$TMPDIR"
}

teardown() {
	if [[ "$TMPDIR" == "$BATS_TEST_DIRNAME"* ]]; then
		rm -rf -- "$TMPDIR"
	else
		echo "Refusing to remove outside test dir" >&2
	fi
}

SUT="$BATS_TEST_DIRNAME/checksum.sh"

@test "bs_checksum_output_is_minimal_hex_only_for_known_content" {
	file="$TMPDIR/testfile.txt"
	printf 'hello world\n' >"$file"
	run timeout 30s bash -c "source \"$SUT\"; bs_checksum_file \"$file\""
	[ "$status" -eq 0 ]
	[[ "$output" =~ ^[0-9a-f]{64}$ ]]
	if command -v sha256sum >/dev/null 2>&1; then
		expected=$(sha256sum -- "$file" | awk '{print $1}')
	elif command -v shasum >/dev/null 2>&1; then
		expected=$(shasum -a 256 -- "$file" | awk '{print $1}')
	elif command -v openssl >/dev/null 2>&1; then
		expected=$(openssl dgst -sha256 -r "$file" | awk '{print $1}')
	elif command -v python3 >/dev/null 2>&1; then
		expected=$(python3 -c "import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "$file")
	else
		echo "No tool to compute expected digest" >&2
		false
	fi
	[ "$output" = "$expected" ]
}

@test "bs_checksum_verify_returns_success_exit_code_when_provided_digest_matches_computed" {
	file="$TMPDIR/ok.txt"
	printf 'ok\n' >"$file"
	run timeout 30s bash -c "source \"$SUT\"; bs_checksum_file \"$file\""
	[ "$status" -eq 0 ]
	digest="$output"
	run timeout 30s bash -c "source \"$SUT\"; bs_checksum_verify \"$digest\" \"$file\""
	[ "$status" -eq 0 ]
}

@test "bs_checksum_verify_returns_failure_exit_code_on_mismatch" {
	file="$TMPDIR/m.txt"
	printf 'mismatch\n' >"$file"
	bad="deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
	run timeout 30s bash -c "source \"$SUT\"; bs_checksum_verify \"$bad\" \"$file\""
	[ "$status" -eq 1 ]
}

@test "bs_checksum_verify_propagates_failure_exit_code_when_computation_errors" {
	nonexist="$TMPDIR/no_such_file_$(date +%s%N)"
	bad="deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
	run timeout 30s bash -c "source \"$SUT\"; bs_checksum_verify \"$bad\" \"$nonexist\""
	[ "$status" -eq 3 ]
}
