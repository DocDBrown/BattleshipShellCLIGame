#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
LC_ALL=C

# ai_medium_helper_3.sh - seen-shot bookkeeping utilities
#
# Purpose: Provide idempotent helpers to record and query indexes of previously
# targeted cells for the "medium" AI. These functions are library utilities
# intended to be sourced by higher-level AI modules. No work is performed at
# load time; only functions are defined. Globals:
#   BS_AI_MEDIUM_SEEN_SHOTS - array of numerical or string indexes recorded.
# Functions are idempotent and safe to call repeatedly.

# Ensure the global array exists in the current shell (do not overwrite if present).
if ! declare -p BS_AI_MEDIUM_SEEN_SHOTS >/dev/null 2>&1; then
	BS_AI_MEDIUM_SEEN_SHOTS=()
fi

# Internal: return 0 if idx is recorded in BS_AI_MEDIUM_SEEN_SHOTS, 1 otherwise.
_bs_ai_medium_has_seen() {
	local idx="${1:-}"
	if [[ -z "${idx}" ]]; then
		return 1
	fi
	local s
	for s in "${BS_AI_MEDIUM_SEEN_SHOTS[@]:-}"; do
		if [[ "${s}" == "${idx}" ]]; then
			return 0
		fi
	done
	return 1
}

# Internal: ensure an index is recorded in BS_AI_MEDIUM_SEEN_SHOTS (idempotent).
# Returns 0 on success, 2 on invalid input.
_bs_ai_medium_mark_seen() {
	local idx="${1:-}"
	if [[ -z "${idx}" ]]; then
		return 2
	fi
	_bs_ai_medium_has_seen "${idx}" && return 0
	BS_AI_MEDIUM_SEEN_SHOTS+=("${idx}")
	return 0
}
