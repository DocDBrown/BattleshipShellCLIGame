#!/usr/bin/env bash
_validate_board_size() {
	local s="${1}"
	if [[ ! "${s}" =~ ^[0-9]+$ ]]; then
		return 1
	fi
	if ((s < 8 || s > 12)); then
		return 1
	fi
	return 0
}
validate_board_size() {
	_validate_board_size "${@}"
}
validate_coordinate() {
	local coord="${1}"
	local size="${2}"
	if ! _validate_board_size "${size}"; then
		return 2
	fi
	if [ -z "${coord}" ]; then
		return 1
	fi
	# Enforce strict uppercase coordinates per specification; do not normalize case
	if [[ ! "${coord}" =~ ^([A-Z])([1-9]|10|11|12)$ ]]; then
		return 1
	fi
	local letter="${BASH_REMATCH[1]}"
	local number="${BASH_REMATCH[2]}"
	local ord
	ord=$(printf '%d' "'${letter}") || return 1
	local max=$((65 + size - 1))
	if ((ord < 65 || ord > max)); then
		return 1
	fi
	if ((number < 1 || number > size)); then
		return 1
	fi
	return 0
}
validate_ai_difficulty() {
	local d="${1}"
	case "${d}" in
	easy | medium | hard) return 0 ;;
	*) return 1 ;;
	esac
}
is_non_empty_string() {
	[ -n "${1-}" ] && return 0 || return 1
}
is_safe_filename() {
	local fn="${1}"
	if [ -z "${fn}" ]; then
		return 1
	fi
	if [[ "${fn}" == -* ]]; then
		return 1
	fi
	if [[ "${fn}" == */* ]]; then
		return 1
	fi
	if [[ "${fn}" == *".."* ]]; then
		return 1
	fi
	if printf '%s' "${fn}" | LC_ALL=C grep -q '[[:cntrl:]]'; then
		return 1
	fi
	if printf '%s' "${fn}" | grep -q '[[:space:]]'; then
		return 1
	fi
	return 0
}
