#!/usr/bin/env bats

setup() {
	:
}

deardown() {
	:
}

@test "unit_self_check_sha_tool_prefers_sha256sum_then_shasum_reports_ok" {
	tmp=$(mktemp -d)
	wrapper="$tmp/wrap.sh"
	cat >"$wrapper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# SELF_CHECK_SCRIPT path in env
# shellcheck source=/dev/null
source "$SELF_CHECK_SCRIPT"
check_sha_tool
EOF
	chmod +x "$wrapper"

	# create sha256sum and shasum mocks
	cat >"$tmp/sha256sum" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ] || [ "${1:-}" = "-V" ] || [ "${1:-}" = "-v" ]; then
  printf "sha256sum mock 1.0\n"
  exit 0
fi
exit 0
EOF
	chmod +x "$tmp/sha256sum"

	cat >"$tmp/shasum" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ] || [ "${1:-}" = "-V" ] || [ "${1:-}" = "-v" ]; then
  printf "shasum mock 2.0\n"
  exit 0
fi
exit 0
EOF
	chmod +x "$tmp/shasum"

	# First: sha256sum present, should be preferred
	run timeout 5s env PATH="$tmp:$PATH" SELF_CHECK_SCRIPT="${BATS_TEST_DIRNAME}/src/diagnostics/self_check.sh" bash "$wrapper"
	[ "$status" -eq 0 ]
	[[ "$output" == *"sha256: OK (sha256sum)"* ]]

	# remove sha256sum to force shasum path
	rm -f "$tmp/sha256sum"

	# Second: only shasum available, should still report OK for sha256
	run timeout 5s env PATH="$tmp:$PATH" SELF_CHECK_SCRIPT="${BATS_TEST_DIRNAME}/src/diagnostics/self_check.sh" bash "$wrapper"
	[ "$status" -eq 0 ]
	# Do not assume the exact provider label; just verify OK for sha256
	[[ "$output" == *"sha256: OK"* ]]

	rm -rf "$tmp"
}

@test "unit_help_text_battleship_help_version_includes_optional_build_date_and_commit_when_set" {
	run timeout 5s bash -c "BATTLESHIP_APP_NAME='MyApp' BATTLESHIP_APP_VERSION='1.2.3' BATTLESHIP_BUILD_DATE='2025-01-01' BATTLESHIP_COMMIT_SHA='abcd1234' bash -c 'source \"${BATS_TEST_DIRNAME}/src/cli/help_text.sh\"; battleship_help_version'"
	[ "$status" -eq 0 ]
	[[ "$output" == *"MyApp 1.2.3"* ]]
	[[ "$output" == *"Build date: 2025-01-01"* ]]
	[[ "$output" == *"Commit: abcd1234"* ]]
}

@test "unit_exit_traps_handler_removes_registered_temp_and_atomic_files_and_restores_tty_state" {
	tmp=$(mktemp -d)
	exit_sh="${BATS_TEST_DIRNAME}/src/runtime/exit_traps.sh"
	wrapper="$tmp/wrapper.sh"
	stub_stty="$tmp/stty"
	touch "$tmp/file1" "$tmp/file2"

	cat >"$stub_stty" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$STTY_CALLED"
exit 0
EOF
	chmod +x "$stub_stty"

	export STTY_CALLED="$tmp/stty_called"

	cat >"$wrapper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export PATH="$tmp:\$PATH"
export __EXIT_TRAPS_TTY_STATE='mystate'
declare -a __EXIT_TRAPS_TEMP_FILES=("$tmp/file1" "$tmp/file2")
declare -A __EXIT_TRAPS_ATOMIC_MAP
__EXIT_TRAPS_ATOMIC_MAP['$tmp/file1']='/noop/target1'
__EXIT_TRAPS_ATOMIC_MAP['$tmp/file2']='/noop/target2'
# shellcheck source=/dev/null
source "$exit_sh"
__exit_traps_handler EXIT
EOF
	chmod +x "$wrapper"

	run timeout 5s bash "$wrapper"
	[ "$status" -eq 0 ]
	[ ! -e "$tmp/file1" ]
	[ ! -e "$tmp/file2" ]
	[ -f "$STTY_CALLED" ]
	grep -q 'mystate' "$STTY_CALLED"

	rm -rf "$tmp"
}

@test "unit_game_flow_manual_flag_returns_3_and_prints_unsupported_message" {
	run timeout 5s bash "${BATS_TEST_DIRNAME}/src/game/game_flow.sh" --manual
	[ "$status" -eq 3 ]
	[[ "$output" == *"Manual placement via game_flow is unsupported"* ]]
}
