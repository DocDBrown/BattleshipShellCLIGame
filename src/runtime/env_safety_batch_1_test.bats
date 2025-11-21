#!/usr/bin/env bats

setup() {
	SCRIPT="${BATS_TEST_DIRNAME}/env_safety.sh"
}

teardown() {
	:
}

@test "unit_bs_env_init_constrains_PATH_when_unset_or_empty_to_trusted_dirs" {
	run timeout 5s bash -c "unset PATH; . \"${SCRIPT}\"; bs_env_init; printf '%s' \"\$PATH\""
	[ "$status" -eq 0 ]
	[ "$output" = "/usr/bin:/bin" ]
}

@test "unit_bs_env_init_replaces_untrusted_PATH_with_trusted_dirs" {
	run timeout 5s bash -c "export PATH=\"/tmp/fake/bin:/usr/local/bin\"; . \"${SCRIPT}\"; bs_env_init; printf '%s' \"\$PATH\""
	[ "$status" -eq 0 ]
	[ "$output" = "/usr/bin:/bin" ]
}

@test "unit_bs_env_init_preserves_already_trusted_PATH_idempotently" {
	run timeout 5s bash -c "export PATH=\"/usr/bin:/bin\"; . \"${SCRIPT}\"; bs_env_init; first=\"\$PATH\"; bs_env_init; second=\"\$PATH\"; printf '%s|%s' \"\$first\" \"\$second\""
	[ "$status" -eq 0 ]
	[ "$output" = "/usr/bin:/bin|/usr/bin:/bin" ]
}

@test "unit_bs_env_init_sets_locale_sanity_for_numeric_parsing_LC_ALL_C" {
	run timeout 5s bash -c ". \"${SCRIPT}\"; bs_env_init; printf '%s|%s' \"\$LC_ALL\" \"\$LANG\""
	[ "$status" -eq 0 ]
	[ "$output" = "C|C" ]
}

@test "unit_bs_env_init_exports_presence_flags_for_detected_utilities" {
	run timeout 5s bash -c ". \"${SCRIPT}\"; bs_env_init; printf '%s %s %s %s %s %s %s' \"\$BS_HAS_AWK\" \"\$BS_HAS_SED\" \"\$BS_HAS_OD\" \"\$BS_HAS_MKTEMP\" \"\$BS_HAS_TPUT\" \"\$BS_HAS_DATE\" \"\$BS_HAS_SHA256\""
	[ "$status" -eq 0 ]
	read -r a b c d e f g <<<"$output"
	[ "$d" = "1" ]
	for v in "$a" "$b" "$c" "$d" "$e" "$f" "$g"; do
		case "$v" in
		0 | 1) ;;
		*) false ;;
		esac
	done
}
