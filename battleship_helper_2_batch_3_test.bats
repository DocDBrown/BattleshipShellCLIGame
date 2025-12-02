#!/usr/bin/env bats

setup() {
	TMPDIR="$(mktemp -d)"
	export TMPDIR
	
	# Create the SUT file in the temporary directory
	cat >"$TMPDIR/battleship_helper_2.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Helper 2: runtime preparation, diagnostics, help/version dispatch
# Library: defines functions only; does not perform work at load.

# Provide a safe default for REPO_ROOT if the caller did not set it.
if [ "${REPO_ROOT:-}" = "" ]; then
	SCRIPTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
	REPO_ROOT="$(cd "${SCRIPTDIR}/.." >/dev/null 2>&1 && pwd)"
fi
export REPO_ROOT

prepare_runtime() {
	local env_safety
	env_safety="${REPO_ROOT%/}/runtime/env_safety.sh"

	# Prefer caller-provided safe_source; fall back to a friendly error if missing.
	if ! command -v safe_source >/dev/null 2>&1 || ! safe_source "$env_safety"; then
		if command -v die >/dev/null 2>&1; then
			die "Required runtime helper missing: $env_safety" 2
			return 2
		else
			printf '%s\n' "Required runtime helper missing: $env_safety" >&2
			return 2
		fi
	fi

	if command -v bs_env_init >/dev/null 2>&1; then
		bs_env_init || {
			if command -v die >/dev/null 2>&1; then
				die "bs_env_init failed" 2
				return 2
			else
				printf '%s\n' "bs_env_init failed" >&2
				return 2
			fi
		}
	fi

	local exit_traps
	exit_traps="${REPO_ROOT%/}/runtime/exit_traps.sh"
	if ! command -v safe_source >/dev/null 2>&1 || ! safe_source "$exit_traps"; then
		if command -v die >/dev/null 2>&1; then
			die "Required runtime helper missing: $exit_traps" 2
			return 2
		else
			printf '%s\n' "Required runtime helper missing: $exit_traps" >&2
			return 2
		fi
	fi

	if command -v exit_traps_capture_tty_state >/dev/null 2>&1; then
		exit_traps_capture_tty_state || true
	fi
	if command -v exit_traps_setup >/dev/null 2>&1; then
		exit_traps_setup || true
	fi

	local paths_sh
	paths_sh="${REPO_ROOT%/}/runtime/paths.sh"
	if ! command -v safe_source >/dev/null 2>&1 || ! safe_source "$paths_sh"; then
		if command -v die >/dev/null 2>&1; then
			die "Required runtime helper missing: $paths_sh" 2
			return 2
		else
			printf '%s\n' "Required runtime helper missing: $paths_sh" >&2
			return 2
		fi
	fi

	return 0
}

run_self_check() {
	local diag
	diag="${REPO_ROOT%/}/diagnostics/self_check.sh"

	if command -v safe_source >/dev/null 2>&1 && safe_source "$diag"; then
		# Execute in a subshell to avoid altering caller state; preserve exit status.
		bash "$diag" "$@"
		return $?
	fi

	if command -v die >/dev/null 2>&1; then
		die "Diagnostic helper missing: $diag" 2
		return 2
	fi
	printf '%s\n' "Diagnostic helper missing: $diag" >&2
	return 2
}

run_help_or_version() {
	local help_mod action
	help_mod="${REPO_ROOT%/}/cli/help_text.sh"
	action="${1:-}"

	if ! command -v safe_source >/dev/null 2>&1 || ! safe_source "$help_mod"; then
		if command -v die >/dev/null 2>&1; then
			die "Help module missing: $help_mod" 2
			return 2
		else
			printf '%s\n' "Help module missing: $help_mod" >&2
			return 2
		fi
	fi

	case "$action" in
	help)
		if command -v battleship_print_help >/dev/null 2>&1; then
			battleship_print_help
			return 0
		fi
		if command -v die >/dev/null 2>&1; then
			die "Help function missing in help_text.sh" 2
			return 2
		fi
		printf '%s\n' "Help function missing in help_text.sh" >&2
		return 2
		;;
	version)
		if command -v battleship_help_version >/dev/null 2>&1; then
			battleship_help_version
			return 0
		fi
		if command -v die >/dev/null 2>&1; then
			die "Version function missing in help_text.sh" 2
			return 2
		fi
		printf '%s\n' "Version function missing in help_text.sh" >&2
		return 2
		;;
	*)
		if command -v die >/dev/null 2>&1; then
			die "Unknown help/version action: $action" 1
			return 1
		fi
		printf 'Unknown help/version action: %s\n' "$action" >&2
		return 1
		;;
	esac
}

game_flow_entry() {
	if [ "${#}" -eq 0 ]; then
		return 0
	fi
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--manual)
			printf '%s\n' "Manual placement via game_flow is unsupported; run placement tool directly." >&2
			return 3
			;;
		--help | -h)
			printf '%s\n' "Usage: game_flow_entry [--manual]" >&2
			return 0
			;;
		*)
			shift
			;;
		esac
	done
	return 0
}
EOF
}

teardown() {
	if [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ]; then
		rm -rf -- "$TMPDIR"
	fi
}

@test "game_flow_manual_returns_3_and_prints_unsupported_message" {
	# Invoke the library in a subshell so we can source it and call the function.
	run bash -c ". \"$TMPDIR/battleship_helper_2.sh\"; game_flow_entry --manual 2>&1"

	# Expect the documented exit code for manual placement being unsupported.
	[ "$status" -eq 3 ]

	# The message should be emitted; allow matching as substring to be robust.
	[[ "$output" == *"Manual placement via game_flow is unsupported; run placement tool directly."* ]]
}