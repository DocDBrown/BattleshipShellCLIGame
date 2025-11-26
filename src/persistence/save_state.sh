#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

usage() {
  cat <<'USAGE' >&2
Usage: save_state.sh [--state-dir DIR] [--out /abs/path/file] [--help]
Creates a human-readable save file under the application saves directory.
Exit codes:
  0  success
  2  missing tool/args or required helper
  3  state dir failure or temp file creation/move or checksum validation failure
  4  path validation error
  5  --out must be absolute
USAGE
}

_append() {
  local line="$1"
  if [ -z "${TMPFILE:-}" ]; then
    printf "Internal error: TMPFILE not set\n" >&2
    return 1
  fi
  printf "%s\n" "$line" >>"$TMPFILE"
}

_require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf "Required: %s\n" "$1" >&2
    exit 2
  }
}

_fsync_best_effort() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import os' >/dev/null 2>&1 || true
  fi
}

_locate_and_source_helpers() {
  local this_dir repo_root
  this_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
  if [[ -f "$this_dir/../runtime/paths.sh" || -f "$this_dir/../util/checksum.sh" ]]; then
    repo_root="$this_dir/.."
  elif [[ -f "$this_dir/runtime/paths.sh" || -f "$this_dir/util/checksum.sh" ]]; then
    repo_root="$this_dir"
  else
    repo_root="$this_dir/.."
  fi

  # shellcheck source=/dev/null
  if [[ -f "$repo_root/runtime/paths.sh" ]]; then . "$repo_root/runtime/paths.sh"; fi
  # shellcheck source=/dev/null
  if [[ -f "$repo_root/util/checksum.sh" ]]; then . "$repo_root/util/checksum.sh"; fi
  # shellcheck source=/dev/null
  if [[ -f "$repo_root/model/board_state.sh" ]]; then . "$repo_root/model/board_state.sh"; fi
  # shellcheck source=/dev/null
  if [[ -f "$repo_root/model/ship_rules.sh" ]]; then . "$repo_root/model/ship_rules.sh"; fi
  # shellcheck source=/dev/null
  if [[ -f "$repo_root/game/stats.sh" ]]; then . "$repo_root/game/stats.sh"; fi
}

main() {
  local state_dir="" out_file="" SAVES_DIR

  _locate_and_source_helpers

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)
        if [ "$#" -lt 2 ]; then
          printf "Missing argument for --state-dir\n" >&2
          exit 2
        fi
        state_dir="$2"
        shift 2
        ;;
      --out)
        if [ "$#" -lt 2 ]; then
          printf "Missing argument for --out\n" >&2
          exit 2
        fi
        out_file="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        printf "Unknown argument: %s\n" "$1" >&2
        usage
        exit 2
        ;;
    esac
  done

  _require_cmd mktemp

  if ! command -v bs_path_saves_dir >/dev/null 2>&1; then
    printf "Required helper bs_path_saves_dir not available\n" >&2
    exit 2
  fi

  SAVES_DIR="$(bs_path_saves_dir "${state_dir:-}" 2>/dev/null)" || {
    printf "Failed to determine saves directory\n" >&2
    exit 3
  }
  SAVES_DIR="${SAVES_DIR%/}"
  mkdir -p -- "$SAVES_DIR" 2>/dev/null || true

  if [ -z "${out_file:-}" ]; then
    local ts
    ts="$(date -u +%Y%m%dT%H%M%SZ)"
    out_file="$SAVES_DIR/${ts}.save"
  else
    case "$out_file" in
      /*)
        if [[ "$out_file" != "$SAVES_DIR" && "$out_file" != "$SAVES_DIR/"* ]]; then
          printf "Output path must be inside saves dir: %s\n" "$SAVES_DIR" >&2
          exit 4
        fi
        ;;
      *)
        printf "Output path must be absolute\n" >&2
        exit 5
        ;;
    esac
  fi

  TMPFILE="$(mktemp -p "$SAVES_DIR" ".save.tmp.XXXXXX")" || {
    printf "Failed to create temporary file in saves directory\n" >&2
    exit 3
  }
  chmod 0600 -- "$TMPFILE"
  trap 'rm -f -- "${TMPFILE:-}"' EXIT

  _append "### battleship_shell_script save"
  _append "version: 1"
  _append "generated_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  _append "command_pid: $$"
  _append "service: ${BS_SERVICE:-battleship}"

  _append "### Config"
  _append "board_size: ${BS_BOARD_SIZE:-}"
  _append "board_total_segments: ${BS_BOARD_TOTAL_SEGMENTS:-}"
  _append "board_remaining_segments: ${BS_BOARD_REMAINING_SEGMENTS:-}"

  local size="${BS_BOARD_SIZE:-10}"
  if type bs_board_get_state >/dev/null 2>&1; then
    _append "### Board (cells)"
    _append "rows=${size}"
    _append "cols=${size}"
    local r c state owner
    for ((r = 0; r < size; r++)); do
      for ((c = 0; c < size; c++)); do
        state="$(bs_board_get_state "$r" "$c" 2>/dev/null || true)"
        owner="$(bs_board_get_owner "$r" "$c" 2>/dev/null || true)"
        _append "${r},${c}=${state},${owner}"
      done
    done
  fi

  if type bs_ship_list >/dev/null 2>&1; then
    _append "### Ships"
    local ship
    while IFS= read -r ship; do
      [ -z "$ship" ] && continue
      local length rem hits placed
      length="$(bs_ship_length "$ship" 2>/dev/null || true)"
      rem="$(bs_board_ship_remaining_segments "$ship" 2>/dev/null || true)"
      if [[ "$length" =~ ^[0-9]+$ ]] && [[ "$rem" =~ ^[0-9]+$ ]]; then
        hits=$((length - rem))
        (( hits < 0 )) && hits=0
        placed=$((hits + rem))
      else
        hits=""
        placed=""
      fi
      local name
      name="$(bs_ship_name "$ship" 2>/dev/null || printf '%s' "$ship")"
      _append "ship=${ship} name=${name} length=${length:-} placed=${placed:-} hits=${hits:-} remaining=${rem:-}"
    done < <(bs_ship_list)
  fi

  _append "### Turn History"
  _append "history="

  if type stats_summary_kv >/dev/null 2>&1; then
    _append "### Stats"
    stats_summary_kv >>"$TMPFILE" 2>/dev/null || true
  fi

  _fsync_best_effort "$TMPFILE" || true

  if ! type bs_checksum_file >/dev/null 2>&1; then
    rm -f -- "$TMPFILE"
    printf "Required checksum helper not available\n" >&2
    exit 2
  fi

  local digest
  digest="$(bs_checksum_file "$TMPFILE" 2>/dev/null)" || {
    rm -f -- "$TMPFILE"
    printf "Checksum computation failed\n" >&2
    exit 3
  }

  if printf '%s\n' "$digest" | grep -Eq '^[0-9a-f]{64}$'; then
    :
  else
    rm -f -- "$TMPFILE"
    printf "Invalid checksum produced\n" >&2
    exit 3
  fi

  _append "### Checksum: sha256=${digest}"
  chmod 0600 -- "$TMPFILE" || true

  if ! mv -- "$TMPFILE" "$out_file"; then
    rm -f -- "$TMPFILE"
    printf "Failed to move save into place\n" >&2
    exit 3
  fi
  trap - EXIT

  printf "%s\n" "$out_file"
  return 0
}

main "$@"
exit $?