#!/usr/bin/env bash

_bs_checksum_detected_tool=""

_bs_checksum_detect_tool() {
	if [ -n "$_bs_checksum_detected_tool" ]; then
		return 0
	fi

	if command -v sha256sum >/dev/null 2>&1; then
		_bs_checksum_detected_tool="sha256sum"
		return 0
	fi

	if command -v shasum >/dev/null 2>&1; then
		_bs_checksum_detected_tool="shasum"
		return 0
	fi

	if command -v openssl >/dev/null 2>&1; then
		_bs_checksum_detected_tool="openssl"
		return 0
	fi

	if command -v python3 >/dev/null 2>&1; then
		_bs_checksum_detected_tool="python3"
		return 0
	fi

	return 127
}

_bs_checksum_normalize_hex() {
	tr '[:upper:]' '[:lower:]' | tr -d ' \t\n\r'
}

bs_checksum_file() {
	# Expect exactly one argument: FILE
	if [ "$#" -ne 1 ]; then
		return 2
	fi

	local file="$1"
	if [ -z "$file" ]; then
		return 2
	fi

	case "$file" in
	-*)
		return 7
		;;
	esac

	if [[ "$file" == *$'\n'* ]]; then
		return 3
	fi

	if [ ! -e "$file" ]; then
		return 4
	fi
	if [ ! -f "$file" ]; then
		return 5
	fi
	if [ ! -r "$file" ]; then
		return 6
	fi

	_bs_checksum_detect_tool || return 127

	case "$_bs_checksum_detected_tool" in
	sha256sum)
		sha256sum -- "$file" 2>/dev/null | awk '{print $1}' | _bs_checksum_normalize_hex
		return 0
		;;
	shasum)
		shasum -a 256 -- "$file" 2>/dev/null | awk '{print $1}' | _bs_checksum_normalize_hex
		return 0
		;;
	openssl)
		openssl dgst -sha256 -r "$file" 2>/dev/null | awk '{print $1}' | _bs_checksum_normalize_hex
		return 0
		;;
	python3)
		python3 -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' \
			"$file" 2>/dev/null | _bs_checksum_normalize_hex
		return 0
		;;
	*)
		return 127
		;;
	esac
}

bs_checksum_verify() {
	# Usage: bs_checksum_verify EXPECTED_DIGEST FILE
	if [ "$#" -ne 2 ]; then
		return 2
	fi

	local expected="$1"
	local file="$2"

	if [ -z "$expected" ] || [ -z "$file" ]; then
		return 2
	fi

	case "$expected" in
	-*)
		return 7
		;;
	esac

	if [[ "$expected" == *$'\n'* ]]; then
		return 3
	fi

	# Compute actual digest via helper; any failure => generic computation error (3)
	if ! actual="$(bs_checksum_file "$file")"; then
		return 3
	fi

	# Normalize both and compare
	expected_norm="$(printf '%s' "$expected" | _bs_checksum_normalize_hex)"
	actual_norm="$(printf '%s' "$actual" | _bs_checksum_normalize_hex)"

	if [ "$expected_norm" = "$actual_norm" ]; then
		return 0
	else
		return 1
	fi
}
