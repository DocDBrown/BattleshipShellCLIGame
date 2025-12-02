#!/usr/bin/env bash
# Helper 1: basic utilities (safe sourcing, simple die, usage, tempdir)
# Library: defines reusable helper functions; safe to source without side-effects.

set -euo pipefail
IFS=$'\n\t'

require_file() {
	local f="$1"
	if [ -z "${f:-}" ] || [ ! -f "$f" ]; then
		return 1
	fi
	return 0
}

safe_source() {
	local f="$1"
	if require_file "$f"; then
		# shellcheck source=/dev/null
		source "$f"
		return 0
	fi
	return 1
}

usage() {
	cat <<'USAGE' >&2
Usage: battleship.sh [--new] [--load FILE] [--size N] [--ai LEVEL] [--state-dir DIR] [--save FILE] [--version] [--help] [--doctor] [--self-check]
See 'battleship.sh --help' for detailed guidance.
USAGE
}

die() {
	local msg="${1:-}"
	local code=${2:-2}
	printf '%s\n' "$msg" >&2
	exit "$code"
}

_main_cleanup_on_error() { return 0; }

create_tempdir() {
	local tmp
	tmp="$(mktemp -d 2>/dev/null || true)"
	if [ -z "${tmp:-}" ] || [ ! -d "$tmp" ]; then
		die "Failed to create temporary directory with mktemp" 2
	fi
	if type exit_traps_add_temp >/dev/null 2>&1; then
		exit_traps_add_temp "$tmp" || true
	else
		# Install a runtime-only cleanup trap when not using the exit_traps helper.
		# The trap is created at invocation time so sourcing this file remains side-effect free.
		trap 'rm -rf -- "${tmp}" >/dev/null 2>&1 || true' EXIT
	fi
	printf '%s' "$tmp"
}
