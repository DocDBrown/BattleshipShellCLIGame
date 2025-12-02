#!/usr/bin/env bats

setup() {
	TEST_TMPDIR="$(mktemp -d)"
	export TEST_TMPDIR
	mkdir -p "$TEST_TMPDIR/home"
	cat >"$TEST_TMPDIR/arg_parser_local.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

normalize_path() {
  local p="$1"
  if [ -z "$p" ]; then
    printf '%s' ""
    return 0
  fi
  if [[ "$p" == ~* ]]; then p="${HOME}${p:1}"; fi
  local abs=0
  if [[ "$p" == /* ]]; then abs=1; fi
  IFS='/' read -ra parts <<<"$p"
  local -a out=()
  local part
  for part in "${parts[@]}"; do
    if [ -z "$part" ] || [ "$part" == "." ]; then
      continue
    fi
    if [ "$part" == ".." ]; then
      if [ "${#out[@]}" -gt 0 ]; then
        unset 'out[${#out[@]}-1]'
      else
        if [ "$abs" -eq 0 ]; then out+=(..); fi
      fi
    else
      out+=("$part")
    fi
  done
  local joined
  if [ "${#out[@]}" -eq 0 ]; then
    if [ "$abs" -eq 1 ]; then joined="/"; else joined="."; fi
  else
    joined="$(printf '/%s' "${out[@]}")"
    if [ "$abs" -eq 0 ]; then joined="${joined:1}"; fi
  fi
  printf '%s' "$joined"
}

is_integer() {
  case "$1" in
    '' | *[!0-9-]*) return 1 ;;
    *) return 0 ;;
  esac
}

emit_error() {
  local msg="$1"
  local code="${2:-1}"
  printf '%s\n' "$msg" >&2
  exit "$code"
}

parse_arg_value() {
  if [ "${2:-}" == "" ]; then emit_error "Missing value for $1" 2; fi
}

check_size_bounds() {
  local val="$1"
  if ! is_integer "$val"; then emit_error "Size must be integer" 2; fi
  if [ "$val" -lt 8 ] || [ "$val" -gt 12 ]; then emit_error "Size must be between 8 and 12" 2; fi
}
EOF
}

teardown() {
	if [ -n "${TEST_TMPDIR:-}" ] && [[ "$TEST_TMPDIR" == $(dirname "$TEST_TMPDIR")/* || -d "$TEST_TMPDIR" ]]; then
		rm -rf -- "$TEST_TMPDIR"
	fi
}

@test "arg_parser_normalize_tilde_expands_to_home_and_preserves_components" {
	run timeout 5s bash -c "export HOME='$TEST_TMPDIR/home'; . '$TEST_TMPDIR/arg_parser_local.sh'; normalize_path '~/.config/../foo'"
	[ "$status" -eq 0 ]
	[ "$output" = "$TEST_TMPDIR/home/foo" ]
}

@test "arg_parser_normalize_relative_with_parent_components_resolves_correctly" {
	run timeout 5s bash -c ". '$TEST_TMPDIR/arg_parser_local.sh'; normalize_path '../a/./b/../c'"
	[ "$status" -eq 0 ]
	[ "$output" = "../a/c" ]
}

@test "arg_parser_is_integer_accepts_positive_and_negative_integers_and_rejects_non_numeric" {
	run timeout 5s bash -c ". '$TEST_TMPDIR/arg_parser_local.sh'; is_integer 42"
	[ "$status" -eq 0 ]

	run timeout 5s bash -c ". '$TEST_TMPDIR/arg_parser_local.sh'; is_integer -3"
	[ "$status" -eq 0 ]

	run timeout 5s bash -c ". '$TEST_TMPDIR/arg_parser_local.sh'; is_integer abc"
	[ "$status" -ne 0 ]
}

@test "arg_parser_missing_value_for_flag_size_emits_error_and_exit_code_2" {
	run timeout 5s bash -c ". '$TEST_TMPDIR/arg_parser_local.sh'; parse_arg_value --size ''"
	[ "$status" -eq 2 ]
	[[ "$output" == *"Missing value for --size"* ]]
}

@test "arg_parser_invalid_size_out_of_bounds_emits_error_and_exit_code_2" {
	run timeout 5s bash -c ". '$TEST_TMPDIR/arg_parser_local.sh'; check_size_bounds 7"
	[ "$status" -eq 2 ]
	[[ "$output" == *"Size must be between 8 and 12"* ]]
}
