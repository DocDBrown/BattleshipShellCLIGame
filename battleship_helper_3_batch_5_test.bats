#!/usr/bin/env bats

setup() {
	TMPDIR="$(mktemp -d)"
	# Copy the SUT into a per-test temp dir and make a writable copy to operate on.
	cp "${BATS_TEST_DIRNAME}/battleship_helper_3.sh" "$TMPDIR/"
	chmod +x "$TMPDIR/battleship_helper_3.sh"

	# Minimal arg_parser so that --doctor sets BATTLESHIP_ACTION correctly.
	mkdir -p "$TMPDIR/src/cli"
	cat >"$TMPDIR/src/cli/arg_parser.sh" <<'ARGP'
#!/usr/bin/env bash
# Minimal arg parser for this test: only handle --doctor / --self-check.
BATTLESHIP_ACTION=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --doctor|--self-check)
      BATTLESHIP_ACTION="doctor"
      shift
      ;;
    *)
      shift
      ;;
  esac
done
export BATTLESHIP_ACTION
ARGP

	mkdir -p "$TMPDIR/src/diagnostics"
	cat >"$TMPDIR/src/diagnostics/self_check.sh" <<'SH'
#!/usr/bin/env bash
# Minimal self_check that returns non-zero to simulate failure
echo "self_check: simulated failure" >&2
exit 7
SH
	chmod +x "$TMPDIR/src/diagnostics/self_check.sh"
}

teardown() {
	if [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ]; then
		rm -rf -- "$TMPDIR"
	fi
}

@test "launcher_Integration_propagates_non_zero_exit_from_self_check_submodule" {
	run timeout 5s bash "$TMPDIR/battleship_helper_3.sh" --doctor
	[ "$status" -eq 7 ]
	[[ "$output" == *"simulated failure"* ]] || fail "expected self_check message"
}
