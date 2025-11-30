#!/usr/bin/env bats

# Only load assert helper if present
if [ -f "${BATS_TEST_DIRNAME}/assert.bash" ]; then
	load "assert"
fi

setup() {
	TMPTESTDIR="$(mktemp -d)"
}

teardown() {
	rm -rf "${TMPTESTDIR}"
}

@test "Unit_MainLoop_HumanTurn_prompts_via_tui_prompts_prompt_coordinate_and_calls_turn_engine_te_human_shoot_with_sanitized_coord" {
	mkdir -p "${TMPTESTDIR}/mocks"
	cat >"${TMPTESTDIR}/mocks/tui_prompts.sh" <<'SH'
prompt_coordinate() { printf "%s" "a5"; }
SH
	cat >"${TMPTESTDIR}/mocks/turn_engine.sh" <<'SH'
te_human_shoot() { printf "RESULT:miss\nGOT:%s\n" "$1"; }
SH
	run timeout 5s bash -c ". \"${BATS_TEST_DIRNAME}/game_flow_helper_1.sh\"; . \"${TMPTESTDIR}/mocks/tui_prompts.sh\"; . \"${TMPTESTDIR}/mocks/turn_engine.sh\"; game_flow__main_loop 10 1"
	[ "$status" -eq 0 ]
	echo "$output" | grep -q "GOT:A5"
}

@test "Unit_MainLoop_AfterEachTurn_calls_tui_render_dual_grid_with_player_and_ai_callbacks_and_updates_status" {
	mkdir -p "${TMPTESTDIR}/mocks"
	cat >"${TMPTESTDIR}/mocks/tui_prompts.sh" <<'SH'
prompt_coordinate() { printf "%s" "B3"; }
SH
	cat >"${TMPTESTDIR}/mocks/turn_engine.sh" <<'SH'
te_human_shoot() { printf "RESULT:miss\n"; }
SH
	cat >"${TMPTESTDIR}/mocks/tui_renderer.sh" <<'SH'
tui_render_dual_grid() { printf "RENDER_CALLED status:%s\n" "$7"; }
manual__player_state() { printf "unknown"; }
manual__player_owner() { printf ""; }
manual__ai_state() { printf "unknown"; }
manual__ai_owner() { printf ""; }
SH
	run timeout 5s bash -c ". \"${BATS_TEST_DIRNAME}/game_flow_helper_1.sh\"; . \"${TMPTESTDIR}/mocks/tui_prompts.sh\"; . \"${TMPTESTDIR}/mocks/turn_engine.sh\"; . \"${TMPTESTDIR}/mocks/tui_renderer.sh\"; game_flow__main_loop 8 1"
	[ "$status" -eq 0 ]
	echo "$output" | grep -q "RENDER_CALLED status:Turn 0"
}

@test "Unit_MainLoop_When_turn_engine_reports_win_exits_loop_calls_stats_end_and_renders_win_status" {
	mkdir -p "${TMPTESTDIR}/mocks"
	cat >"${TMPTESTDIR}/mocks/tui_prompts.sh" <<'SH'
prompt_coordinate() { printf "%s" "C1"; }
SH
	cat >"${TMPTESTDIR}/mocks/turn_engine.sh" <<'SH'
te_human_shoot() { printf "RESULT:win\n"; }
SH
	cat >"${TMPTESTDIR}/mocks/tui_renderer.sh" <<'SH'
tui_render_dual_grid() { printf "FINAL_RENDER status:%s\n" "$7"; }
manual__player_state() { printf "unknown"; }
manual__player_owner() { printf ""; }
manual__ai_state() { printf "unknown"; }
manual__ai_owner() { printf ""; }
SH
	cat >"${TMPTESTDIR}/mocks/stats.sh" <<'SH'
stats_end() { printf "STATS_END_CALLED\n"; }
stats_summary_text() { printf "STATS_SUMMARY\n"; }
SH
	run timeout 5s bash -c ". \"${BATS_TEST_DIRNAME}/game_flow_helper_1.sh\"; . \"${TMPTESTDIR}/mocks/tui_prompts.sh\"; . \"${TMPTESTDIR}/mocks/turn_engine.sh\"; . \"${TMPTESTDIR}/mocks/tui_renderer.sh\"; . \"${TMPTESTDIR}/mocks/stats.sh\"; game_flow__main_loop 8 1"
	[ "$status" -eq 0 ]
	echo "$output" | grep -q "STATS_END_CALLED"
	echo "$output" | grep -q "STATS_SUMMARY"
	echo "$output" | grep -q "FINAL_RENDER status:You win!"
}

@test "Unit_AIInitialization_selects_requested_difficulty_and_calls_correct_ai_init_with_board_size_and_seed" {
	mkdir -p "${TMPTESTDIR}/mocks"
	cat >"${TMPTESTDIR}/mocks/ai_easy.sh" <<'SH'
bs_ai_easy_init() { printf "AI_EASY_INIT size:%s seed:%s\n" "$1" "$2"; return 0; }
SH
	run timeout 5s bash -c ". \"${BATS_TEST_DIRNAME}/game_flow_helper_1.sh\"; . \"${TMPTESTDIR}/mocks/ai_easy.sh\"; game_flow__init_ai easy 9 42"
	[ "$status" -eq 0 ]
	echo "$output" | grep -q "AI_EASY_INIT size:9 seed:42"
}

@test "Unit_AIInitialization_on_init_failure_aborts_game_start_and_returns_error_to_caller" {
	mkdir -p "${TMPTESTDIR}/mocks"
	cat >"${TMPTESTDIR}/mocks/ai_easy_fail.sh" <<'SH'
bs_ai_easy_init() { printf "AI_EASY_FAIL size:%s seed:%s\n" "$1" "$2"; return 3; }
SH
	run timeout 5s bash -c ". \"${BATS_TEST_DIRNAME}/game_flow_helper_1.sh\"; . \"${TMPTESTDIR}/mocks/ai_easy_fail.sh\"; game_flow__init_ai easy 11 badseed"
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "AI_EASY_FAIL size:11 seed:badseed"
}
