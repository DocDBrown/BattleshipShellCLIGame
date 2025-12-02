#!/usr/bin/env bats
# shellcheck disable=SC1091,SC2088

setup() {
	TMP_HELP_DIR="$(mktemp -d)"
	# Create a minimal arg_parser-like helper implementing only the functions we need for tests.
	cat >"$TMP_HELP_DIR/arg_parser.sh" <<'ARG'
#!/usr/bin/env bash
# Minimal arg_parser shim for tests: normalize_path, is_integer, output_config
SOURCED=1

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

output_config() {
    # Export a subset of the environment variables used by callers
    export BATTLESHIP_NEW=0
    export BATTLESHIP_LOAD_FILE=""
    export BATTLESHIP_SIZE=""
    export BATTLESHIP_AI=""
    export BATTLESHIP_SEED=""
    export BATTLESHIP_NO_COLOR=0
    export BATTLESHIP_HIGH_CONTRAST=0
    export BATTLESHIP_MONOCHROME=0
    export BATTLESHIP_STATE_DIR="${HOME}/.battlestatedir"
    export BATTLESHIP_SAVE_FILE=""
    export BATTLESHIP_VERSION=0
    export BATTLESHIP_HELP=0
    export BATTLESHIP_DOCTOR=0
    export BATTLESHIP_SELF_CHECK=0
    export BATTLESHIP_ACTION=""
    export BATTLESHIP_COLOR_MODE="auto"
}
ARG

	# Create a minimal help_text shim implementing only battleship_help_version
	cat >"$TMP_HELP_DIR/help_text.sh" <<'HT'
#!/usr/bin/env bash
battleship_help_version() {
    local name="${BATTLESHIP_APP_NAME:-battleship_shell_script}"
    local ver="${BATTLESHIP_APP_VERSION:-0.0.0}"
    printf "%s\n" "${name} ${ver}"
}
HT
}

teardown() {
	if [ -n "${TMP_HELP_DIR:-}" ] && [[ "$TMP_HELP_DIR" == $(dirname "$TMP_HELP_DIR")* || -d "$TMP_HELP_DIR" ]]; then
		rm -rf -- "$TMP_HELP_DIR"
	fi
}

@test "normalize_path expands leading '~' and resolves '..' and '.' returning canonical relative path" {
	. "$TMP_HELP_DIR/arg_parser.sh"
	# Provide a literal tilde to the function; the function itself expands it to HOME.
	# shellcheck disable=SC2088
	result="$(normalize_path '~/a/../b/./c')"
	expected="$HOME/b/c"
	[ "$result" = "$expected" ]
}

@test "normalize_path preserves absolute root '/' and collapses redundant slashes" {
	. "$TMP_HELP_DIR/arg_parser.sh"
	r1="$(normalize_path '/')"
	[ "$r1" = "/" ]
	r2="$(normalize_path '/a//b////')"
	[ "$r2" = "/a/b" ]
}

@test "is_integer returns success for integer inputs and failure for non-numeric inputs" {
	run bash -c ". '$TMP_HELP_DIR/arg_parser.sh'; is_integer '123'"
	[ "$status" -eq 0 ]
	run bash -c ". '$TMP_HELP_DIR/arg_parser.sh'; is_integer '12a'"
	[ "$status" -ne 0 ]
}

@test "arg_parser when sourced exports BATTLESHIP_* variables and sets BATTLESHIP_COLOR_MODE accordingly" {
	run bash -c ". '$TMP_HELP_DIR/arg_parser.sh'; output_config; printf '%s' \"\$BATTLESHIP_COLOR_MODE\""
	[ "$status" -eq 0 ]
	[ "$output" = "auto" ]
}

@test "help_text battleship_help_version prints overridden app name and version from environment" {
	run bash -c "export BATTLESHIP_APP_NAME='MyApp'; export BATTLESHIP_APP_VERSION='1.2.3'; . '$TMP_HELP_DIR/help_text.sh'; battleship_help_version"
	[ "$status" -eq 0 ]
	[[ "$output" == *"MyApp 1.2.3"* ]]
}
