#!/usr/bin/env bats

setup() {
	BOARD_STATE_SCRIPT="${BATS_TEST_DIRNAME}/board_state.sh"
}

teardown() {
	:
}

@test "unit: create empty 10x10 grid results in all cells in 'unknown' state and no ship ownership" {
	run bash -c ". \"$BOARD_STATE_SCRIPT\"; \
bs_board_new; \
cnt=0; \
for r in {0..9}; do \
  for c in {0..9}; do \
    s=\$(bs_board_get_state \"\$r\" \"\$c\"); \
    if [ \"\$s\" != \"unknown\" ]; then echo \"bad \$r,\$c \$s\"; exit 2; fi; \
    o=\$(bs_board_get_owner \"\$r\" \"\$c\"); \
    if [ -n \"\$o\" ]; then echo \"owner \$r,\$c \$o\"; exit 3; fi; \
    cnt=\$((cnt+1)); \
  done; \
done; \
echo \"unknown=\$cnt\""
	[ "$status" -eq 0 ]
	[[ "$output" =~ unknown=100 ]]
}

@test "unit: update cell to 'ship' sets cell state to 'ship' and records per-cell owner; repeated updates are idempotent" {
	run bash -c ". \"$BOARD_STATE_SCRIPT\"; \
bs_board_new; \
bs_board_set_ship 0 0 carrier; \
s1=\$(bs_board_get_state 0 0); \
o1=\$(bs_board_get_owner 0 0); \
bs_board_set_ship 0 0 carrier; \
s2=\$(bs_board_get_state 0 0); \
o2=\$(bs_board_get_owner 0 0); \
echo \"s1=\$s1 owner1=\$o1 s2=\$s2 owner2=\$o2\""
	[ "$status" -eq 0 ]
	[[ "$output" =~ s1=ship ]]
	[[ "$output" =~ owner1=carrier ]]
	[[ "$output" =~ s2=ship ]]
}

@test "unit: update cell to 'hit' marks the cell as 'hit', attributes damage to the correct ship owner, and does not alter unrelated cells" {
	run bash -c ". \"$BOARD_STATE_SCRIPT\"; \
bs_board_new; \
bs_board_set_ship 0 0 destroyer; \
bs_board_set_ship 0 1 carrier; \
bs_board_set_hit 0 0; \
s_hit=\$(bs_board_get_state 0 0); \
s_other=\$(bs_board_get_state 0 1); \
rem_destroyer=\$(bs_board_ship_remaining_segments destroyer); \
echo \"s_hit=\$s_hit s_other=\$s_other rem_destroyer=\$rem_destroyer\""
	[ "$status" -eq 0 ]
	[[ "$output" =~ s_hit=hit ]]
	[[ "$output" =~ s_other=ship ]]
	[[ "$output" =~ rem_destroyer=0 ]]
}

@test "unit: update cell to 'miss' marks the cell as 'miss' and leaves per-cell owner unset" {
	run bash -c ". \"$BOARD_STATE_SCRIPT\"; \
bs_board_new; \
bs_board_set_ship 1 1 carrier; \
bs_board_set_miss 2 2; \
s=\$(bs_board_get_state 2 2); \
o=\$(bs_board_get_owner 2 2); \
echo \"s=\$s owner=\\\"\$o\\\"\""
	[ "$status" -eq 0 ]
	[[ "$output" =~ s=miss ]]
	# owner should be empty; output will contain owner=""
	[[ "$output" =~ owner="" ]]
}

@test "unit: sunk detection identifies a ship as sunk when all its owned cells are hit" {
	run bash -c ". \"$BOARD_STATE_SCRIPT\"; \
bs_board_new; \
bs_board_set_ship 0 0 destroyer; \
bs_board_set_ship 0 1 destroyer; \
bs_board_set_hit 0 0; \
bs_board_set_hit 0 1; \
sunk_after=\$(bs_board_ship_is_sunk destroyer); \
win_after=\$(bs_board_is_win); \
echo \"sunk_after=\$sunk_after win_after=\$win_after\""
	[ "$status" -eq 0 ]
	[[ "$output" =~ sunk_after=true ]]
	[[ "$output" =~ win_after=true ]]
}
