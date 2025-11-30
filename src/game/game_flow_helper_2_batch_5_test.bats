#!/usr/bin/env bats
# shellcheck shell=bats disable=SC2317,SC2012,SC1091

setup() {
	TEST_TMPDIR="$(mktemp -d)"
	mkdir -p "$TEST_TMPDIR/saves"
	export TEST_TMPDIR
}

teardown() {
	if [[ -n "$TEST_TMPDIR" && -d "$TEST_TMPDIR" ]]; then
		rm -rf -- "$TEST_TMPDIR"
	fi
}

@test "Integration:game_flow_load_existing_save_invokes_bs_load_state_and_renders_initial_grids_via_tui_renderer" {
	BS_LOAD_CALLED_FILE="$TEST_TMPDIR/bs_load_called"
	TUI_CALLED_FILE="$TEST_TMPDIR/tui_called"

	run bash -c '
		set -euo pipefail

		BS_LOAD_CALLED_FILE="'"$BS_LOAD_CALLED_FILE"'"
		TUI_CALLED_FILE="'"$TUI_CALLED_FILE"'"

		bs_load_state_load_file() {
			: >"$BS_LOAD_CALLED_FILE"
			return 0
		}

		tui_render_dual_grid() {
			: >"$TUI_CALLED_FILE"
			return 0
		}

		prompt_coordinate() {
			printf "A1"
			return 0
		}

		bs_board_is_win() {
			printf "true"
			return 0
		}

		bs_board_get_state() {
			printf "unknown"
			return 0
		}

		bs_board_get_owner() {
			printf ""
			return 0
		}

		game_flow__print_summary_and_exit() { return 0; }
		game_flow__log_info() { :; }
		game_flow__log_warn() { :; }
		te_set_on_shot_result_callback() { return 0; }

		. "'"${BATS_TEST_DIRNAME}/game_flow_helper_2.sh"'"

		game_flow_load_save "dummy.save"
	'
	[ "$status" -eq 0 ]
	[ -f "$BS_LOAD_CALLED_FILE" ]
	[ -f "$TUI_CALLED_FILE" ]
}

@test "Integration:turn_loop_runs_until_win_triggers_stats_updates_autosave_and_terminates_cleanly" {
	TMP_REPO="$TEST_TMPDIR/repo"
	mkdir -p "$TMP_REPO/persistence"

	cat >"$TMP_REPO/persistence/save_state.sh" <<'EOF'
#!/usr/bin/env bash
while [ "$#" -gt 0 ]; do
	case "$1" in
	--out)
		OUT="$2"
		shift 2
		;;
	*) shift ;;
	esac
done
if [[ -z "$OUT" ]]; then
	echo "missing out" >&2
	exit 2
fi
printf "saved_at:%s\n" "$(date -u +%s)" >"$OUT"
exit 0
EOF
	chmod +x "$TMP_REPO/persistence/save_state.sh"

	STATS_FILE="$TEST_TMPDIR/stats.out"
	WIN_COUNTER_FILE="$TEST_TMPDIR/win_counter"
	echo "0" > "$WIN_COUNTER_FILE"

	run bash -c '
		set -euo pipefail

		TEST_TMPDIR="'"$TEST_TMPDIR"'"
		TMP_REPO="'"$TMP_REPO"'"
		STATS_FILE="'"$STATS_FILE"'"
		WIN_COUNTER_FILE="'"$WIN_COUNTER_FILE"'"

		export REPO_ROOT="$TMP_REPO"

		bs_path_saves_dir() { printf "%s" "$TEST_TMPDIR/saves"; }

		stats_init() { _stats_init=1; }
		stats_start() { :; }
		stats_on_shot() {
			printf "%s,%s\n" "$1" "$2" >"$STATS_FILE"
			return 0
		}
		stats_summary_kv() { :; }
		stats_summary_text() { :; }

		bs_board_is_win() {
			# Fix: Use file-based counter because this function is called in a subshell $()
			# and variable updates would be lost, causing an infinite loop.
			local c
			c=$(cat "$WIN_COUNTER_FILE")
			c=$((c + 1))
			echo "$c" > "$WIN_COUNTER_FILE"
			if [ "$c" -ge 2 ]; then
				printf "true"
			else
				printf "false"
			fi
			return 0
		}

		bs_board_get_state() {
			printf "unknown"
			return 0
		}

		bs_board_get_owner() {
			printf ""
			return 0
		}

		te_human_shoot() {
			stats_on_shot player hit || true
			return 0
		}

		tui_render_dual_grid() { return 0; }

		prompt_coordinate() { return 1; }

		game_flow__log_info() { :; }
		game_flow__log_warn() { :; }

		. "'"${BATS_TEST_DIRNAME}/game_flow_helper_2.sh"'"

		stats_init

		game_flow__run_loop 1
	'
	[ "$status" -eq 0 ]

	[ -f "$STATS_FILE" ]
	read -r recorded <"$STATS_FILE"
	[ "$recorded" = "player,hit" ]

	SAVED_FILE_COUNT=$(find "$TEST_TMPDIR/saves" -maxdepth 1 -type f 2>/dev/null | wc -l || printf 0)
	[ "$SAVED_FILE_COUNT" -ge 1 ]
}