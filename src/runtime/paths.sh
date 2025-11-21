#!/usr/bin/env bash
set -euo pipefail

_bs_normalize() {
	local p="$1"
	if [[ -z "$p" ]]; then return 1; fi
	if [[ "${p#-}" != "$p" ]]; then return 2; fi
	if [[ "$p" != /* ]]; then return 3; fi
	if [[ "$p" == *".."* ]]; then return 4; fi
	while [[ "$p" == *'//'* ]]; do p="$(printf '%s' "$p" | sed ':a; s#//#/#; ta')"; done
	if [[ "$p" != "/" ]]; then p="${p%/}"; fi
	printf '%s' "$p"
}

_bs_make_dir_secure() {
	local d="$1"
	if [[ -z "$d" ]]; then return 1; fi
	if [[ -L "$d" ]]; then return 2; fi
	if [[ -e "$d" && ! -d "$d" ]]; then return 3; fi
	mkdir -p -- "$d"
	chmod 0700 -- "$d"
	return 0
}

_bs_default_state_dir() {
	local p
	if [[ -n "${XDG_STATE_HOME-}" ]]; then p="${XDG_STATE_HOME%/}/battleship"; else p="${HOME%/}/.local/state/battleship"; fi
	_bs_normalize "$p" || printf '%s' "$p"
}

_bs_default_config_dir() {
	local p
	if [[ -n "${XDG_CONFIG_HOME-}" ]]; then p="${XDG_CONFIG_HOME%/}/battleship"; else p="${HOME%/}/.config/battleship"; fi
	_bs_normalize "$p" || printf '%s' "$p"
}

_bs_default_cache_dir() {
	local p
	if [[ -n "${XDG_CACHE_HOME-}" ]]; then p="${XDG_CACHE_HOME%/}/battleship"; else p="${HOME%/}/.cache/battleship"; fi
	_bs_normalize "$p" || printf '%s' "$p"
}

bs_path_state_dir_from_cli() {
	local override="${1-}"
	local dir
	if [[ -n "$override" ]]; then
		dir="$(_bs_normalize "$override")" || return 2
	else
		dir="$(_bs_default_state_dir)"
	fi
	_bs_make_dir_secure "$dir" || return 3
	printf '%s\n' "$dir"
}

bs_path_config_dir_from_cli() {
	local override="${1-}"
	local dir
	if [[ -n "$override" ]]; then
		dir="$(_bs_normalize "$override")" || return 2
	else
		dir="$(_bs_default_config_dir)"
	fi
	_bs_make_dir_secure "$dir" || return 3
	printf '%s\n' "$dir"
}

bs_path_cache_dir_from_cli() {
	local override="${1-}"
	local dir
	if [[ -n "$override" ]]; then
		dir="$(_bs_normalize "$override")" || return 2
	else
		dir="$(_bs_default_cache_dir)"
	fi
	_bs_make_dir_secure "$dir" || return 3
	printf '%s\n' "$dir"
}

bs_path_saves_dir() {
	local state
	state="$(bs_path_state_dir_from_cli "${1-}")" || return 1
	local d="$state/saves"
	_bs_make_dir_secure "$d" || return 2
	printf '%s\n' "$d"
}

bs_path_autosave_file() {
	local state
	state="$(bs_path_state_dir_from_cli "${1-}")" || return 1
	local d="$state/autosaves"
	_bs_make_dir_secure "$d" || return 2
	printf '%s\n' "$d/autosave.sav"
}

bs_path_log_file() {
	local state
	state="$(bs_path_state_dir_from_cli "${1-}")" || return 1
	local d="$state/logs"
	_bs_make_dir_secure "$d" || return 2
	printf '%s\n' "$d/battleship.log"
}
