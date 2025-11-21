#!/usr/bin/env bats

setup() {
	:
}

teardown() {
	if [ -n "${TMP_TEST_DIR:-}" ] && [[ "${TMP_TEST_DIR}" == "${BATS_TEST_DIRNAME}"* || "${TMP_TEST_DIR}" == "${BATS_TEST_DIRNAME}/"* ]]; then
		rm -rf -- "${TMP_TEST_DIR}" || true
	fi
}

@test "unit_register_exit_and_signal_traps_sets_EXIT_INT_TERM_traps_and_returns_zero" {
	TMP_TEST_DIR="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp.XXXXXX")"
	run timeout 5s bash -c "source \"${BATS_TEST_DIRNAME}/exit_traps.sh\"; exit_traps_setup; rc=\$?; trap -p EXIT; trap -p INT; trap -p TERM; exit \$rc"
	[ "$status" -eq 0 ]
	[[ "$output" == *__exit_traps_handler* ]]
	[[ "$output" == *EXIT* ]]
	[[ "$output" == *INT* ]]
	[[ "$output" == *TERM* ]]
}

@test "unit_supports_exported_variable_and_setter_based_temp_path_registration_and_cleans_both" {
	TMP_TEST_DIR="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp.XXXXXX")"
	f1="$TMP_TEST_DIR/file_env.tmp"
	f2="$TMP_TEST_DIR/file_fn.tmp"
	touch "$f1" "$f2"

	run timeout 5s bash -c "__EXIT_TRAPS_TEMP_FILES=(); __EXIT_TRAPS_TEMP_FILES+=(\"$f1\"); source \"${BATS_TEST_DIRNAME}/exit_traps.sh\"; exit_traps_setup; exit_traps_add_temp \"$f2\"; __exit_traps_handler EXIT"
	# handler exits the subprocess; after run, files should be removed
	[ ! -e "$f1" ]
	[ ! -e "$f2" ]
}

@test "unit_cleanup_calls_rm_with_safe_flags_and_does_not_follow_symlinks_when_removing_paths" {
	TMP_TEST_DIR="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp.XXXXXX")"
	real="$TMP_TEST_DIR/real_target.txt"
	lnk="$TMP_TEST_DIR/the_link.lnk"
	echo "keep me" >"$real"
	ln -s "$real" "$lnk"

	# register symlink for removal
	run timeout 5s bash -c "__EXIT_TRAPS_TEMP_FILES=(); __EXIT_TRAPS_TEMP_FILES+=(\"$lnk\"); source \"${BATS_TEST_DIRNAME}/exit_traps.sh\"; exit_traps_setup; __exit_traps_handler EXIT"
	[ ! -e "$lnk" ]
	[ -e "$real" ]
	grep -q "keep me" "$real"
}

@test "unit_cleanup_restores_TTY_modes_and_echo_when_raw_mode_was_enabled" {
	TMP_TEST_DIR="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp.XXXXXX")"
	bin_dir="$TMP_TEST_DIR/bin"
	mkdir -p "$bin_dir"
	stty_log="$TMP_TEST_DIR/stty.log"
	cat >"$bin_dir/stty" <<'SH'
#!/usr/bin/env bash
printf "%s\n" "$@" >> "$STTY_LOG"
exit 0
SH
	chmod +x "$bin_dir/stty"
	export STTY_LOG="$stty_log"

	run timeout 5s bash -c "PATH=\"$bin_dir:$PATH\"; source \"${BATS_TEST_DIRNAME}/exit_traps.sh\"; __EXIT_TRAPS_TTY_STATE=\"saved_state_xyz\"; __exit_traps_handler EXIT"
	# ensure our stubbed stty was invoked with the saved state
	grep -q "saved_state_xyz" "$stty_log"
}

@test "unit_cleanup_preserves_existing_nonzero_exit_code_after_running_cleanup" {
	TMP_TEST_DIR="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp.XXXXXX")"
	run timeout 5s bash -c "source \"${BATS_TEST_DIRNAME}/exit_traps.sh\"; __exit_traps_exit_code=7; __exit_traps_handler EXIT"
	[ "$status" -eq 7 ]
}
