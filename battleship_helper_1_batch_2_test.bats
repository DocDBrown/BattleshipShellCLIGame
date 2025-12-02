#!/usr/bin/env bats

setup() {
	TMPDIR_TEST_DIR="$(mktemp -d)"
}

teardown() {
	if [ -n "${TMPDIR_TEST_DIR:-}" ] && [[ "${TMPDIR_TEST_DIR}" == /* ]]; then
		rm -rf -- "${TMPDIR_TEST_DIR}" || true
	fi
}

# Helper to write env_safety.sh into the per-test temp dir
write_env_safety() {
	cat >"${TMPDIR_TEST_DIR}/env_safety.sh" <<'EOF'
#!/usr/bin/env bash
# env_safety.sh - set safe environment for battleship_shell_script
# Provides POSIX-ish safety while targeting bash 5.2.37 as requested

set -eu
# enable pipefail if supported by the running shell
if (set -o pipefail) >/dev/null 2>&1; then
	set -o pipefail
fi

# disable filename expansion (globbing)
set -f

# safe PATH; can be overridden by setting BS_SAFE_PATH prior to sourcing
: "${BS_SAFE_PATH:=/usr/bin:/bin}"
export PATH="${BS_SAFE_PATH}"

# disable core dumps where supported
ulimit -c 0 2>/dev/null || true

# enforce predictable locale for numeric parsing and stable behavior
export LC_ALL=C
export LANG=C

# conservative IFS to avoid word-splitting pitfalls (space-only to remain portable)
IFS=' '

# feature flags for presence of common utilities
BS_HAS_AWK=0
BS_HAS_SED=0
BS_HAS_OD=0
BS_HAS_MKTEMP=0
BS_HAS_TPUT=0
BS_HAS_DATE=0
BS_HAS_SHA256=0

check_cmd() {
	command -v "$1" >/dev/null 2>&1
}

if check_cmd awk; then BS_HAS_AWK=1; fi
if check_cmd sed; then BS_HAS_SED=1; fi
if check_cmd od; then BS_HAS_OD=1; fi
if check_cmd mktemp; then BS_HAS_MKTEMP=1; fi
if check_cmd tput; then BS_HAS_TPUT=1; fi
if check_cmd date; then BS_HAS_DATE=1; fi
if check_cmd sha256sum; then BS_HAS_SHA256=1; elif check_cmd shasum; then BS_HAS_SHA256=1; fi

export BS_HAS_AWK BS_HAS_SED BS_HAS_OD BS_HAS_MKTEMP BS_HAS_TPUT BS_HAS_DATE BS_HAS_SHA256

fatal_missing() {
	# concise, user-facing error on stderr and non-zero exit
	echo "$1" >&2
	exit 2
}

# mktemp is required for safe temporary file handling downstream
if [ "$BS_HAS_MKTEMP" -ne 1 ]; then
	fatal_missing "battleship_shell_script: required tool 'mktemp' not found in PATH"
fi

bs_env_init() {
	# Re-assert strictness for any caller contexts and export the runtime view
	set -eu
	if (set -o pipefail) >/dev/null 2>&1; then set -o pipefail; fi
	export PATH LC_ALL LANG IFS
	export BS_HAS_AWK BS_HAS_SED BS_HAS_OD BS_HAS_MKTEMP BS_HAS_TPUT BS_HAS_DATE BS_HAS_SHA256
	return 0
}
EOF
	chmod +x "${TMPDIR_TEST_DIR}/env_safety.sh"
}

# Helper to write paths.sh into the per-test temp dir
write_paths_sh() {
	cat >"${TMPDIR_TEST_DIR}/paths.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

_bs_normalize() {
	local p="$1"
	if [[ -z "$p" ]]; then return 1; fi
	if [[ "${p#-}" != "$p" ]]; then return 2; fi
	if [[ "$p" != /* ]]; then return 3; fi
	if [[ "$p" == *".."* ]]; then return 4; fi
	while [[ "$p" == *'//'* ]]; do p="$(printf '%s' "$p" | sed ':a; s#//#/#; ta')"; done
	if [[ "$p" != "/" ]]; then p="${p%/}"; fi
	printf '%s' "$p"
}

_bs_make_dir_secure() {
	local d="$1"
	if [[ -z "$d" ]]; then return 1; fi
	if [[ -L "$d" ]]; then return 2; fi
	if [[ -e "$d" && ! -d "$d" ]]; then return 3; fi
	mkdir -p -- "$d"
	chmod 0700 -- "$d"
	return 0
}

_bs_default_state_dir() {
	local p
	if [[ -n "${XDG_STATE_HOME-}" ]]; then p="${XDG_STATE_HOME%/}/battleship"; else p="${HOME%/}/.local/state/battleship"; fi
	_bs_normalize "$p" || printf '%s' "$p"
}

_bs_default_config_dir() {
	local p
	if [[ -n "${XDG_CONFIG_HOME-}" ]]; then p="${XDG_CONFIG_HOME%/}/battleship"; else p="${HOME%/}/.config/battleship"; fi
	_bs_normalize "$p" || printf '%s' "$p"
}

_bs_default_cache_dir() {
	local p
	if [[ -n "${XDG_CACHE_HOME-}" ]]; then p="${XDG_CACHE_HOME%/}/battleship"; else p="${HOME%/}/.cache/battleship"; fi
	_bs_normalize "$p" || printf '%s' "$p"
}

bs_path_state_dir_from_cli() {
	local override="${1-}"
	local dir
	if [[ -n "$override" ]]; then
		dir="$(_bs_normalize "$override")" || return 2
	else
		dir="$(_bs_default_state_dir)"
	fi
	_bs_make_dir_secure "$dir" || return 3
	printf '%s\n' "$dir"
}

bs_path_config_dir_from_cli() {
	local override="${1-}"
	local dir
	if [[ -n "$override" ]]; then
		dir="$(_bs_normalize "$override")" || return 2
	else
		dir="$(_bs_default_config_dir)"
	fi
	_bs_make_dir_secure "$dir" || return 3
	printf '%s\n' "$dir"
}

bs_path_cache_dir_from_cli() {
	local override="${1-}"
	local dir
	if [[ -n "$override" ]]; then
		dir="$(_bs_normalize "$override")" || return 2
	else
		dir="$(_bs_default_cache_dir)"
	fi
	_bs_make_dir_secure "$dir" || return 3
	printf '%s\n' "$dir"
}

bs_path_saves_dir() {
	local state
	state="$(bs_path_state_dir_from_cli "${1-}")" || return 1
	local d="$state/saves"
	_bs_make_dir_secure "$d" || return 2
	printf '%s\n' "$d"
}

bs_path_autosave_file() {
	local state
	state="$(bs_path_state_dir_from_cli "${1-}")" || return 1
	local d="$state/autosaves"
	_bs_make_dir_secure "$d" || return 2
	printf '%s\n' "$d/autosave.sav"
}

bs_path_log_file() {
	local state
	state="$(bs_path_state_dir_from_cli "${1-}")" || return 1
	local d="$state/logs"
	_bs_make_dir_secure "$d" || return 2
	printf '%s\n' "$d/battleship.log"
}
EOF
	chmod +x "${TMPDIR_TEST_DIR}/paths.sh"
}

@test "Integration: env_safety fatal_missing aborts with exit code 2 when mktemp is not found in PATH" {
	write_env_safety
	# create an empty PATH directory with no mktemp
	mkdir -p -- "${TMPDIR_TEST_DIR}/emptybin"
	
	# Resolve absolute paths for tools needed by the test runner (bash, timeout)
	local bash_bin
	bash_bin="$(command -v bash)"
	local timeout_bin
	timeout_bin="$(command -v timeout || true)"
	
	local cmd
	if [ -n "$timeout_bin" ]; then
		cmd=("$timeout_bin" "5s" "$bash_bin")
	else
		cmd=("$bash_bin")
	fi

	# Run the copied script with BS_SAFE_PATH and PATH that lack mktemp
	BS_SAFE_PATH="${TMPDIR_TEST_DIR}/emptybin" PATH="${TMPDIR_TEST_DIR}/emptybin" \
		run "${cmd[@]}" "${TMPDIR_TEST_DIR}/env_safety.sh"
	
	# Expect exit code 2 and informative message
	[ "$status" -eq 2 ]
	[[ "$output" == *"required tool 'mktemp' not found in PATH"* ]]
}

@test "Integration: env_safety bs_env_init exports BS_HAS_MKTEMP=1 and preserves LC_ALL and PATH when mktemp present" {
	write_env_safety

	# Save original PATH so we don't break Bats/teardown
	local orig_path="${PATH}"

	# Create a fake mktemp in a private bin and set BS_SAFE_PATH to point at it
	mkdir -p -- "${TMPDIR_TEST_DIR}/bin"
	cat >"${TMPDIR_TEST_DIR}/bin/mktemp" <<'MKT'
#!/usr/bin/env bash
# minimal mktemp stub; only existence matters for env_safety
exit 0
MKT
	chmod +x "${TMPDIR_TEST_DIR}/bin/mktemp"

	# Export BS_SAFE_PATH so the sourced script uses this PATH (and therefore finds mktemp)
	export BS_SAFE_PATH="${TMPDIR_TEST_DIR}/bin"
	export LC_ALL="C.UTF-8"

	# Source the copied env_safety; this defines bs_env_init and sets PATH=BS_SAFE_PATH
	# shellcheck source=/dev/null
	. "${TMPDIR_TEST_DIR}/env_safety.sh"

	# Call bs_env_init to export runtime view
	bs_env_init

	# After init, BS_HAS_MKTEMP should be 1
	[ "${BS_HAS_MKTEMP:-0}" -eq 1 ]
	# LC_ALL is enforced to C by env_safety.sh, so we expect C, not C.UTF-8
	[ "${LC_ALL:-}" = "C" ]
	# PATH should be preserved to BS_SAFE_PATH
	[ "${PATH:-}" = "${BS_SAFE_PATH}" ]

	# Restore PATH so Bats (and teardown) still see standard utilities like rm
	PATH="${orig_path}"
}

@test "Integration: bs_path_state_dir_from_cli with valid override creates directory with 0700 and returns canonical path" {
	write_paths_sh
	# Source the paths helper
	# shellcheck source=/dev/null
	. "${TMPDIR_TEST_DIR}/paths.sh"
	# Use a path inside the test tempdir to avoid touching repo
	override_dir="${TMPDIR_TEST_DIR}/my_state_dir"
	# Call the function and capture its output
	out="$(bs_path_state_dir_from_cli "$override_dir")"
	# Directory should exist
	[ -d "$out" ]
	# Permissions should be 700
	perms="$(stat -c '%a' -- "$out")"
	[ "$perms" = "700" ]
	# The returned path should be absolute and equal to the canonical path (no trailing slash)
	[ "$out" = "${override_dir%/}" ]
}
