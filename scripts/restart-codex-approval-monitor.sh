#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
fi

USER_NAME="${USER:-user}"
STATE_BASE_DIR="${TMPDIR:-/tmp}"
STATE_BASE_DIR="${STATE_BASE_DIR%/}"
STATE_DIR="${CODEX_ALERT_STATE_DIR:-${STATE_BASE_DIR}/codex-approval-notifier/${USER_NAME}}"
STATE_PREFIX="${CODEX_ALERT_STATE_PREFIX:-codex-approval}"

log() {
  printf '[codex-alert-reset] %s\n' "$*"
}

run_or_echo() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '[dry-run] '
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

collect_pids() {
  local ps_out
  if ! ps_out="$(ps ax -o pid= -o command= 2>/dev/null)"; then
    log "warning: unable to list processes (ps is unavailable in this context)."
    return 0
  fi

  printf '%s\n' "$ps_out" | awk -v self="$$" '
    $1 == 1 {next}
    $1 == self {next}
    /codex-linux-sandbox/ {next}
    /restart-codex-approval-monitor[.]sh/ {next}
    /codex-approval-notifier([.]sh)?([[:space:]]|$)/ {print $1}
    /tail -n0 -F .*\/[.]codex\/log\/codex-tui[.]log/ {print $1}
    /tail -n0 -F .*\/codex-approval-notifier\/[^ ]+\/codex-approval[.]events[.]log/ {print $1}
  ' | awk 'NF {print $1}' | sort -u
}

terminate_pids() {
  local pid
  if [[ "$#" -eq 0 ]]; then
    log "no stale processes found."
    return 0
  fi

  log "terminating $# process(es)..."
  for pid in "$@"; do
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    if kill -0 "$pid" >/dev/null 2>&1; then
      run_or_echo kill "$pid" || true
    fi
  done

  sleep 0.3

  for pid in "$@"; do
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    if kill -0 "$pid" >/dev/null 2>&1; then
      run_or_echo kill -9 "$pid" || true
    fi
  done
}

state_dirs_for() {
  local dir="$1"
  local prefix="$2"
  local base="${dir}/${prefix}"

  printf '%s\n' \
    "${base}.lock" \
    "${base}.monitor_lock"
}

cleanup_state_dir() {
  local dir="$1"
  local prefix="$2"
  local label="$3"
  local -a files=()
  local -a dirs=()
  local path

  log "cleaning ${label} state in ${dir}..."

  while IFS= read -r path; do
    [[ -n "$path" ]] && dirs+=("$path")
  done < <(state_dirs_for "$dir" "$prefix")

  while IFS= read -r path; do
    [[ -n "$path" ]] && files+=("$path")
  done < <(find "$dir" -maxdepth 1 -type f -name "${prefix}.*" -print 2>/dev/null || true)

  if ((${#files[@]} > 0)); then
    run_or_echo rm -f "${files[@]}" || true
  fi
  if ((${#dirs[@]} > 0)); then
    run_or_echo rm -rf "${dirs[@]}" || true
  fi
}

cleanup_empty_state_dir() {
  [[ -d "$STATE_DIR" ]] || return 0
  run_or_echo rmdir "$STATE_DIR" >/dev/null 2>&1 || true
  local parent
  parent="$(dirname "$STATE_DIR")"
  [[ "$parent" == *"/codex-approval-notifier" ]] || return 0
  run_or_echo rmdir "$parent" >/dev/null 2>&1 || true
}

main() {
  local -a pids=()
  local pid

  if [[ "$DRY_RUN" == "1" ]]; then
    log "dry-run mode enabled."
  fi

  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    pids+=("$pid")
  done < <(collect_pids)

  if ((${#pids[@]} > 0)); then
    terminate_pids "${pids[@]}"
  else
    terminate_pids
  fi
  cleanup_state_dir "$STATE_DIR" "$STATE_PREFIX" "current"
  cleanup_empty_state_dir

  log "done."
  log "now open a new Codex session."
}

main "$@"
