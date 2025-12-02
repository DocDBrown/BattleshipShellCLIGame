#!/usr/bin/env bats

setup() {
	TMPTESTDIR="$(mktemp -d)"
	testdir="$TMPTESTDIR"
	# Copy the SUT into the isolated test dir
	cp "${BATS_TEST_DIRNAME}/battleship_helper_3.sh" "$testdir/"
	mkdir -p "$testdir/src/cli" "$testdir/src/game" "$testdir/src/diagnostics"

	# Minimal arg_parser to be sourced by the launcher; it sets exported BATTLESHIP_* vars.
	cat >"$testdir/src/cli/arg_parser.sh" <<'ARG'
#!/usr/bin/env bash
# minimal arg parser to set BATTLESHIP_* vars when sourced
BATTLESHIP_NEW=0
BATTLESHIP_LOAD_FILE=""
BATTLESHIP_ACTION=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --doctor|--self-check)
      BATTLESHIP_ACTION="doctor"
      shift
      ;;
    --new)
      BATTLESHIP_NEW=1
      shift
      ;;
    --load)
      BATTLESHIP_LOAD_FILE="$2"
      shift 2
      ;;
    --help)
      BATTLESHIP_ACTION="help"
      shift
      ;;
    *)
      shift
      ;;
  esac
done
export BATTLESHIP_NEW BATTLESHIP_LOAD_FILE BATTLESHIP_ACTION
ARG

	# Minimal game_flow that defines functions instead of top-level exit.
	# The launcher sources this file, so it must not exit immediately.
	cat >"$testdir/src/game/game_flow.sh" <<'GF'
#!/usr/bin/env bash
game_flow_load_save() {
  echo "game_flow: load $1"
  return 9
}
game_flow_start_new() {
  echo "game_flow: new"
  return 7
}
GF
	chmod +x "$testdir/src/game/game_flow.sh"

	# Minimal self_check that echoes and exits with a distinct code
	cat >"$testdir/src/diagnostics/self_check.sh" <<'SC'
#!/usr/bin/env bash
echo "self_check: running doctor"
exit 42
SC
	chmod +x "$testdir/src/diagnostics/self_check.sh"
}

teardown() {
	if [ -n "${testdir:-}" ]; then
		case "$testdir" in
		/tmp/* | /var/tmp/*)
			rm -rf -- "$testdir"
			;;
		*)
			echo "Refusing to remove unsafe testdir: $testdir" >&2
			;;
		esac
	fi
}

@test "launcher_Integration_dispatches_to_self_check_for_self_check_flag_and_propagates_exit_code" {
	run timeout 5s bash "$testdir/battleship_helper_3.sh" --doctor
	[ "$status" -eq 42 ]
	[[ "$output" == *"self_check: running doctor"* ]]
}

@test "launcher_Integration_dispatches_to_game_flow_for_new_game_and_propagates_exit_code" {
	run timeout 5s bash "$testdir/battleship_helper_3.sh" --new
	[ "$status" -eq 7 ]
	[[ "$output" == *"game_flow: new"* ]]
}

@test "launcher_Integration_dispatches_to_game_flow_for_load_game_and_propagates_exit_code" {
	run timeout 5s bash "$testdir/battleship_helper_3.sh" --load mysave.sav
	[ "$status" -eq 9 ]
	[[ "$output" == *"game_flow: load mysave.sav"* ]]
}