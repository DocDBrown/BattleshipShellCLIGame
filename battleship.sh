#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
LC_ALL=C

SCRIPTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd "${SCRIPTDIR}/src" >/dev/null 2>&1 && pwd)"

# Minimal die until helpers are sourced
die_min() {
	local msg="$1"
	local code=${2:-2}
	printf '%s\n' "$msg" >&2
	exit "$code"
}

# Load helper modules placed alongside this entrypoint
if [ -f "${SCRIPTDIR}/battleship_helper_1.sh" ]; then
	# shellcheck source=/dev/null
	source "${SCRIPTDIR}/battleship_helper_1.sh"
else
	die_min "Missing helper: ${SCRIPTDIR}/battleship_helper_1.sh" 2
fi
if [ -f "${SCRIPTDIR}/battleship_helper_2.sh" ]; then
	# shellcheck source=/dev/null
	source "${SCRIPTDIR}/battleship_helper_2.sh"
else
	die_min "Missing helper: ${SCRIPTDIR}/battleship_helper_2.sh" 2
fi
if [ -f "${SCRIPTDIR}/battleship_helper_3.sh" ]; then
	# shellcheck source=/dev/null
	source "${SCRIPTDIR}/battleship_helper_3.sh"
else
	die_min "Missing helper: ${SCRIPTDIR}/battleship_helper_3.sh" 2
fi

main() {
	umask 0077

	prepare_runtime || die_min "Runtime preparation failed" 2

	local argp="${REPO_ROOT}/cli/arg_parser.sh"
	if ! safe_source "$argp"; then
		die_min "Argument parser missing: $argp" 2
	fi

	# help_text may depend on exported color flags; load if present
	local help_mod="${REPO_ROOT}/cli/help_text.sh"
	safe_source "$help_mod" || true

	# Resolve state directory via paths helper when available
	local resolved_state=""
	if type bs_path_state_dir_from_cli >/dev/null 2>&1; then
		if [ "${BATTLESHIP_STATE_DIR:-}" ]; then
			resolved_state="$(bs_path_state_dir_from_cli "${BATTLESHIP_STATE_DIR}" 2>/dev/null || true)"
		else
			resolved_state="$(bs_path_state_dir_from_cli 2>/dev/null || true)"
		fi
	fi
	if [ -n "${resolved_state:-}" ]; then
		export BATTLESHIP_STATE_DIR_RESOLVED="$resolved_state"
	fi

	local action="${BATTLESHIP_ACTION:-}"
	if [ "${BATTLESHIP_SELF_CHECK:-0}" = "1" ]; then
		run_self_check --self-check
		exit $?
	fi

	case "$action" in
	help)
		run_help_or_version help
		exit 0
		;;
	version)
		run_help_or_version version
		exit 0
		;;
	doctor)
		run_self_check --doctor
		exit $?
		;;
	"") ;;
	*)
		die_min "Unknown action requested: ${action}" 1
		;;
	esac

	TMPDIR="$(create_tempdir)"
	export BATTLESHIP_TMPDIR="$TMPDIR"

	dispatch_game_flow "$@"
	local rc=$?

	if type exit_traps_set_exit_code >/dev/null 2>&1; then
		exit_traps_set_exit_code "$rc" || true
	fi

	exit "$rc"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	main "$@"
fi
