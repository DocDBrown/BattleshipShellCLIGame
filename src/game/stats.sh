#!/usr/bin/env bash
set -euo pipefail
_STATS_START=0
_STATS_END=0
_total_shots_player=0
_total_shots_ai=0
_hits_player=0
_hits_ai=0
_misses_player=0
_misses_ai=0
_sunk_player=0
_sunk_ai=0

stats_init() {
	_STATS_START=0
	_STATS_END=0
	_total_shots_player=0
	_total_shots_ai=0
	_hits_player=0
	_hits_ai=0
	_misses_player=0
	_misses_ai=0
	_sunk_player=0
	_sunk_ai=0
}

stats_start() {
	_STATS_START=$(date +%s)
}

stats_end() {
	_STATS_END=$(date +%s)
}

_stats_validate_shooter() {
	case "$1" in
	player | ai) return 0 ;;
	*) return 1 ;;
	esac
}

_stats_validate_result() {
	case "$1" in
	hit | miss | sunk) return 0 ;;
	*) return 1 ;;
	esac
}

stats_on_shot() {
	if [ "$#" -ne 2 ]; then return 2; fi
	local shooter result
	shooter="$1"
	result="$2"
	if ! _stats_validate_shooter "$shooter"; then return 3; fi
	if ! _stats_validate_result "$result"; then return 4; fi
	if [ "$shooter" = "player" ]; then
		_total_shots_player=$((_total_shots_player + 1))
		case "$result" in
		hit)
			_hits_player=$((_hits_player + 1))
			;;
		miss)
			_misses_player=$((_misses_player + 1))
			;;
		sunk)
			_hits_player=$((_hits_player + 1))
			_sunk_player=$((_sunk_player + 1))
			;;
		esac
	else
		_total_shots_ai=$((_total_shots_ai + 1))
		case "$result" in
		hit)
			_hits_ai=$((_hits_ai + 1))
			;;
		miss)
			_misses_ai=$((_misses_ai + 1))
			;;
		sunk)
			_hits_ai=$((_hits_ai + 1))
			_sunk_ai=$((_sunk_ai + 1))
			;;
		esac
	fi
	return 0
}

_stats_elapsed_seconds() {
	if [ "$_STATS_START" -eq 0 ]; then
		echo 0
		return 0
	fi
	if [ "$_STATS_END" -ne 0 ]; then
		echo "$((_STATS_END - _STATS_START))"
		return 0
	fi
	local now
	now=$(date +%s)
	echo "$((now - _STATS_START))"
}

_stats_format_duration() {
	local secs mins rem
	secs="$1"
	if [ "$secs" -lt 60 ]; then
		printf "%ds" "$secs"
	else
		mins=$((secs / 60))
		rem=$((secs % 60))
		printf "%dm%02ds" "$mins" "$rem"
	fi
}

_stats_pct() {
	local total hits
	total="$1"
	hits="$2"
	if [ "$total" -le 0 ]; then
		echo "0.00"
		return 0
	fi
	awk -v t="$total" -v h="$hits" 'BEGIN{printf "%.2f", (h/t)*100}'
}

stats_summary_text() {
	local duration dur_readable p_acc a_acc
	duration=$(_stats_elapsed_seconds)
	dur_readable=$(_stats_format_duration "$duration")
	p_acc=$(_stats_pct "$_total_shots_player" "$_hits_player")
	a_acc=$(_stats_pct "$_total_shots_ai" "$_hits_ai")
	printf "Player Shots: %d Hits: %d Misses: %d Sunk: %d Accuracy: %s%%\n" "$_total_shots_player" "$_hits_player" "$_misses_player" "$_sunk_player" "$p_acc"
	printf "AI     Shots: %d Hits: %d Misses: %d Sunk: %d Accuracy: %s%%\n" "$_total_shots_ai" "$_hits_ai" "$_misses_ai" "$_sunk_ai" "$a_acc"
	printf "Duration: %s (%d seconds)\n" "$dur_readable" "$duration"
}

stats_summary_kv() {
	local duration dur_readable p_acc a_acc
	duration=$(_stats_elapsed_seconds)
	dur_readable=$(_stats_format_duration "$duration")
	p_acc=$(_stats_pct "$_total_shots_player" "$_hits_player")
	a_acc=$(_stats_pct "$_total_shots_ai" "$_hits_ai")
	printf "total_shots_player=%d\n" "$_total_shots_player"
	printf "hits_player=%d\n" "$_hits_player"
	printf "misses_player=%d\n" "$_misses_player"
	printf "sunk_ships_player=%d\n" "$_sunk_player"
	printf "accuracy_player_percent=%s\n" "$p_acc"
	printf "total_shots_ai=%d\n" "$_total_shots_ai"
	printf "hits_ai=%d\n" "$_hits_ai"
	printf "misses_ai=%d\n" "$_misses_ai"
	printf "sunk_ships_ai=%d\n" "$_sunk_ai"
	printf "accuracy_ai_percent=%s\n" "$a_acc"
	printf "duration_seconds=%d\n" "$duration"
	printf "duration_readable=%s\n" "$dur_readable"
}

export -f stats_init stats_start stats_end stats_on_shot stats_summary_text stats_summary_kv
