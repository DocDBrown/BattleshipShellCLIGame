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
