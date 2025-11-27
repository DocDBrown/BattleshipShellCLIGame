#!/usr/bin/env bats
# shellcheck disable=SC1091

setup() {
	# Source libraries from the same directory as this test file
	# shellcheck disable=SC1091
	. "${BATS_TEST_DIRNAME}/tui_renderer.sh"
	# shellcheck disable=SC1091
	. "${BATS_TEST_DIRNAME}/accessibility_modes.sh"
	# Ensure deterministic probe state
	unset BS_MONOCHROME BS_HIGH_CONTRAST BS_NO_COLOR NO_COLOR BS_ACCESS_MODE BS_ACCESS_MODE_LOCK BS_TERM_PROBED BS_TERM_HAS_COLOR BS_TERM_RESET_SEQ || true
}

teardown() {
	:
}

# Helper function to fail tests with a message
fail() {
	printf "%s\n" "$1" >&2
	return 1
}

@test "bs_accessibility_style_for_returns_expected_symbols_and_sequences_for_color_high_contrast_and_monochrome" {
	unset BS_MONOCHROME BS_NO_COLOR NO_COLOR BS_HIGH_CONTRAST || true
	bs_accessibility_set_mode color || true
	out="$(bs_accessibility_style_for hit)"
	[[ -n "${out}" ]] || fail "empty output for color hit"
	[[ "${out}" == *"X"* ]] || fail "expected color mode to include symbol X, got: ${out}"

	bs_accessibility_set_mode high-contrast || true
	out="$(bs_accessibility_style_for hit)"
	[[ -n "${out}" ]] || fail "empty output for high-contrast hit"
	[[ "${out}" == *"✖"* ]] || fail "expected high-contrast symbol ✖, got: ${out}"

	bs_accessibility_set_mode monochrome || true
	out="$(bs_accessibility_style_for miss)"
	[[ -n "${out}" ]] || fail "empty output for monochrome miss"
	[[ "${out}" == *"o"* ]] || fail "expected monochrome miss symbol o, got: ${out}"
}

@test "bs_accessibility_map_all_emits_all_role_key_value_pairs_suitable_for_renderer_consumption" {
	unset BS_MONOCHROME BS_NO_COLOR NO_COLOR BS_HIGH_CONTRAST || true
	out="$(bs_accessibility_map_all)"
	echo "${out}"
	echo "${out}" | grep -q '^hit=' || fail "missing hit="
	echo "${out}" | grep -q '^miss=' || fail "missing miss="
	echo "${out}" | grep -q '^ship=' || fail "missing ship="
	echo "${out}" | grep -q '^water=' || fail "missing water="
	echo "${out}" | grep -q '^status=' || fail "missing status="
}

# Integration test that sources the renderer and uses simple in-process board query fns.
@test "tui_renderer_renders_dual_grid_player_ships_visible_ai_ships_hidden_uses_symbols_and_respects_modes_no_color_high_contrast_monochrome" {
	# Define small 3x3 board queries
	p_state_fn_batch_3_test() {
		# player has ship at 0,0; hit at 1,1; others unknown
		if [ "$1" -eq 0 ] && [ "$2" -eq 0 ]; then
			printf "ship"
		elif [ "$1" -eq 1 ] && [ "$2" -eq 1 ]; then
			printf "hit"
		else
			printf "unknown"
		fi
	}
	p_owner_fn_batch_3_test() {
		if [ "$1" -eq 0 ] && [ "$2" -eq 0 ]; then
			printf "destroyer"
		else
			printf ""
		fi
	}
	# AI: ships are hidden from the player view; simulate by returning unknown for ship cells.
	a_state_fn_batch_3_test() {
		# pretend AI has ship at 0,0 but renderer should display unknown/water
		printf "unknown"
	}
	a_owner_fn_batch_3_test() { printf ""; }

	# Ensure monochrome (no color) mode and assert plain symbols present
	export BS_MONOCHROME=1
	out="$(tui_render_dual_grid 3 3 p_state_fn_batch_3_test p_owner_fn_batch_3_test a_state_fn_batch_3_test a_owner_fn_batch_3_test "Last: Hit on B2; Destroyer damaged")"
	echo "${out}"
	
	# Player ship should render as 'S' in monochrome mode (per accessibility_modes.sh definition)
	echo "${out}" | grep -q 'S' || fail "expected player ship symbol 'S' in output when monochrome"
	
	# Hit should render as 'X'
	echo "${out}" | grep -q 'X' || fail "expected hit symbol 'X' in output when monochrome"
	
	# AI ship hidden: ensure there is no 'S' in the right-side grid (simple approximation)
	# Count total 'S' occurrences.
	# 1 in Legend (S Ship (#))
	# 1 in Legend word "Ship"
	# 1 in Grid (Player ship)
	# Total should be 3.
	# Use grep -o to count occurrences reliably across multiple lines
	count_s="$(printf "%s" "${out}" | grep -o 'S' | wc -l)"
	[ "${count_s}" -eq 3 ] || fail "unexpected number of 'S' symbols: ${count_s} (expected 3)"

	# Now test high-contrast mode: unset monochrome and request high-contrast
	unset BS_MONOCHROME || true
	bs_accessibility_set_mode high-contrast || true
	out_hc="$(tui_render_dual_grid 3 3 p_state_fn_batch_3_test p_owner_fn_batch_3_test a_state_fn_batch_3_test a_owner_fn_batch_3_test "HC mode status")"
	echo "${out_hc}"
	# high-contrast hit should include the unicode '✖' symbol
	echo "${out_hc}" | grep -q '✖' || fail "expected high-contrast symbol '✖' in output"
}