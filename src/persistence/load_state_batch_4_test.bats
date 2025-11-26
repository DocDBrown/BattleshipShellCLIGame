#!/usr/bin/env bats

setup() {
	TMPDIR="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp.XXXXXX")"
}

teardown() {
	if [[ -n "${TMPDIR:-}" && "${TMPDIR}" = "${BATS_TEST_DIRNAME}/"* ]]; then
		rm -rf -- "${TMPDIR}"
	fi
}

@test "Integration: load_state_rejects_save_with_missing_or_malformed_checksum_footer_and_reports_parse_error" {
	savefile="${TMPDIR}/save_missing_checksum.sav"
	printf 'SAVE_VERSION: 1\n[CONFIG]\nboard_size=10\n[BOARD]\n[TURNS]\n[STATS]\n' >"${savefile}"
	run timeout 5s bash -c "source \"${BATS_TEST_DIRNAME}/load_state.sh\"; bs_checksum_verify(){ return 0; }; bs__sanitize_type(){ printf '%s' \"\$1\"; return 0; }; bs_ship_length(){ printf '3'; return 0; }; bs_total_segments(){ printf '0'; return 0; }; bs_board_new(){ return 0; }; bs_board_set_ship(){ return 0; }; bs_board_set_hit(){ return 0; }; bs_board_set_miss(){ return 0; }; stats_init(){ return 0; }; stats_on_shot(){ return 0; }; bs_load_state_load_file \"${savefile}\""
	[ "$status" -eq 4 ]
	[[ "$output" == *"Missing or malformed checksum footer"* ]]
}

@test "Integration: load_state_rejects_save_with_incompatible_version_header_and_returns_version_mismatch_error" {
	savefile="${TMPDIR}/save_incompatible_version.sav"
	printf 'SAVE_VERSION: 2\n[CONFIG]\nboard_size=10\n[BOARD]\n[TURNS]\n[STATS]\nCHECKSUM: 0000000000000000000000000000000000000000000000000000000000000000\n' >"${savefile}"
	run timeout 5s bash -c "source \"${BATS_TEST_DIRNAME}/load_state.sh\"; bs_checksum_verify(){ return 0; }; bs__sanitize_type(){ printf '%s' \"\$1\"; return 0; }; bs_ship_length(){ printf '3'; return 0; }; bs_total_segments(){ printf '0'; return 0; }; bs_board_new(){ return 0; }; bs_board_set_ship(){ return 0; }; bs_board_set_hit(){ return 0; }; bs_board_set_miss(){ return 0; }; stats_init(){ return 0; }; stats_on_shot(){ return 0; }; bs_load_state_load_file \"${savefile}\""
	[ "$status" -eq 4 ]
	[[ "$output" == *"Unsupported save version: 2"* ]]
}
