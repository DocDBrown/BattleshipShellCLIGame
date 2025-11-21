#!/usr/bin/env bash
set -euo pipefail
_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_script_dir/../runtime/paths.sh" || true
BS_SERVICE="${BS_SERVICE:-battleship}"
BS_COMPONENT="${BS_COMPONENT:-logger}"
BS_ENVIRONMENT="${BS_ENVIRONMENT:-production}"
BS_SCHEMA_VERSION="1"
BS_LOG_FILE=""
BS_VERBOSE="${BS_VERBOSE:-0}"
BS_DEBUG_SAMPLE_PERCENT="${BS_DEBUG_SAMPLE_PERCENT:-0}"
BS_LOG_REDACT_FIELDS=("password" "secret" "token" "authorization" "email" "ip" "board" "layout" "chat")
bs_log_init() {
	local override="${1-}"
	local lf
	# Respect explicit verbose toggle: only create log file when enabled
	if [[ "${BS_VERBOSE:-0}" != "1" ]]; then
		BS_LOG_FILE=""
		return 2
	fi
	lf="$(bs_path_log_file "${override:-}" 2>/dev/null || true)"
	if [[ -z "$lf" ]]; then
		BS_LOG_FILE=""
		return 2
	fi
	mkdir -p "$(dirname "$lf")" 2>/dev/null || true
	touch "$lf" 2>/dev/null || {
		BS_LOG_FILE=""
		return 3
	}
	chmod 0600 "$lf" 2>/dev/null || true
	BS_LOG_FILE="$lf"
	return 0
}
_uuid_generate() { if command -v uuidgen >/dev/null 2>&1; then uuidgen; else printf '%s' "$(date +%s%N)-$$-$RANDOM"; fi; }
_json_escape() {
	local s="$1"
	s="${s//\\/\\\\}"
	s="${s//\"/\\\"}"
	s="${s//$'\n'/\\n}"
	s="${s//$'\r'/\\r}"
	s="${s//$'\t'/\\t}"
	printf '%s' "$s"
}
_redact_json_simple() {
	local j="$1"
	local key
	for key in "${BS_LOG_REDACT_FIELDS[@]}"; do
		j="$(printf '%s' "$j" | sed -E "s/(\"$key\"[[:space:]]*:[[:space:]]*)\"([^\"]*)\"/\1\"REDACTED\"/Ig")"
		j="$(printf '%s' "$j" | sed -E "s/(\"$key\"[[:space:]]*:[[:space:]]*)[^,}\]]+/\1\"REDACTED\"/Ig")"
	done
	printf '%s' "$j"
}
_bs_host() { hostname 2>/dev/null || printf '%s' "unknown"; }
_bs_current_time() { date -u +%Y-%m-%dT%H:%M:%SZ; }
_bs_emit() {
	local level="$1"
	shift
	local message_template="${1-}"
	local message_params="${2-}"
	local outcome="${3-}"
	local error_json="${4-}"
	local http_status="${5-}"
	local duration_ms="${6-}"
	local func="${7-}"
	local file="${8-}"
	local line="${9-}"
	local test_run_id="${TEST_RUN_ID:-}"
	if [[ "$level" == "DEBUG" ]]; then
		if [[ "${BS_DEBUG_SAMPLE_PERCENT:-0}" -gt 0 ]]; then if ((RANDOM % 100 >= BS_DEBUG_SAMPLE_PERCENT)); then return 0; fi; else return 0; fi
	fi
	local event_id
	event_id="$(_uuid_generate)"
	local time
	time="$(_bs_current_time)"
	local host
	host="$(_bs_host)"
	local pid="$$"
	local trace_id="${TRACE_ID:-}"
	local span_id="${SPAN_ID:-}"
	local parent_span_id="${PARENT_SPAN_ID:-}"
	local build_id="${BUILD_ID:-}"
	local commit_sha="${COMMIT_SHA:-}"
	local message_params_json="{}"
	if [[ -n "$message_params" ]]; then case "$message_params" in \{* | \[*) message_params_json="$(_redact_json_simple "$message_params")" ;; *)
		local esc
		esc="$(_json_escape "$message_params")"
		message_params_json="\"$esc\""
		;;
	esac fi
	if [[ -n "$error_json" ]]; then error_json="$(_redact_json_simple "$error_json")"; else error_json="null"; fi
	local msg_tmpl_esc
	msg_tmpl_esc="$(_json_escape "$message_template")"
	local func_esc
	func_esc="$(_json_escape "$func")"
	local file_esc
	file_esc="$(_json_escape "$file")"
	local line_esc
	line_esc="$(_json_escape "$line")"
	local test_run_esc
	test_run_esc="$(_json_escape "$test_run_id")"
	local trace_esc
	trace_esc="$(_json_escape "$trace_id")"
	local span_esc
	span_esc="$(_json_escape "$span_id")"
	local parent_span_esc
	parent_span_esc="$(_json_escape "$parent_span_id")"
	local build_esc
	build_esc="$(_json_escape "$build_id")"
	local commit_esc
	commit_esc="$(_json_escape "$commit_sha")"
	local json
	json="{\"time\":\"$time\",\"level\":\"$level\",\"schema_version\":\"$BS_SCHEMA_VERSION\",\"service\":\"$BS_SERVICE\",\"component\":\"$BS_COMPONENT\",\"environment\":\"$BS_ENVIRONMENT\",\"host\":\"$host\",\"pid\":$pid,\"thread\":\"\",\"function\":\"$func_esc\",\"file\":\"$file_esc\",\"line\":\"$line_esc\",\"test_run_id\":\"$test_run_esc\",\"trace_id\":\"$trace_esc\",\"span_id\":\"$span_esc\",\"parent_span_id\":\"$parent_span_esc\",\"build_id\":\"$build_esc\",\"commit_sha\":\"$commit_esc\",\"event_id\":\"$event_id\",\"message_template\":\"$msg_tmpl_esc\",\"message_params\":$message_params_json,\"outcome\":\"$(_json_escape "$outcome")\",\"error\":$error_json,\"http\":{\"status\":$([ -n "$http_status" ] && printf '%s' "$http_status" || printf 'null')},\"duration_ms\":$([ -n "$duration_ms" ] && printf '%s' "$duration_ms" || printf 'null') }"
	if [[ -n "$BS_LOG_FILE" ]]; then
		printf '%s\n' "$json" >>"$BS_LOG_FILE" 2>/dev/null &
		disown
		return 0
	else return 4; fi
}
bs_log_info() {
	local msg="${1-}"
	local params="${2-}"
	bs_log_init "" >/dev/null 2>&1 || true
	if [[ -z "$params" ]]; then params="{}"; fi
	_bs_emit "INFO" "$msg" "$params" "success" "" "" "${FUNCNAME[0]}" "${BASH_SOURCE[1]:-}" "${BASH_LINENO[0]:-}"
}
bs_log_warn() {
	local msg="${1-}"
	local params="${2-}"
	local http_status="${3-}"
	local duration_ms="${4-}"
	bs_log_init "" >/dev/null 2>&1 || true
	_bs_emit "WARN" "$msg" "${params:-}" "failure" "" "${http_status:-}" "${duration_ms:-}" "${FUNCNAME[0]}" "${BASH_SOURCE[1]:-}" "${BASH_LINENO[0]:-}"
}
bs_log_error() {
	local msg="${1-}"
	local params="${2-}"
	local error_json="${3-}"
	local duration_ms="${4-}"
	bs_log_init "" >/dev/null 2>&1 || true
	_bs_emit "ERROR" "$msg" "${params:-}" "failure" "${error_json:-}" "" "${duration_ms:-}" "${FUNCNAME[0]}" "${BASH_SOURCE[1]:-}" "${BASH_LINENO[0]:-}"
}
return 0
