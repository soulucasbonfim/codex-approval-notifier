#!/usr/bin/env bash
# shellcheck disable=SC2317
set -euo pipefail

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

CODEX_APPROVAL_NOTIFIER_VERSION="1.0.8"

need_cmd() {
  command_exists "$1" || {
    echo "[codex-alert] missing required command: $1" >&2
    exit 1
  }
}

PLATFORM="${CODEX_ALERT_PLATFORM:-}"
if [[ -z "$PLATFORM" ]]; then
  case "${OSTYPE:-}" in
    darwin*) PLATFORM="darwin" ;;
    linux*) PLATFORM="linux" ;;
    *)
      echo "[codex-alert] unsupported platform: ${OSTYPE:-unknown} (supported: macOS, Linux)" >&2
      exit 1
      ;;
  esac
fi
case "$PLATFORM" in
  darwin|linux) ;;
  *)
    echo "[codex-alert] unsupported platform override: $PLATFORM (supported: darwin, linux)" >&2
    exit 1
    ;;
esac

CODEX_BIN="${CODEX_BIN:-codex}"
ALERT_TITLE="${CODEX_ALERT_TITLE:-Codex}"
ALERT_SUBTITLE="${CODEX_ALERT_SUBTITLE:-Approval pending}"
ALERT_BODY="${CODEX_ALERT_BODY:-Codex is waiting for approve or reject.}"
ALERT_SOUND="${CODEX_ALERT_SOUND:-Funk}"
ALERT_COOLDOWN_SECONDS="${CODEX_ALERT_COOLDOWN_SECONDS:-2}"
ALERT_MIN_GAP_SECONDS="${CODEX_ALERT_MIN_GAP_SECONDS:-1}"
ALERT_REPEAT_SOUND_SECONDS="${CODEX_ALERT_REPEAT_SOUND_SECONDS:-5}"
ALERT_REPEAT_TOAST_SECONDS="${CODEX_ALERT_REPEAT_TOAST_SECONDS:-30}"
ALERT_REMOVE_TOAST_TIMEOUT_SECONDS="${CODEX_ALERT_REMOVE_TOAST_TIMEOUT_SECONDS:-1}"
ALERT_PENDING_TIMEOUT_SECONDS="${CODEX_ALERT_PENDING_TIMEOUT_SECONDS:-30}"
ALERT_PROGRESS_SUPPRESS_SECONDS="${CODEX_ALERT_PROGRESS_SUPPRESS_SECONDS:-0.5}"
ALERT_LOOP_TICK_SECONDS="${CODEX_ALERT_LOOP_TICK_SECONDS:-0.2}"
ALERT_OWNER_CHECK_SECONDS="${CODEX_ALERT_OWNER_CHECK_SECONDS:-1}"
ALERT_EVENT_LOG_MAX_BYTES="${CODEX_ALERT_EVENT_LOG_MAX_BYTES:-1048576}"
ALERT_JANITOR_INTERVAL_SECONDS="${CODEX_ALERT_JANITOR_INTERVAL_SECONDS:-60}"
ALERT_LOCK_STALE_SECONDS="${CODEX_ALERT_LOCK_STALE_SECONDS:-10}"
ALERT_ORPHAN_LOCK_GRACE_SECONDS="${CODEX_ALERT_ORPHAN_LOCK_GRACE_SECONDS:-1}"
ALERT_TOAST_SENDER_BUNDLE_ID="${CODEX_ALERT_TOAST_SENDER_BUNDLE_ID:-}"
ALERT_PLAY_SOUND="${CODEX_ALERT_PLAY_SOUND:-1}"
ALERT_SOUND_FILE="${CODEX_ALERT_SOUND_FILE:-}"
ALERT_NOTIFY_EXPIRE_MS="${CODEX_ALERT_NOTIFY_EXPIRE_MS:-5000}"
ALERT_NOTIFY_URGENCY="${CODEX_ALERT_NOTIFY_URGENCY:-normal}"
ALERT_NOTIFY_TRANSIENT="${CODEX_ALERT_NOTIFY_TRANSIENT:-1}"
ALERT_NOTIFY_CATEGORY="${CODEX_ALERT_NOTIFY_CATEGORY:-im.received}"
ALERT_BACKEND_TIMEOUT_SECONDS="${CODEX_ALERT_BACKEND_TIMEOUT_SECONDS:-2}"
ALERT_LOG_MESSAGES="${CODEX_ALERT_LOG_MESSAGES:-1}"
ALERT_HOOK_PERMISSION_REQUEST_ENABLED="${CODEX_ALERT_HOOK_PERMISSION_REQUEST_ENABLED:-1}"

case "$ALERT_NOTIFY_URGENCY" in
  low|normal|critical) ;;
  *)
    ALERT_NOTIFY_URGENCY="normal"
    ;;
esac
case "$ALERT_NOTIFY_TRANSIENT" in
  0|1) ;;
  *)
    ALERT_NOTIFY_TRANSIENT="1"
    ;;
esac
ALERT_WINDOWS_APP_ID="${CODEX_ALERT_WINDOWS_APP_ID:-Codex}"
ALERT_WINDOWS_SHORTCUT_NAME="${CODEX_ALERT_WINDOWS_SHORTCUT_NAME:-Codex Approval Notifier.lnk}"
ALERT_WINDOWS_NOTIFYICON_FALLBACK="${CODEX_ALERT_WINDOWS_NOTIFYICON_FALLBACK:-1}"
ALERT_WINDOWS_SOUND_ALIAS="${CODEX_ALERT_WINDOWS_SOUND_ALIAS:-SystemNotification}"
ALERT_WINDOWS_SOUND_FILE="${CODEX_ALERT_WINDOWS_SOUND_FILE:-C:\\Windows\\Media\\Speech On.wav}"
CODEX_TUI_LOG_FILE="${CODEX_TUI_LOG_FILE:-$HOME/.codex/log/codex-tui.log}"
CODEX_CONFIG_FILE="${CODEX_CONFIG_FILE:-$HOME/.codex/config.toml}"
ALERT_STATE_BASE_DIR="${TMPDIR:-/tmp}"
ALERT_STATE_BASE_DIR="${ALERT_STATE_BASE_DIR%/}"
ALERT_STATE_DIR="${CODEX_ALERT_STATE_DIR:-${ALERT_STATE_BASE_DIR}/codex-approval-notifier/${USER:-user}}"
ALERT_STATE_PREFIX="${CODEX_ALERT_STATE_PREFIX:-codex-approval}"
ALERT_LOCK_DIR="${ALERT_STATE_DIR}/${ALERT_STATE_PREFIX}.lock"
ALERT_MONITOR_PID_FILE="${ALERT_STATE_DIR}/${ALERT_STATE_PREFIX}.monitor_pid"
ALERT_MONITOR_LOCK_DIR="${ALERT_STATE_DIR}/${ALERT_STATE_PREFIX}.monitor_lock"
ALERT_MONITOR_HEARTBEAT_FILE="${ALERT_STATE_DIR}/${ALERT_STATE_PREFIX}.monitor_heartbeat"
ALERT_MONITOR_HEARTBEAT_STALE_SECONDS="${CODEX_ALERT_MONITOR_HEARTBEAT_STALE_SECONDS:-3}"
ALERT_TOAST_GROUP="${CODEX_ALERT_TOAST_GROUP:-${ALERT_STATE_PREFIX}}"
ALERT_EVENT_LOG_FILE="${ALERT_STATE_DIR}/${ALERT_STATE_PREFIX}.events.log"
ALERT_INSTALLED_PATH="${CODEX_ALERT_INSTALLED_PATH:-${HOME}/.local/bin/codex-approval-notifier}"
HOOK_BEGIN_MARKER="# >>> codex-approval-notifier-hooks >>>"
HOOK_END_MARKER="# <<< codex-approval-notifier-hooks <<<"

if [[ -z "$ALERT_SOUND_FILE" ]]; then
  if [[ "$PLATFORM" == "darwin" ]]; then
    ALERT_SOUND_FILE="/System/Library/Sounds/${ALERT_SOUND}.aiff"
  else
    ALERT_SOUND_FILE="/usr/share/sounds/freedesktop/stereo/message.oga"
  fi
fi

HASH_COMMAND=""
if command_exists sha1sum; then
  HASH_COMMAND="sha1sum"
elif command_exists shasum; then
  HASH_COMMAND="shasum"
elif command_exists openssl; then
  HASH_COMMAND="openssl"
else
  echo "[codex-alert] missing hash command: shasum/sha1sum/openssl" >&2
  exit 1
fi

file_size_bytes() {
  local path="$1"
  stat -f '%z' "$path" 2>/dev/null ||
    stat -c '%s' "$path" 2>/dev/null ||
    wc -c <"$path" 2>/dev/null ||
    echo 0
}

file_mtime_unix() {
  local path="$1"
  stat -f '%m' "$path" 2>/dev/null ||
    stat -c '%Y' "$path" 2>/dev/null ||
    echo 0
}

hash_text() {
  local text="$1"
  if [[ "$HASH_COMMAND" == "openssl" ]]; then
    printf '%s' "$text" | openssl sha1 2>/dev/null | awk '{print $2}'
  else
    printf '%s' "$text" | "$HASH_COMMAND" | awk '{print $1}'
  fi
}

group_key() {
  hash_text "${1:-$ALERT_TOAST_GROUP}"
}

group_state_file() {
  local group="${1:-$ALERT_TOAST_GROUP}"
  local suffix="$2"
  local key
  key="$(group_key "$group")"
  printf '%s/%s.%s.%s' "$ALERT_STATE_DIR" "$ALERT_STATE_PREFIX" "$key" "$suffix"
}

group_lock_dir() {
  local group="${1:-$ALERT_TOAST_GROUP}"
  local key
  key="$(group_key "$group")"
  printf '%s/%s.%s.lock' "$ALERT_STATE_DIR" "$ALERT_STATE_PREFIX" "$key"
}

write_group_state() {
  local group="$1"
  local suffix="$2"
  local value="$3"
  printf '%s' "$value" >"$(group_state_file "$group" "$suffix")" 2>/dev/null || true
}

read_group_state() {
  local group="$1"
  local suffix="$2"
  local path
  path="$(group_state_file "$group" "$suffix")"
  [[ -f "$path" ]] || return 1
  cat "$path" 2>/dev/null || true
}

remove_group_state() {
  local group="$1"
  shift
  local suffix
  for suffix in "$@"; do
    rm -f "$(group_state_file "$group" "$suffix")" >/dev/null 2>&1 || true
  done
}

state_key_from_path() {
  local path="$1"
  local base rest
  base="${path##*/}"
  rest="${base#"${ALERT_STATE_PREFIX}."}"
  printf '%s' "${rest%%.*}"
}

group_from_state_path() {
  local path="$1"
  local key group_file group
  key="$(state_key_from_path "$path")"
  group_file="${ALERT_STATE_DIR}/${ALERT_STATE_PREFIX}.${key}.group"
  group="$(cat "$group_file" 2>/dev/null || true)"
  [[ -n "$group" ]] && printf '%s' "$group"
}

list_groups_with_flag() {
  local flag_suffix="$1"
  local path raw group
  for path in "$ALERT_STATE_DIR"/"${ALERT_STATE_PREFIX}."*".${flag_suffix}"; do
    [[ -e "$path" ]] || break
    raw="$(cat "$path" 2>/dev/null || true)"
    [[ "$raw" == "1" ]] || continue
    group="$(group_from_state_path "$path")"
    [[ -n "$group" ]] && printf '%s\n' "$group"
  done
}

cleanup_group_identity_if_idle() {
  local group="$1"
  if [[ ! -f "$(group_state_file "$group" pending)" ]]; then
    if has_recent_progress "$group" "$ALERT_PROGRESS_SUPPRESS_SECONDS"; then
      return 0
    fi
    remove_group_state "$group" group progress_since
  fi
}

cleanup_idle_group_identities() {
  local path group
  for path in "$ALERT_STATE_DIR"/"${ALERT_STATE_PREFIX}."*".group"; do
    [[ -e "$path" ]] || break
    group="$(cat "$path" 2>/dev/null || true)"
    [[ -n "$group" ]] && cleanup_group_identity_if_idle "$group"
  done
}

clear_all_group_state() {
  local path group
  for path in "$ALERT_STATE_DIR"/"${ALERT_STATE_PREFIX}."*".group"; do
    [[ -e "$path" ]] || break
    group="$(cat "$path" 2>/dev/null || true)"
    [[ -n "$group" ]] && clear_alert_toast "$group"
  done

  shopt -s nullglob
  rm -f "$ALERT_STATE_DIR"/"${ALERT_STATE_PREFIX}."*.pending \
        "$ALERT_STATE_DIR"/"${ALERT_STATE_PREFIX}."*.message \
        "$ALERT_STATE_DIR"/"${ALERT_STATE_PREFIX}."*.ack \
        "$ALERT_STATE_DIR"/"${ALERT_STATE_PREFIX}."*.group \
        "$ALERT_STATE_DIR"/"${ALERT_STATE_PREFIX}."*.pending_since \
        "$ALERT_STATE_DIR"/"${ALERT_STATE_PREFIX}."*.progress_since \
        "$ALERT_STATE_DIR"/"${ALERT_STATE_PREFIX}."*.last_event \
        "$ALERT_STATE_DIR"/"${ALERT_STATE_PREFIX}."*.last_event_key \
        "$ALERT_STATE_DIR"/"${ALERT_STATE_PREFIX}."*.last_sound \
        "$ALERT_STATE_DIR"/"${ALERT_STATE_PREFIX}."*.last_toast \
        "$ALERT_STATE_DIR"/"${ALERT_STATE_PREFIX}."*.next_sound \
        "$ALERT_STATE_DIR"/"${ALERT_STATE_PREFIX}."*.next_toast \
        "$ALERT_STATE_DIR"/"${ALERT_STATE_PREFIX}."*.notify_id \
        >/dev/null 2>&1 || true
  shopt -u nullglob
}

pid_liveness_status() {
  local pid="$1"
  local out ps_out
  [[ "$pid" =~ ^[0-9]+$ ]] || {
    printf 'invalid'
    return 0
  }
  if out="$(kill -0 "$pid" 2>&1)"; then
    ps_out="$(ps -p "$pid" -o stat= 2>/dev/null | awk 'NR == 1 {print $1}' || true)"
    case "$ps_out" in
      *Z*)
        printf 'dead'
        return 0
        ;;
    esac
    printf 'alive'
    return 0
  fi
  case "$out" in
    *[Oo]peration\ not\ permitted*)
      # EPERM means the process exists, but this shell is not allowed to signal it.
      printf 'alive-permission-denied'
      return 0
      ;;
  esac
  if ps -p "$pid" >/dev/null 2>&1; then
    printf 'alive'
    return 0
  fi
  ps_out="$(ps -p "$pid" 2>&1 >/dev/null || true)"
  case "$ps_out" in
    *[Oo]peration\ not\ permitted*)
      printf 'unknown-permission-denied'
      return 0
      ;;
  esac
  printf 'dead'
}

is_pid_alive() {
  local status
  status="$(pid_liveness_status "$1")"
  case "$status" in
    alive|alive-permission-denied) return 0 ;;
    *) return 1 ;;
  esac
}

child_pids_of() {
  local parent_pid="$1"
  local pids
  if command_exists pgrep; then
    pids="$(pgrep -P "$parent_pid" 2>/dev/null || true)"
    if [[ -n "$pids" ]]; then
      printf '%s\n' "$pids"
      return 0
    fi
  fi
  ps ax -o pid= -o ppid= 2>/dev/null | awk -v parent="$parent_pid" '$2 == parent {print $1}' || true
}

terminate_child_tree() {
  local parent_pid="$1"
  local child
  while IFS= read -r child; do
    [[ "$child" =~ ^[0-9]+$ ]] || continue
    terminate_child_tree "$child"
    kill "$child" >/dev/null 2>&1 || true
  done < <(child_pids_of "$parent_pid")
}

lock_owner_pid() {
  local lock_dir="$1"
  local owner_file="${lock_dir}/owner"
  [[ -f "$owner_file" ]] || return 1
  cat "$owner_file" 2>/dev/null || true
}

lock_should_be_reclaimed() {
  local lock_dir="$1"
  local owner now lock_mtime

  [[ -d "$lock_dir" ]] || return 1

  owner="$(lock_owner_pid "$lock_dir" 2>/dev/null || true)"
  if [[ -n "$owner" ]]; then
    if ! is_pid_alive "$owner"; then
      return 0
    fi
  fi

  lock_mtime="$(file_mtime_unix "$lock_dir")"
  now="$(date +%s)"
  [[ "$lock_mtime" =~ ^[0-9]+$ ]] || return 1

  if [[ -z "$owner" ]] && (( ALERT_ORPHAN_LOCK_GRACE_SECONDS >= 0 )) && (( now - lock_mtime >= ALERT_ORPHAN_LOCK_GRACE_SECONDS )); then
    return 0
  fi

  if (( ALERT_LOCK_STALE_SECONDS > 0 )) && (( now - lock_mtime >= ALERT_LOCK_STALE_SECONDS )); then
    return 0
  fi

  return 1
}

reclaim_lock_if_needed() {
  local lock_dir="$1"
  if lock_should_be_reclaimed "$lock_dir"; then
    rm -rf "$lock_dir" >/dev/null 2>&1 || true
    return 0
  fi
  return 1
}

format_pid_status() {
  local status="$1"
  case "$status" in
    alive) printf 'alive' ;;
    alive-permission-denied) printf 'alive (permission denied)' ;;
    unknown-permission-denied) printf 'unknown (permission denied)' ;;
    invalid) printf 'invalid pid' ;;
    *) printf 'not running' ;;
  esac
}

format_bytes() {
  local bytes="$1"
  awk -v b="$bytes" 'BEGIN {
    if (b !~ /^[0-9]+$/) b = 0;
    printf "%d bytes (%.3f MB)", b, b / 1048576;
  }'
}

print_cmd_status() {
  local cmd="$1"
  if command_exists "$cmd"; then
    printf '  %-22s ok (%s)\n' "$cmd" "$(command -v "$cmd")"
  else
    printf '  %-22s missing\n' "$cmd"
  fi
}

cmd_help_contains() {
  local cmd="$1"
  local needle="$2"
  local help
  command_exists "$cmd" || return 1
  help="$("$cmd" --help 2>&1 || true)"
  [[ "$help" == *"$needle"* ]]
}

notify_send_supports() {
  local feature="$1"
  cmd_help_contains notify-send "$feature"
}

is_wsl() {
  local release version release_lc version_lc
  case "${CODEX_ALERT_WSL:-}" in
    1|true|yes) return 0 ;;
    0|false|no) return 1 ;;
  esac
  release="$(cat /proc/sys/kernel/osrelease 2>/dev/null || true)"
  version="$(cat /proc/version 2>/dev/null || true)"
  release_lc="$(printf '%s' "$release" | tr '[:upper:]' '[:lower:]')"
  version_lc="$(printf '%s' "$version" | tr '[:upper:]' '[:lower:]')"
  [[ "$release_lc" == *microsoft* || "$release_lc" == *wsl* || "$version_lc" == *microsoft* || "$version_lc" == *wsl* ]]
}

resolve_notification_backend() {
  if [[ "$PLATFORM" == "darwin" ]]; then
    if command_exists terminal-notifier; then
      printf 'terminal-notifier'
      return 0
    fi
    if command_exists osascript; then
      printf 'osascript'
      return 0
    fi
  else
    if is_wsl; then
      if command_exists powershell.exe && command_exists iconv && command_exists base64; then
        printf 'windows-toast'
      else
        printf 'none'
      fi
      return 0
    fi
    if command_exists notify-send; then
      printf 'notify-send'
      return 0
    fi
    if command_exists zenity; then
      printf 'zenity'
      return 0
    fi
    if command_exists kdialog; then
      printf 'kdialog'
      return 0
    fi
  fi
  printf 'none'
}

aplay_file_supported() {
  local sound_file="$1"
  local lower
  lower="${sound_file,,}"
  case "$lower" in
    *.wav|*.au|*.voc) return 0 ;;
  esac
  return 1
}

resolve_sound_backend() {
  [[ "$ALERT_PLAY_SOUND" == "1" ]] || {
    printf 'disabled'
    return 0
  }
  if is_wsl && [[ "$(resolve_notification_backend)" == "windows-toast" ]]; then
    printf 'windows-sound'
    return 0
  fi
  if [[ "$PLATFORM" == "darwin" ]]; then
    if command_exists afplay && [[ -f "$ALERT_SOUND_FILE" ]]; then
      printf 'afplay'
      return 0
    fi
  else
    if command_exists paplay && [[ -f "$ALERT_SOUND_FILE" ]]; then
      printf 'paplay'
      return 0
    fi
    if command_exists canberra-gtk-play; then
      printf 'canberra-gtk-play'
      return 0
    fi
    if command_exists aplay && [[ -f "$ALERT_SOUND_FILE" ]] && aplay_file_supported "$ALERT_SOUND_FILE"; then
      printf 'aplay'
      return 0
    fi
  fi
  printf 'terminal-bell'
}

print_notify_send_capabilities() {
  command_exists notify-send || return 0
  printf '  %-22s %s\n' "notify --replace-id" "$(notify_send_supports '--replace-id' && printf yes || printf no)"
  printf '  %-22s %s\n' "notify --print-id" "$(notify_send_supports '--print-id' && printf yes || printf no)"
  printf '  %-22s %s\n' "notify --app-name" "$(notify_send_supports '--app-name' && printf yes || printf no)"
  printf '  %-22s %s\n' "notify --category" "$(notify_send_supports '--category' && printf yes || printf no)"
  printf '  %-22s %s\n' "notify --expire-time" "$(notify_send_supports '--expire-time' && printf yes || printf no)"
  printf '  %-22s %s\n' "notify --transient" "$(notify_send_supports '--transient' && printf yes || printf no)"
}

print_file_status() {
  local label="$1"
  local path="$2"
  local size
  if [[ -e "$path" ]]; then
    size="$(file_size_bytes "$path")"
    printf '  %-22s %s [%s]\n' "$label" "$path" "$(format_bytes "$size")"
  else
    printf '  %-22s %s [missing]\n' "$label" "$path"
  fi
}

print_installed_notifier_status() {
  local path="$ALERT_INSTALLED_PATH"
  local version=""
  if [[ -x "$path" ]]; then
    version="$("$path" --version 2>/dev/null | head -n1 || true)"
    if [[ -n "$version" ]]; then
      printf '  %-22s %s [%s]\n' "installed notifier" "$path" "$version"
    else
      printf '  %-22s %s [executable]\n' "installed notifier" "$path"
    fi
  elif [[ -e "$path" ]]; then
    printf '  %-22s %s [not executable]\n' "installed notifier" "$path"
  else
    printf '  %-22s %s [missing]\n' "installed notifier" "$path"
  fi
}

toml_single_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/''/g")"
}

remove_managed_hook_block() {
  local path="$1"
  local tmp
  [[ -f "$path" ]] || return 0
  tmp="${path}.codex-alert.tmp.$$"
  awk -v begin="$HOOK_BEGIN_MARKER" -v end="$HOOK_END_MARKER" '
    $0 == begin {skip=1; next}
    $0 == end {skip=0; next}
    !skip {print}
  ' "$path" >"$tmp"
  mv "$tmp" "$path"
}

ensure_hooks_feature() {
  local path="$1"
  local tmp
  tmp="${path}.codex-alert.tmp.$$"

  awk '
    BEGIN { in_features=0; saw_features=0; saw_hooks=0 }
    /^\[features\][[:space:]]*$/ {
      if (in_features && !saw_hooks) print "hooks = true";
      in_features=1;
      saw_features=1;
      saw_hooks=0;
      print;
      next;
    }
    /^\[/ {
      if (in_features && !saw_hooks) print "hooks = true";
      in_features=0;
      print;
      next;
    }
    in_features && /^[[:space:]]*(codex_hooks|hooks)[[:space:]]*=/ {
      print "hooks = true";
      saw_hooks=1;
      next;
    }
    { print }
    END {
      if (in_features && !saw_hooks) print "hooks = true";
      if (!saw_features) {
        print "";
        print "[features]";
        print "hooks = true";
      }
    }
  ' "$path" >"$tmp"
  mv "$tmp" "$path"
}

append_codex_hook_block() {
  local path="$1"
  local hook_command
  hook_command="$(toml_single_quote "${ALERT_INSTALLED_PATH} --hook-permission-request")"
  cat >>"$path" <<EOF

${HOOK_BEGIN_MARKER}
[[hooks.PermissionRequest]]
matcher = "^Bash$"

[[hooks.PermissionRequest.hooks]]
type = "command"
command = ${hook_command}
timeout = 2
statusMessage = "Notify approval request"
${HOOK_END_MARKER}
EOF
}

validate_codex_hook_config() {
  [[ -f "$CODEX_CONFIG_FILE" ]] || return 1
  grep -Eq '^[[:space:]]*hooks[[:space:]]*=[[:space:]]*true[[:space:]]*$' "$CODEX_CONFIG_FILE" || return 1
  grep -Fq '[[hooks.PermissionRequest]]' "$CODEX_CONFIG_FILE" || return 1
  grep -Fq "${ALERT_INSTALLED_PATH} --hook-permission-request" "$CODEX_CONFIG_FILE" || return 1
}

install_hook_command() {
  mkdir -p "$(dirname "$CODEX_CONFIG_FILE")"
  touch "$CODEX_CONFIG_FILE"
  cp "$CODEX_CONFIG_FILE" "${CODEX_CONFIG_FILE}.codex-alert.bak.$(date +%Y%m%d-%H%M%S)"
  remove_managed_hook_block "$CODEX_CONFIG_FILE"
  ensure_hooks_feature "$CODEX_CONFIG_FILE"
  append_codex_hook_block "$CODEX_CONFIG_FILE"
  printf 'installed PermissionRequest hook in %s\n' "$CODEX_CONFIG_FILE"
}

uninstall_hook_command() {
  if [[ ! -f "$CODEX_CONFIG_FILE" ]]; then
    printf 'Codex config not found: %s\n' "$CODEX_CONFIG_FILE"
    return 0
  fi
  cp "$CODEX_CONFIG_FILE" "${CODEX_CONFIG_FILE}.codex-alert.bak.$(date +%Y%m%d-%H%M%S)"
  remove_managed_hook_block "$CODEX_CONFIG_FILE"
  printf 'removed managed PermissionRequest hook from %s\n' "$CODEX_CONFIG_FILE"
}

process_snapshot() {
  ps ax -o pid= -o command= 2>/dev/null || true
}

process_count_for_pattern() {
  local snapshot="$1"
  local pattern="$2"
  if [[ -z "$snapshot" ]]; then
    printf 'unavailable'
    return 0
  fi
  printf '%s\n' "$snapshot" | awk -v self="$$" -v pattern="$pattern" '
    $1 == self {next}
    $0 ~ pattern {count++}
    END {print count + 0}
  '
}

print_process_count() {
  local label="$1"
  local pattern="$2"
  local snapshot="$3"
  printf '  %-22s %s\n' "$label" "$(process_count_for_pattern "$snapshot" "$pattern")"
}

show_usage() {
  cat <<'EOF'
Usage:
  codex-approval-notifier.sh [codex args...]
  codex-approval-notifier.sh --hook-permission-request
  codex-approval-notifier.sh --doctor
  codex-approval-notifier.sh --status
  codex-approval-notifier.sh --self-test [message]
  codex-approval-notifier.sh --backend-test
  codex-approval-notifier.sh --clear
  codex-approval-notifier.sh --install-hook
  codex-approval-notifier.sh --uninstall-hook
  codex-approval-notifier.sh --install-windows-toast
  codex-approval-notifier.sh --uninstall-windows-toast
  codex-approval-notifier.sh --start-monitor
  codex-approval-notifier.sh --tail-events
  codex-approval-notifier.sh --version
  codex-approval-notifier.sh --help

Environment:
  CODEX_ALERT_STATE_DIR=path             Default: ${TMPDIR:-/tmp}/codex-approval-notifier/$USER
  CODEX_ALERT_PLAY_SOUND=0|1             Default: 1
  CODEX_ALERT_NOTIFY_EXPIRE_MS=ms        Default: 5000
  CODEX_ALERT_NOTIFY_URGENCY=level       Default: normal
  CODEX_ALERT_NOTIFY_TRANSIENT=0|1       Default: 1
  CODEX_ALERT_BACKEND_TIMEOUT_SECONDS     Default: 2
  CODEX_ALERT_LOG_MESSAGES=0|1           Default: 1
  CODEX_ALERT_HOOK_PERMISSION_REQUEST_ENABLED=0|1  Default: 1
  CODEX_ALERT_WINDOWS_APP_ID=id        Default: Codex
  CODEX_ALERT_WINDOWS_SHORTCUT_NAME=name.lnk
  CODEX_ALERT_PROGRESS_SUPPRESS_SECONDS  Default: 0.5
  CODEX_ALERT_OWNER_CHECK_SECONDS         Default: 1
EOF
}

show_version() {
  printf 'codex-approval-notifier %s\n' "$CODEX_APPROVAL_NOTIFIER_VERSION"
  printf 'mode: permission-request-hook+tui-log-clear\n'
}

doctor() {
  local size pid state_files pending_groups snapshot
  local notification_backend sound_backend exit_code
  exit_code=0
  notification_backend="$(resolve_notification_backend)"
  sound_backend="$(resolve_sound_backend)"
  printf 'codex-approval-notifier doctor\n'
  printf 'version: %s\n' "$CODEX_APPROVAL_NOTIFIER_VERSION"
  printf 'platform: %s\n' "$PLATFORM"
  printf 'mode: permission-request-hook+tui-log-clear\n'
  printf 'hook_permission_request_enabled: %s\n' "$ALERT_HOOK_PERMISSION_REQUEST_ENABLED"
  printf 'state_dir: %s\n' "$ALERT_STATE_DIR"
  printf 'state_prefix: %s\n' "$ALERT_STATE_PREFIX"
  printf 'codex_config: %s\n' "$CODEX_CONFIG_FILE"
  printf 'tui_log: %s\n' "$CODEX_TUI_LOG_FILE"
  printf 'event_log: %s\n' "$ALERT_EVENT_LOG_FILE"
  printf 'progress_suppress_seconds: %s\n' "$ALERT_PROGRESS_SUPPRESS_SECONDS"
  printf 'orphan_lock_grace_seconds: %s\n' "$ALERT_ORPHAN_LOCK_GRACE_SECONDS"
  printf 'remove_toast_timeout_seconds: %s\n' "$ALERT_REMOVE_TOAST_TIMEOUT_SECONDS"
  printf 'notification_backend: %s\n' "$notification_backend"
  printf 'sound_backend: %s\n' "$sound_backend"
  if is_wsl; then
    printf 'windows_app_id: %s\n' "$ALERT_WINDOWS_APP_ID"
    printf 'windows_shortcut: %s\n' "$(windows_toast_shortcut_ps_path || true)"
    printf 'windows_sound_alias: %s\n' "$ALERT_WINDOWS_SOUND_ALIAS"
    printf 'windows_sound_file: %s\n' "$ALERT_WINDOWS_SOUND_FILE"
  fi
  printf '\ncommands:\n'
  print_cmd_status "$CODEX_BIN"
  print_cmd_status tail
  print_cmd_status sed
  print_cmd_status awk
  print_cmd_status perl
  print_cmd_status dd
  print_cmd_status jq
  print_cmd_status "$HASH_COMMAND"
  if [[ "$PLATFORM" == "darwin" ]]; then
    print_cmd_status terminal-notifier
    print_cmd_status osascript
    print_cmd_status afplay
  else
    print_cmd_status notify-send
    print_cmd_status zenity
    print_cmd_status kdialog
    print_cmd_status powershell.exe
    print_cmd_status iconv
    print_cmd_status base64
    print_cmd_status paplay
    print_cmd_status aplay
    print_cmd_status canberra-gtk-play
  fi
  if [[ "$PLATFORM" == "linux" ]]; then
    printf '\nnotify-send capabilities:\n'
    print_notify_send_capabilities
  fi
  printf '\nbackend health:\n'
  if [[ "$notification_backend" == "none" ]]; then
    printf '  %-22s error: no visual notification backend found\n' "notification"
    if [[ "$PLATFORM" == "darwin" ]]; then
      printf '  %-22s install terminal-notifier or use built-in osascript\n' "hint"
    else
      printf '  %-22s install libnotify-bin/libnotify, zenity, or kdialog\n' "hint"
    fi
    exit_code=1
  else
    printf '  %-22s ok (%s)\n' "notification" "$notification_backend"
    if is_wsl; then
      ensure_windows_toast_installed >/dev/null 2>&1 || true
      if windows_toast_shortcut_exists; then
        printf '  %-22s ok (%s)\n' "windows app id" "$ALERT_WINDOWS_APP_ID"
      elif windows_toast_app_installed; then
        printf '  %-22s available, shortcut auto-install failed\n' "windows app id"
      else
        printf '  %-22s unavailable; using NotifyIcon fallback\n' "windows app id"
      fi
    fi
  fi
  if [[ "$ALERT_PLAY_SOUND" == "1" ]]; then
    if [[ "$sound_backend" == "terminal-bell" ]]; then
      printf '  %-22s warning: using terminal bell fallback\n' "sound"
    else
      printf '  %-22s ok (%s)\n' "sound" "$sound_backend"
    fi
  else
    printf '  %-22s disabled\n' "sound"
  fi
  printf '\nhook health:\n'
  if validate_codex_hook_config; then
    printf '  %-22s ok\n' "PermissionRequest"
  else
    printf '  %-22s error: hook is not configured for %s\n' "PermissionRequest" "$ALERT_INSTALLED_PATH"
    printf '  %-22s run: codex-approval-notifier --install-hook\n' "hint"
    exit_code=1
  fi
  printf '\nfiles:\n'
  print_installed_notifier_status
  print_file_status "codex tui log" "$CODEX_TUI_LOG_FILE"
  print_file_status "event log" "$ALERT_EVENT_LOG_FILE"
  print_file_status "monitor pid" "$ALERT_MONITOR_PID_FILE"
  print_file_status "alert lock" "$ALERT_LOCK_DIR"
  print_file_status "monitor lock" "$ALERT_MONITOR_LOCK_DIR"
  if [[ -f "$ALERT_MONITOR_PID_FILE" ]]; then
    pid="$(cat "$ALERT_MONITOR_PID_FILE" 2>/dev/null || true)"
    printf '  %-22s %s [%s]\n' "monitor process" "${pid:-unknown}" "$(format_pid_status "$(pid_liveness_status "$pid")")"
  fi
  pending_groups="$(find "$ALERT_STATE_DIR" -maxdepth 1 -name "${ALERT_STATE_PREFIX}.*.pending" 2>/dev/null | wc -l | tr -d ' ')"
  printf '  %-22s %s\n' "pending groups" "${pending_groups:-0}"
  state_files="$(find "$ALERT_STATE_DIR" -maxdepth 1 -name "${ALERT_STATE_PREFIX}*" 2>/dev/null | wc -l | tr -d ' ')"
  printf '  %-22s %s\n' "state files" "${state_files:-0}"
  if [[ -d "$ALERT_STATE_DIR" ]]; then
    size="$(du -sk "$ALERT_STATE_DIR" 2>/dev/null | awk '{print $1 * 1024}' || echo 0)"
    printf '  %-22s %s\n' "state dir size" "$(format_bytes "$size")"
  fi
  snapshot="$(process_snapshot)"
  printf '\nprocesses:\n'
  print_process_count "notifier wrappers" 'codex-approval-notifier([.]sh)?([[:space:]]|$)' "$snapshot"
  print_process_count "stale tui tails" 'tail -n0 -F .*/[.]codex/log/codex-tui[.]log' "$snapshot"
  return "$exit_code"
}

status_command() {
  local notification_backend sound_backend pid pending_groups state_files size monitor_status hook_status
  notification_backend="$(resolve_notification_backend)"
  sound_backend="$(resolve_sound_backend)"
  pending_groups="$(find "$ALERT_STATE_DIR" -maxdepth 1 -name "${ALERT_STATE_PREFIX}.*.pending" 2>/dev/null | wc -l | tr -d ' ')"
  state_files="$(find "$ALERT_STATE_DIR" -maxdepth 1 -name "${ALERT_STATE_PREFIX}*" 2>/dev/null | wc -l | tr -d ' ')"
  if [[ -d "$ALERT_STATE_DIR" ]]; then
    size="$(du -sk "$ALERT_STATE_DIR" 2>/dev/null | awk '{print $1 * 1024}' || echo 0)"
  else
    size=0
  fi
  pid=""
  monitor_status="not running"
  if [[ -f "$ALERT_MONITOR_PID_FILE" ]]; then
    pid="$(cat "$ALERT_MONITOR_PID_FILE" 2>/dev/null || true)"
    monitor_status="$(format_pid_status "$(pid_liveness_status "$pid")")"
  fi
  if validate_codex_hook_config; then
    hook_status="ok"
  else
    hook_status="missing"
  fi

  printf 'codex-approval-notifier %s\n' "$CODEX_APPROVAL_NOTIFIER_VERSION"
  printf 'platform=%s mode=permission-request-hook+tui-log-clear hook_permission_request_enabled=%s hook_status=%s\n' "$PLATFORM" "$ALERT_HOOK_PERMISSION_REQUEST_ENABLED" "$hook_status"
  printf 'notification_backend=%s sound_backend=%s\n' "$notification_backend" "$sound_backend"
  printf 'monitor_pid=%s monitor_status=%s\n' "${pid:-none}" "$monitor_status"
  printf 'pending_groups=%s state_files=%s\n' "${pending_groups:-0}" "${state_files:-0}"
  printf 'state_dir=%s\n' "$ALERT_STATE_DIR"
  printf 'state_dir_size=%s\n' "$(format_bytes "$size")"
  printf 'event_log=%s\n' "$ALERT_EVENT_LOG_FILE"
}

clear_command() {
  mkdir -p "$ALERT_STATE_DIR" >/dev/null 2>&1 || true
  clear_all_group_state
  append_event_log "clear_command: cleared notifier state"
  printf 'cleared notifier pending state in %s\n' "$ALERT_STATE_DIR"
}

self_test_command() {
  local message="${1:-Codex Approval Notifier self-test}"
  local group="${ALERT_TOAST_GROUP}-self-test"
  local notification_backend sound_backend
  mkdir -p "$ALERT_STATE_DIR" >/dev/null 2>&1 || true
  notification_backend="$(resolve_notification_backend)"
  sound_backend="$(resolve_sound_backend)"
  if [[ "$notification_backend" == "none" ]]; then
    printf 'self-test failed: no visual notification backend available\n' >&2
    return 1
  fi
  append_event_log "self_test: notification_backend=${notification_backend} sound_backend=${sound_backend}"
  notify_approval "$message" "$group"
  printf 'self-test sent: notification_backend=%s sound_backend=%s\n' "$notification_backend" "$sound_backend"
}

tail_events_command() {
  mkdir -p "$ALERT_STATE_DIR" >/dev/null 2>&1 || true
  touch "$ALERT_EVENT_LOG_FILE"
  printf 'tailing %s\n' "$ALERT_EVENT_LOG_FILE" >&2
  tail -f "$ALERT_EVENT_LOG_FILE"
}

backend_check() {
  local label="$1"
  shift
  if "$@"; then
    printf '  %-22s ok\n' "$label"
    return 0
  fi
  printf '  %-22s failed\n' "$label"
  return 1
}

backend_skip() {
  local label="$1"
  local reason="$2"
  printf '  %-22s skipped (%s)\n' "$label" "$reason"
}

ring_terminal_bell() {
  if [[ -t 2 ]]; then
    printf '\a' >&2
    return 0
  fi
  if [[ -t 1 ]]; then
    printf '\a' >&1
    return 0
  fi
  if tty -s 2>/dev/null; then
    printf '\a' >/dev/tty 2>/dev/null || true
  fi
  return 0
}

sound_backend_check() {
  local backend="$1"
  case "$backend" in
    afplay)
      command_exists afplay && [[ -f "$ALERT_SOUND_FILE" ]] && run_with_timeout "$ALERT_BACKEND_TIMEOUT_SECONDS" afplay "$ALERT_SOUND_FILE"
      ;;
    paplay)
      command_exists paplay && [[ -f "$ALERT_SOUND_FILE" ]] && run_with_timeout "$ALERT_BACKEND_TIMEOUT_SECONDS" paplay "$ALERT_SOUND_FILE"
      ;;
    canberra-gtk-play)
      command_exists canberra-gtk-play && run_with_timeout "$ALERT_BACKEND_TIMEOUT_SECONDS" canberra-gtk-play -i message
      ;;
    aplay)
      command_exists aplay && [[ -f "$ALERT_SOUND_FILE" ]] && aplay_file_supported "$ALERT_SOUND_FILE" && run_with_timeout "$ALERT_BACKEND_TIMEOUT_SECONDS" aplay -q "$ALERT_SOUND_FILE"
      ;;
    windows-sound)
      command_exists powershell.exe && run_with_timeout "$ALERT_BACKEND_TIMEOUT_SECONDS" powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "\$sound = '${ALERT_WINDOWS_SOUND_FILE//\'/\'\'}'; Add-Type -MemberDefinition '[DllImport(\"winmm.dll\", SetLastError=true)] public static extern bool PlaySound(string pszSound, System.IntPtr hmod, uint fdwSound);' -Name WinMM -Namespace CodexApprovalNotifier; [CodexApprovalNotifier.WinMM]::PlaySound(\$sound, [IntPtr]::Zero, 0x00020000) | Out-Null"
      ;;
    terminal-bell)
      ring_terminal_bell
      ;;
    *)
      return 1
      ;;
  esac
}

windows_toast_backend_check() {
  is_wsl && command_exists powershell.exe && command_exists iconv && command_exists base64
}

backend_test_command() {
  local failures=0
  local group="${ALERT_TOAST_GROUP}-backend-test"
  local message="Codex Approval Notifier backend test"
  mkdir -p "$ALERT_STATE_DIR" >/dev/null 2>&1 || true

  printf 'visual backends:\n'
  if [[ "$PLATFORM" == "darwin" ]]; then
    if command_exists terminal-notifier; then
      backend_check terminal-notifier send_macos_terminal_notifier "$message: terminal-notifier" "$group-terminal-notifier" 0 || failures=$((failures + 1))
    else
      backend_skip terminal-notifier missing
    fi
    if command_exists osascript; then
      backend_check osascript send_macos_osascript "$message: osascript" "$group-osascript" 0 || failures=$((failures + 1))
    else
      backend_skip osascript missing
    fi
  else
    if is_wsl; then
      if windows_toast_backend_check; then
        backend_check windows-toast send_windows_toast "$message: windows-toast" "$group-windows-toast" || failures=$((failures + 1))
      else
        backend_skip windows-toast unavailable
        failures=$((failures + 1))
      fi
    else
      if command_exists notify-send; then
        backend_check notify-send send_linux_notify_send "$message: notify-send" "$group-notify-send" || failures=$((failures + 1))
      else
        backend_skip notify-send missing
      fi
      if command_exists zenity; then
        backend_check zenity send_linux_zenity "$message: zenity" "$group-zenity" || failures=$((failures + 1))
      else
        backend_skip zenity missing
      fi
      if command_exists kdialog; then
        backend_check kdialog send_linux_kdialog "$message: kdialog" "$group-kdialog" || failures=$((failures + 1))
      else
        backend_skip kdialog missing
      fi
    fi
  fi

  printf 'sound backends:\n'
  if [[ "$PLATFORM" == "darwin" ]]; then
    if command_exists afplay && [[ -f "$ALERT_SOUND_FILE" ]]; then
      backend_check afplay sound_backend_check afplay || failures=$((failures + 1))
    else
      backend_skip afplay "missing command or sound file"
    fi
    backend_check terminal-bell sound_backend_check terminal-bell || failures=$((failures + 1))
  else
    if is_wsl && [[ "$(resolve_sound_backend)" == "windows-sound" ]]; then
      backend_check windows-sound sound_backend_check windows-sound || failures=$((failures + 1))
    else
      if command_exists paplay && [[ -f "$ALERT_SOUND_FILE" ]]; then
        backend_check paplay sound_backend_check paplay || failures=$((failures + 1))
      else
        backend_skip paplay "missing command or sound file"
      fi
      if command_exists canberra-gtk-play; then
        backend_check canberra-gtk-play sound_backend_check canberra-gtk-play || failures=$((failures + 1))
      else
        backend_skip canberra-gtk-play missing
      fi
      if command_exists aplay && [[ -f "$ALERT_SOUND_FILE" ]] && aplay_file_supported "$ALERT_SOUND_FILE"; then
        backend_check aplay sound_backend_check aplay || failures=$((failures + 1))
      else
        backend_skip aplay "missing command or unsupported sound file"
      fi
      backend_check terminal-bell sound_backend_check terminal-bell || failures=$((failures + 1))
    fi
  fi

  append_event_log "backend_test: failures=${failures}"
  if (( failures > 0 )); then
    return 1
  fi
  return 0
}

acquire_monitor_lock() {
  local attempts=0
  while ! mkdir "$ALERT_MONITOR_LOCK_DIR" >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if (( attempts % 20 == 0 )); then
      reclaim_lock_if_needed "$ALERT_MONITOR_LOCK_DIR" || true
    fi
    if (( attempts >= 300 )); then
      return 1
    fi
    sleep 0.01
  done
  printf '%s' "${BASHPID:-$$}" >"${ALERT_MONITOR_LOCK_DIR}/owner" 2>/dev/null || true
}

release_monitor_lock() {
  local owner=""
  if [[ -f "${ALERT_MONITOR_LOCK_DIR}/owner" ]]; then
    owner="$(cat "${ALERT_MONITOR_LOCK_DIR}/owner" 2>/dev/null || true)"
    [[ -z "$owner" || "$owner" == "${BASHPID:-$$}" ]] || return 0
  fi
  rm -f "${ALERT_MONITOR_LOCK_DIR}/owner" >/dev/null 2>&1 || true
  rmdir "$ALERT_MONITOR_LOCK_DIR" >/dev/null 2>&1 || true
}

claim_monitor_ownership() {
  local current_pid now owner_hb hb_age
  local owner_pid=""
  IS_MONITOR_OWNER=0
  ALERT_OWNER_PID=""
  current_pid="${BASHPID:-$$}"

  if ! acquire_monitor_lock; then
    return 0
  fi

  if [[ -f "$ALERT_MONITOR_PID_FILE" ]]; then
    owner_pid="$(cat "$ALERT_MONITOR_PID_FILE" 2>/dev/null || true)"
  fi

  if [[ -n "$owner_pid" ]] && is_pid_alive "$owner_pid"; then
    now="$(now_interval_ts)"
    owner_hb="$(read_unix_ts "$ALERT_MONITOR_HEARTBEAT_FILE")"
    hb_age=$((now - owner_hb))
    if (( owner_hb > 0 )) && (( hb_age > ALERT_MONITOR_HEARTBEAT_STALE_SECONDS )); then
      owner_pid=""
    fi
  fi

  if [[ -n "$owner_pid" ]] && is_pid_alive "$owner_pid"; then
    if [[ "$owner_pid" == "$current_pid" ]]; then
      IS_MONITOR_OWNER=1
      ALERT_OWNER_PID="$current_pid"
    fi
    release_monitor_lock
    return 0
  fi

  printf '%s' "$current_pid" >"$ALERT_MONITOR_PID_FILE" 2>/dev/null || true
  printf '%s' "$(now_interval_ts)" >"$ALERT_MONITOR_HEARTBEAT_FILE" 2>/dev/null || true
  IS_MONITOR_OWNER=1
  ALERT_OWNER_PID="$current_pid"
  release_monitor_lock
}

release_monitor_ownership() {
  local current_pid
  local owner_pid=""
  current_pid="${BASHPID:-$$}"
  if [[ "$IS_MONITOR_OWNER" != "1" ]]; then
    return 0
  fi
  if [[ -z "$ALERT_OWNER_PID" ]] || [[ "$current_pid" != "$ALERT_OWNER_PID" ]]; then
    return 0
  fi
  if ! acquire_monitor_lock; then
    return 0
  fi
  if [[ -f "$ALERT_MONITOR_PID_FILE" ]]; then
    owner_pid="$(cat "$ALERT_MONITOR_PID_FILE" 2>/dev/null || true)"
    if [[ "$owner_pid" == "$ALERT_OWNER_PID" ]]; then
      rm -f "$ALERT_MONITOR_PID_FILE" >/dev/null 2>&1 || true
      rm -f "$ALERT_MONITOR_HEARTBEAT_FILE" >/dev/null 2>&1 || true
    fi
  fi
  release_monitor_lock
}

is_current_monitor_owner() {
  local owner_pid=""
  [[ "$IS_MONITOR_OWNER" == "1" ]] || return 1
  [[ -n "$ALERT_OWNER_PID" ]] || return 1
  [[ -f "$ALERT_MONITOR_PID_FILE" ]] || return 1
  owner_pid="$(cat "$ALERT_MONITOR_PID_FILE" 2>/dev/null || true)"
  if [[ -z "$owner_pid" ]] || [[ "$owner_pid" != "$ALERT_OWNER_PID" ]]; then
    return 1
  fi
  return 0
}

initialize_alert_state() {
  perform_owner_housekeeping
}

read_unix_ts() {
  local path="$1"
  if [[ -f "$path" ]]; then
    local raw
    raw="$(cat "$path" 2>/dev/null || echo 0)"
    if [[ "$raw" =~ ^[0-9]+$ ]]; then
      printf '%s' "$raw"
      return 0
    fi
  fi
  printf '0'
}

now_highres_ts() {
  perl -MTime::HiRes=clock_gettime,CLOCK_MONOTONIC -e 'printf "%.6f", clock_gettime(CLOCK_MONOTONIC)'
}

now_interval_ts() {
  perl -MTime::HiRes=clock_gettime,CLOCK_MONOTONIC -e 'printf "%d", clock_gettime(CLOCK_MONOTONIC)' 2>/dev/null ||
    date +%s
}

read_highres_ts() {
  local path="$1"
  if [[ -f "$path" ]]; then
    local raw
    raw="$(cat "$path" 2>/dev/null || true)"
    if [[ "$raw" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
      printf '%s' "$raw"
      return 0
    fi
  fi
  printf '0'
}

elapsed_since_ge() {
  local since_ts="$1"
  local threshold_seconds="$2"
  perl -MTime::HiRes=clock_gettime,CLOCK_MONOTONIC -e '
    my ($since, $threshold) = @ARGV;
    $since = 0 unless defined $since && $since =~ /^[0-9]+(?:\.[0-9]+)?$/;
    $threshold = 0 unless defined $threshold && $threshold =~ /^[0-9]+(?:\.[0-9]+)?$/;
    exit((clock_gettime(CLOCK_MONOTONIC) - $since) >= $threshold ? 0 : 1);
  ' "$since_ts" "$threshold_seconds"
}

append_event_log() {
  local message="$1"
  printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${BASHPID:-$$}" "$message" >>"$ALERT_EVENT_LOG_FILE" 2>/dev/null || true
}

event_message_value() {
  local message="$1"
  if [[ "$ALERT_LOG_MESSAGES" == "1" ]]; then
    printf '%s' "$message"
  else
    printf '[redacted]'
  fi
}

run_with_timeout() {
  local timeout_seconds="$1"
  shift
  local pid timer_pid rc

  "$@" >/dev/null 2>&1 &
  pid="$!"
  (
    sleep "$timeout_seconds"
    kill "$pid" >/dev/null 2>&1 || true
  ) >/dev/null 2>&1 &
  timer_pid="$!"

  wait "$pid" >/dev/null 2>&1
  rc="$?"
  kill "$timer_pid" >/dev/null 2>&1 || true
  wait "$timer_pid" >/dev/null 2>&1 || true
  return "$rc"
}

run_detached_with_timeout() {
  (
    set +e
    run_with_timeout "$ALERT_BACKEND_TIMEOUT_SECONDS" "$@"
  ) >/dev/null 2>&1 &
  disown "$!" >/dev/null 2>&1 || true
}

capture_with_timeout() {
  local timeout_seconds="$1"
  local output_path="$2"
  shift 2
  local pid timer_pid rc

  : >"$output_path" 2>/dev/null || return 1
  "$@" >"$output_path" 2>/dev/null &
  pid="$!"
  (
    sleep "$timeout_seconds"
    kill "$pid" >/dev/null 2>&1 || true
  ) >/dev/null 2>&1 &
  timer_pid="$!"

  wait "$pid" >/dev/null 2>&1
  rc="$?"
  kill "$timer_pid" >/dev/null 2>&1 || true
  wait "$timer_pid" >/dev/null 2>&1 || true
  return "$rc"
}

rotate_file_keep_tail() {
  local path="$1"
  local max_bytes="$2"
  local size tmp

  [[ -n "$path" ]] || return 0
  [[ -f "$path" ]] || return 0
  [[ "$max_bytes" =~ ^[0-9]+$ ]] || return 0
  (( max_bytes > 0 )) || return 0

  size="$(file_size_bytes "$path")"
  [[ "$size" =~ ^[0-9]+$ ]] || return 0
  if (( size <= max_bytes )); then
    return 0
  fi

  tmp="${path}.rotate.$(date +%s).${BASHPID:-$$}"
  if ! tail -c "$max_bytes" "$path" >"$tmp" 2>/dev/null; then
    rm -f "$tmp" >/dev/null 2>&1 || true
    return 0
  fi

  # Keep the same inode so active writers remain attached to the visible path.
  cat "$tmp" >"$path" 2>/dev/null || true
  rm -f "$tmp" >/dev/null 2>&1 || true
  append_event_log "rotate_file_keep_tail: path=${path} from=${size} to=${max_bytes}"
}

perform_shared_housekeeping() {
  if acquire_monitor_lock; then
    rotate_file_keep_tail "$ALERT_EVENT_LOG_FILE" "$ALERT_EVENT_LOG_MAX_BYTES"
    release_monitor_lock
  fi
}

perform_owner_housekeeping() {
  perform_shared_housekeeping
  cleanup_idle_group_identities
}

set_pending_state() {
  local group="$1"
  local value="$2"
  write_group_state "$group" pending "$value"
  write_group_state "$group" group "$group"
}

get_pending_state() {
  local group="$1"
  local raw
  raw="$(read_group_state "$group" pending 2>/dev/null || echo 0)"
  [[ "$raw" == "1" ]]
}

set_pending_message() {
  local group="$1"
  local message="$2"
  write_group_state "$group" message "$message"
  write_group_state "$group" group "$group"
}

set_pending_since() {
  local group="$1"
  local now="$2"
  write_group_state "$group" pending_since "$now"
}

get_pending_since() {
  local group="$1"
  read_unix_ts "$(group_state_file "$group" pending_since)"
}

clear_ack_state() {
  local group="$1"
  remove_group_state "$group" ack
}

acknowledge_group() {
  local group="$1"
  write_group_state "$group" ack 1
}

clear_alert_toast() {
  local toast_group="${1:-$ALERT_TOAST_GROUP}"
  local notify_id
  if [[ "$PLATFORM" == "darwin" ]] && command -v terminal-notifier >/dev/null 2>&1; then
    # terminal-notifier -remove may hang on some macOS states. Never let toast
    # cleanup block the approval monitor or leave the alert lock held.
    (
      terminal-notifier -remove "$toast_group" >/dev/null 2>&1 &
      remove_pid="$!"
      sleep "$ALERT_REMOVE_TOAST_TIMEOUT_SECONDS"
      kill "$remove_pid" >/dev/null 2>&1 || true
      wait "$remove_pid" >/dev/null 2>&1 || true
    ) >/dev/null 2>&1 &
    disown "$!" >/dev/null 2>&1 || true
    return 0
  fi

  if [[ "$PLATFORM" == "linux" ]]; then
    notify_id="$(read_group_state "$toast_group" notify_id 2>/dev/null || true)"
    if [[ "$notify_id" =~ ^[0-9]+$ ]] && command_exists gdbus; then
      run_with_timeout "$ALERT_BACKEND_TIMEOUT_SECONDS" \
        gdbus call --session \
        --dest org.freedesktop.Notifications \
        --object-path /org/freedesktop/Notifications \
        --method org.freedesktop.Notifications.CloseNotification \
        "$notify_id" >/dev/null 2>&1 || true
    fi
  fi
}

schedule_linux_notification_close() {
  local notify_id="$1"
  local close_seconds

  [[ "$PLATFORM" == "linux" ]] || return 0
  [[ "$notify_id" =~ ^[0-9]+$ ]] || return 0
  command_exists gdbus || return 0
  [[ "$ALERT_NOTIFY_EXPIRE_MS" =~ ^[0-9]+$ ]] || return 0
  (( ALERT_NOTIFY_EXPIRE_MS > 0 )) || return 0

  close_seconds=$(((ALERT_NOTIFY_EXPIRE_MS + 999) / 1000))
  if (( close_seconds < 1 )); then
    close_seconds=1
  fi

  (
    sleep "$close_seconds"
    run_with_timeout "$ALERT_BACKEND_TIMEOUT_SECONDS" \
      gdbus call --session \
      --dest org.freedesktop.Notifications \
      --object-path /org/freedesktop/Notifications \
      --method org.freedesktop.Notifications.CloseNotification \
      "$notify_id" >/dev/null 2>&1 || true
  ) >/dev/null 2>&1 &
  disown "$!" >/dev/null 2>&1 || true
}

is_acknowledged() {
  local group="$1"
  local raw
  raw="$(read_group_state "$group" ack 2>/dev/null || echo 0)"
  [[ "$raw" == "1" ]]
}

get_pending_message() {
  local group="$1"
  local message
  message="$(read_group_state "$group" message 2>/dev/null || true)"
  [[ -n "$message" ]] && printf '%s' "$message" || printf '%s' "$ALERT_BODY"
}

set_progress_state() {
  local group="$1"
  local now
  now="$(now_highres_ts)"
  write_group_state "$group" progress_since "$now"
  write_group_state "$group" group "$group"
}

has_recent_progress() {
  local group="$1"
  local threshold_seconds="${2:-$ALERT_PROGRESS_SUPPRESS_SECONDS}"
  local since

  since="$(read_highres_ts "$(group_state_file "$group" progress_since)")"
  [[ "$since" != "0" ]] || return 1
  ! elapsed_since_ge "$since" "$threshold_seconds"
}

acquire_dir_lock() {
  local lock_dir="$1"
  local max_attempts="${2:-300}"
  local attempts=0
  while ! mkdir "$lock_dir" >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if (( attempts % 20 == 0 )); then
      reclaim_lock_if_needed "$lock_dir" || true
    fi
    if (( attempts >= max_attempts )); then
      return 1
    fi
    sleep 0.01
  done
  printf '%s' "${BASHPID:-$$}" >"${lock_dir}/owner" 2>/dev/null || true
}

release_dir_lock() {
  local lock_dir="$1"
  local owner=""
  if [[ -f "${lock_dir}/owner" ]]; then
    owner="$(cat "${lock_dir}/owner" 2>/dev/null || true)"
    [[ -z "$owner" || "$owner" == "${BASHPID:-$$}" ]] || return 0
  fi
  rm -f "${lock_dir}/owner" >/dev/null 2>&1 || true
  rmdir "$lock_dir" >/dev/null 2>&1 || true
}

acquire_alert_lock() {
  acquire_dir_lock "$ALERT_LOCK_DIR" 300
}

release_alert_lock() {
  release_dir_lock "$ALERT_LOCK_DIR"
}

resolve_sender_bundle_id() {
  # Optional explicit sender bundle id, no hardcoded editor/terminal binding.
  printf '%s' "$ALERT_TOAST_SENDER_BUNDLE_ID"
}

play_alert_sound() {
  local backend
  [[ "$ALERT_PLAY_SOUND" == "1" ]] || return 0
  backend="$(resolve_sound_backend)"
  case "$backend" in
    afplay)
      run_detached_with_timeout afplay "$ALERT_SOUND_FILE"
      ;;
    paplay)
      run_detached_with_timeout paplay "$ALERT_SOUND_FILE"
      ;;
    canberra-gtk-play)
      run_detached_with_timeout canberra-gtk-play -i message
      ;;
    aplay)
      run_detached_with_timeout aplay -q "$ALERT_SOUND_FILE"
      ;;
    windows-sound)
      run_detached_with_timeout powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "\$sound = '${ALERT_WINDOWS_SOUND_FILE//\'/\'\'}'; Add-Type -MemberDefinition '[DllImport(\"winmm.dll\", SetLastError=true)] public static extern bool PlaySound(string pszSound, System.IntPtr hmod, uint fdwSound);' -Name WinMM -Namespace CodexApprovalNotifier; [CodexApprovalNotifier.WinMM]::PlaySound(\$sound, [IntPtr]::Zero, 0x00020000) | Out-Null"
      ;;
    terminal-bell)
      ring_terminal_bell
      ;;
  esac
  append_event_log "play_alert_sound: backend=${backend}"
  return 0
}

send_macos_terminal_notifier() {
  local alert_message="${1:-$ALERT_BODY}"
  local toast_group="${2:-$ALERT_TOAST_GROUP}"
  local use_toast_sound="${3:-0}"
  local sender ack_cmd ack_file

  command_exists terminal-notifier || return 1

  # If user clicks "Show" on macOS notification, silence repeats for this pending prompt.
  ack_file="$(group_state_file "$toast_group" ack)"
  printf -v ack_cmd 'printf 1 > %q' "$ack_file"

  sender="$(resolve_sender_bundle_id)"
  local -a args=(
    -title "$ALERT_TITLE"
    -subtitle "$ALERT_SUBTITLE"
    -message "$alert_message"
    -group "$toast_group"
    -execute "$ack_cmd"
  )
  if [[ "$use_toast_sound" == "1" ]]; then
    args+=(-sound "$ALERT_SOUND")
  fi
  if [[ -n "$sender" ]]; then
    args+=(-sender "$sender" -activate "$sender")
  fi
  run_with_timeout "$ALERT_BACKEND_TIMEOUT_SECONDS" terminal-notifier "${args[@]}"
}

send_macos_osascript() {
  local alert_message="${1:-$ALERT_BODY}"
  local use_toast_sound="${3:-0}"
  local esc_body esc_title esc_subtitle

  command_exists osascript || return 1
  esc_body="$(printf '%s' "$alert_message" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  esc_title="$(printf '%s' "$ALERT_TITLE" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  esc_subtitle="$(printf '%s' "$ALERT_SUBTITLE" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  if [[ "$use_toast_sound" == "1" ]]; then
    run_with_timeout "$ALERT_BACKEND_TIMEOUT_SECONDS" osascript \
      -e "display notification \"${esc_body}\" with title \"${esc_title}\" subtitle \"${esc_subtitle}\" sound name \"${ALERT_SOUND}\""
  else
    run_with_timeout "$ALERT_BACKEND_TIMEOUT_SECONDS" osascript \
      -e "display notification \"${esc_body}\" with title \"${esc_title}\" subtitle \"${esc_subtitle}\""
  fi
}

ps_single_quote() {
  local value="$1"
  value="${value//$'\r'/ }"
  value="${value//$'\n'/ }"
  value="${value//\'/\'\'}"
  printf "'%s'" "$value"
}

ps_encoded_command() {
  iconv -f UTF-8 -t UTF-16LE | base64 -w 0
}

run_windows_powershell_hidden() {
  local encoded="$1"
  command_exists powershell.exe || return 1
  run_with_timeout "$ALERT_BACKEND_TIMEOUT_SECONDS" powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand "$encoded"
}

run_windows_powershell_detached() {
  local encoded="$1"
  command_exists powershell.exe || return 1
  powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand "$encoded" >/dev/null 2>&1 &
  disown "$!" 2>/dev/null || true
  return 0
}

windows_toast_shortcut_ps_path() {
  local shortcut_name
  shortcut_name="$(ps_single_quote "$ALERT_WINDOWS_SHORTCUT_NAME")"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "\$p = Join-Path ([Environment]::GetFolderPath('StartMenu')) ('Programs\\' + ${shortcut_name}); Write-Output \$p" 2>/dev/null | tr -d '\r' | head -n1
}

windows_toast_app_installed() {
  is_wsl || return 1
  command_exists powershell.exe || return 1
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime] | Out-Null; [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType=WindowsRuntime] | Out-Null" >/dev/null 2>&1
}

windows_toast_shortcut_exists() {
  is_wsl || return 1
  command_exists powershell.exe || return 1
  local shortcut_name
  shortcut_name="$(ps_single_quote "$ALERT_WINDOWS_SHORTCUT_NAME")"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "\$p = Join-Path ([Environment]::GetFolderPath('StartMenu')) ('Programs\\' + ${shortcut_name}); if (Test-Path -LiteralPath \$p) { exit 0 } else { exit 1 }" >/dev/null 2>&1
}

install_windows_toast_shortcut() {
  local app_id shortcut_name script encoded
  is_wsl || {
    printf 'windows toast install is only available on WSL\n' >&2
    return 1
  }
  command_exists powershell.exe || {
    printf 'powershell.exe is required for windows toast install\n' >&2
    return 1
  }
  command_exists iconv || return 1
  command_exists base64 || return 1

  app_id="$(ps_single_quote "$ALERT_WINDOWS_APP_ID")"
  shortcut_name="$(ps_single_quote "$ALERT_WINDOWS_SHORTCUT_NAME")"
  script="
\$ErrorActionPreference = 'Stop'
\$ProgressPreference = 'SilentlyContinue'
\$source = @'
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace CodexApprovalNotifier {
  [ComImport, Guid(\"00021401-0000-0000-C000-000000000046\")]
  public class CShellLink {}

  [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid(\"000214F9-0000-0000-C000-000000000046\")]
  public interface IShellLinkW {
    void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszFile, int cchMaxPath, IntPtr pfd, uint fFlags);
    void GetIDList(out IntPtr ppidl);
    void SetIDList(IntPtr pidl);
    void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszName, int cchMaxName);
    void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string pszName);
    void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszDir, int cchMaxPath);
    void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string pszDir);
    void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszArgs, int cchMaxPath);
    void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string pszArgs);
    void GetHotkey(out short pwHotkey);
    void SetHotkey(short wHotkey);
    void GetShowCmd(out int piShowCmd);
    void SetShowCmd(int iShowCmd);
    void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszIconPath, int cchIconPath, out int piIcon);
    void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string pszIconPath, int iIcon);
    void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string pszPathRel, uint dwReserved);
    void Resolve(IntPtr hwnd, uint fFlags);
    void SetPath([MarshalAs(UnmanagedType.LPWStr)] string pszFile);
  }

  [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid(\"0000010b-0000-0000-C000-000000000046\")]
  public interface IPersistFile {
    void GetClassID(out Guid pClassID);
    void IsDirty();
    void Load([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, uint dwMode);
    void Save([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, bool fRemember);
    void SaveCompleted([MarshalAs(UnmanagedType.LPWStr)] string pszFileName);
    void GetCurFile([MarshalAs(UnmanagedType.LPWStr)] out string ppszFileName);
  }

  [StructLayout(LayoutKind.Sequential, Pack = 4)]
  public struct PropertyKey {
    public Guid fmtid;
    public uint pid;
    public PropertyKey(Guid fmtid, uint pid) {
      this.fmtid = fmtid;
      this.pid = pid;
    }
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct PropVariant {
    public ushort vt;
    public ushort wReserved1;
    public ushort wReserved2;
    public ushort wReserved3;
    public IntPtr p;
    public int p2;
  }

  [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid(\"886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99\")]
  public interface IPropertyStore {
    void GetCount(out uint cProps);
    void GetAt(uint iProp, out PropertyKey pkey);
    void GetValue(ref PropertyKey key, out PropVariant pv);
    void SetValue(ref PropertyKey key, ref PropVariant pv);
    void Commit();
  }

  public static class Shortcut {
    public static void Create(string path, string target, string arguments, string workingDirectory, string icon, string description, string appId) {
      IShellLinkW link = (IShellLinkW)new CShellLink();
      link.SetPath(target);
      link.SetArguments(arguments);
      link.SetWorkingDirectory(workingDirectory);
      link.SetIconLocation(target, 0);
      link.SetDescription(description);

      IPropertyStore propertyStore = (IPropertyStore)link;
      PropertyKey appUserModelId = new PropertyKey(new Guid(\"9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3\"), 5);
      PropVariant pv = new PropVariant();
      pv.vt = 31;
      pv.p = Marshal.StringToCoTaskMemUni(appId);
      try {
        propertyStore.SetValue(ref appUserModelId, ref pv);
        propertyStore.Commit();
      } finally {
        if (pv.p != IntPtr.Zero) Marshal.FreeCoTaskMem(pv.p);
      }

      IPersistFile file = (IPersistFile)link;
      file.Save(path, true);
    }
  }
}
'@
Add-Type -TypeDefinition \$source
\$appId = ${app_id}
\$shortcutName = ${shortcut_name}
\$shortcutPath = Join-Path ([Environment]::GetFolderPath('StartMenu')) ('Programs\\' + \$shortcutName)
\$shortcutDir = Split-Path -Parent \$shortcutPath
New-Item -ItemType Directory -Force -Path \$shortcutDir | Out-Null
\$target = Join-Path \$env:WINDIR 'System32\\WindowsPowerShell\\v1.0\\powershell.exe'
[CodexApprovalNotifier.Shortcut]::Create(\$shortcutPath, \$target, '-NoProfile -WindowStyle Hidden', \$env:USERPROFILE, \$target, 'Codex Approval Notifier', \$appId)
Write-Output \$shortcutPath
"
  encoded="$(printf '%s' "$script" | ps_encoded_command)"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand "$encoded" | tr -d '\r'
}

ensure_windows_toast_installed() {
  is_wsl || return 1
  windows_toast_app_installed || return 1
  windows_toast_shortcut_exists && return 0
  install_windows_toast_shortcut >/dev/null 2>&1
}

install_windows_toast_command() {
  local output
  windows_toast_app_installed || {
    printf 'windows toast WinRT APIs are not available in this PowerShell/Windows environment\n' >&2
    return 1
  }
  output="$(install_windows_toast_shortcut)" || return $?
  if [[ -n "$output" ]]; then
    printf '%s\n' "$output"
  fi
}

uninstall_windows_toast_command() {
  local shortcut_name script encoded
  is_wsl || {
    printf 'windows toast uninstall is only available on WSL\n' >&2
    return 1
  }
  command_exists powershell.exe || return 1
  command_exists cmd.exe || return 1
  command_exists iconv || return 1
  command_exists base64 || return 1
  shortcut_name="$(ps_single_quote "$ALERT_WINDOWS_SHORTCUT_NAME")"
  script="
\$shortcutPath = Join-Path ([Environment]::GetFolderPath('StartMenu')) ('Programs\\' + ${shortcut_name})
if (Test-Path -LiteralPath \$shortcutPath) {
  Remove-Item -LiteralPath \$shortcutPath -Force
  Write-Output \$shortcutPath
}
"
  encoded="$(printf '%s' "$script" | ps_encoded_command)"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand "$encoded" | tr -d '\r'
}

send_windows_winrt_toast() {
  local alert_message="${1:-$ALERT_BODY}"
  local app_id title subtitle text fallback script encoded

  command_exists powershell.exe || return 1
  command_exists iconv || return 1
  command_exists base64 || return 1

  app_id="$(ps_single_quote "$ALERT_WINDOWS_APP_ID")"
  title="$(ps_single_quote "$ALERT_TITLE")"
  subtitle="$(ps_single_quote "$ALERT_SUBTITLE")"
  text="$(ps_single_quote "$alert_message")"
  fallback="$(ps_single_quote "$ALERT_WINDOWS_NOTIFYICON_FALLBACK")"
  script="
\$appId = ${app_id}
\$rawTitle = ${title}
\$rawBody = (${subtitle} + ': ' + ${text})
\$fallback = ${fallback}
try {
  \$ErrorActionPreference = 'Stop'
  \$title = [Security.SecurityElement]::Escape(\$rawTitle)
  \$body = [Security.SecurityElement]::Escape(\$rawBody)
  [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
  [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
  \$xml = @\"
<toast>
  <visual>
    <binding template=\"ToastGeneric\">
      <text>\$title</text>
      <text>\$body</text>
    </binding>
  </visual>
  <audio silent=\"true\"/>
</toast>
\"@
  \$doc = [Windows.Data.Xml.Dom.XmlDocument]::new()
  \$doc.LoadXml(\$xml)
  \$toast = [Windows.UI.Notifications.ToastNotification]::new(\$doc)
  [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier(\$appId).Show(\$toast)
} catch {
  if (\$fallback -ne '1') { throw }
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  \$n = New-Object System.Windows.Forms.NotifyIcon
  \$n.Icon = [System.Drawing.SystemIcons]::Information
  \$n.Visible = \$true
  \$n.BalloonTipTitle = \$rawTitle
  \$n.BalloonTipText = \$rawBody
  \$n.ShowBalloonTip(7000)
  Start-Sleep -Seconds 8
  \$n.Dispose()
}
"
  encoded="$(printf '%s' "$script" | ps_encoded_command)"
  run_windows_powershell_detached "$encoded"
  return 0
}

send_windows_toast() {
  local alert_message="${1:-$ALERT_BODY}"
  local title subtitle text child_script launcher_script child_encoded launcher_encoded

  is_wsl || return 1
  command_exists powershell.exe || return 1
  command_exists cmd.exe || return 1
  command_exists iconv || return 1
  command_exists base64 || return 1

  if send_windows_winrt_toast "$alert_message"; then
    return 0
  fi
  [[ "$ALERT_WINDOWS_NOTIFYICON_FALLBACK" == "1" ]] || return 1

  title="$(ps_single_quote "$ALERT_TITLE")"
  subtitle="$(ps_single_quote "$ALERT_SUBTITLE")"
  text="$(ps_single_quote "$alert_message")"

  child_script="
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
\$n = New-Object System.Windows.Forms.NotifyIcon
\$n.Icon = [System.Drawing.SystemIcons]::Information
\$n.Visible = \$true
\$n.BalloonTipTitle = ${title}
\$n.BalloonTipText = (${subtitle} + ': ' + ${text})
\$n.ShowBalloonTip(7000)
Start-Sleep -Seconds 8
\$n.Dispose()
"
  child_encoded="$(printf '%s' "$child_script" | ps_encoded_command)"
  launcher_script="
Start-Process -WindowStyle Hidden powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand','${child_encoded}')
"
  launcher_encoded="$(printf '%s' "$launcher_script" | ps_encoded_command)"
  run_windows_powershell_hidden "$launcher_encoded"
  return 0
}

send_linux_notify_send() {
  local alert_message="${1:-$ALERT_BODY}"
  local toast_group="${2:-$ALERT_TOAST_GROUP}"
  local notification_text="${ALERT_SUBTITLE}: ${alert_message}"
  local current_id new_id
  local -a args=()

  command_exists notify-send || return 1
  args+=(--urgency="$ALERT_NOTIFY_URGENCY")
  if [[ "$ALERT_NOTIFY_TRANSIENT" == "1" ]] && notify_send_supports '--transient'; then
    args+=(--transient)
  fi
  if notify_send_supports '--app-name'; then
    args+=(--app-name="$ALERT_TITLE")
  fi
  if notify_send_supports '--category'; then
    args+=(--category="$ALERT_NOTIFY_CATEGORY")
  fi
  if notify_send_supports '--expire-time'; then
    args+=(--expire-time="$ALERT_NOTIFY_EXPIRE_MS")
  fi
  if notify_send_supports '--print-id' && notify_send_supports '--replace-id'; then
    current_id="$(read_group_state "$toast_group" notify_id 2>/dev/null || true)"
    if [[ "$current_id" =~ ^[0-9]+$ ]]; then
      args+=(--replace-id="$current_id")
    fi
    args+=(--print-id)
    local output_path
    output_path="${ALERT_STATE_DIR}/${ALERT_STATE_PREFIX}.notify-send.$(date +%s).${BASHPID:-$$}.out"
    capture_with_timeout "$ALERT_BACKEND_TIMEOUT_SECONDS" "$output_path" notify-send "${args[@]}" "$ALERT_TITLE" "$notification_text" || {
      rm -f "$output_path" >/dev/null 2>&1 || true
      return 1
    }
    new_id="$(cat "$output_path" 2>/dev/null || true)"
    rm -f "$output_path" >/dev/null 2>&1 || true
    new_id="$(printf '%s' "$new_id" | awk 'NF {print $1; exit}')"
    if [[ "$new_id" =~ ^[0-9]+$ ]]; then
      write_group_state "$toast_group" notify_id "$new_id"
      schedule_linux_notification_close "$new_id"
    fi
    return 0
  fi

  run_with_timeout "$ALERT_BACKEND_TIMEOUT_SECONDS" notify-send "${args[@]}" "$ALERT_TITLE" "$notification_text"
}

send_linux_zenity() {
  local alert_message="${1:-$ALERT_BODY}"
  command_exists zenity || return 1
  run_with_timeout "$ALERT_BACKEND_TIMEOUT_SECONDS" zenity --notification --title="$ALERT_TITLE" --text="${ALERT_SUBTITLE}: ${alert_message}"
}

send_linux_kdialog() {
  local alert_message="${1:-$ALERT_BODY}"
  command_exists kdialog || return 1
  run_with_timeout "$ALERT_BACKEND_TIMEOUT_SECONDS" kdialog --title "$ALERT_TITLE" --passivepopup "${ALERT_SUBTITLE}: ${alert_message}" 0
}

send_alert_toast() {
  local alert_message="${1:-$ALERT_BODY}"
  local toast_group="${2:-$ALERT_TOAST_GROUP}"
  local use_toast_sound=1
  local backend="none"
  local status="failed"

  # When external sound is enabled, keep the toast itself silent.
  if [[ "$ALERT_PLAY_SOUND" == "1" ]]; then
    use_toast_sound=0
  fi

  if [[ "$PLATFORM" == "darwin" ]]; then
    if send_macos_terminal_notifier "$alert_message" "$toast_group" "$use_toast_sound"; then
      backend="terminal-notifier"
      status="sent"
    elif send_macos_osascript "$alert_message" "$toast_group" "$use_toast_sound"; then
      backend="osascript"
      status="sent"
    fi
  else
    if send_windows_toast "$alert_message" "$toast_group"; then
      backend="windows-toast"
      status="sent"
    elif is_wsl; then
      backend="windows-toast"
      status="failed"
    elif send_linux_notify_send "$alert_message" "$toast_group"; then
      backend="notify-send"
      status="sent"
    elif send_linux_zenity "$alert_message" "$toast_group"; then
      backend="zenity"
      status="sent"
    elif send_linux_kdialog "$alert_message" "$toast_group"; then
      backend="kdialog"
      status="sent"
    fi
  fi

  append_event_log "send_alert_toast: status=${status} backend=${backend} group=${toast_group}"
  return 0
}

notify_approval() {
  local alert_message="${1:-$ALERT_BODY}"
  local toast_group="${2:-$ALERT_TOAST_GROUP}"
  if is_wsl && [[ "$(resolve_notification_backend)" == "windows-toast" ]]; then
    send_alert_toast "$alert_message" "$toast_group"
    play_alert_sound
    return 0
  fi
  play_alert_sound
  send_alert_toast "$alert_message" "$toast_group"
}

notify_pending_command() {
  local toast_group="${1:-$ALERT_TOAST_GROUP}"
  local message now

  mkdir -p "$ALERT_STATE_DIR" >/dev/null 2>&1 || true
  get_pending_state "$toast_group" || return 0
  is_acknowledged "$toast_group" && return 0

  message="$(get_pending_message "$toast_group")"
  notify_approval "$message" "$toast_group"

  if is_wsl && [[ "$(resolve_notification_backend)" == "windows-toast" ]] && get_pending_state "$toast_group" && ! is_acknowledged "$toast_group"; then
    now="$(now_interval_ts)"
    write_group_state "$toast_group" last_sound "$now"
    write_group_state "$toast_group" next_sound "$((now + ALERT_REPEAT_SOUND_SECONDS))"
  fi
  append_event_log "notify_pending: notified group=${toast_group}"
}

start_notify_pending_process() {
  local toast_group="$1"
  nohup env CODEX_NO_ALERT=1 "$0" --notify-pending "$toast_group" >/dev/null 2>&1 &
  disown "$!" 2>/dev/null || true
}

start_pending_alert() {
  local message="${1:-$ALERT_BODY}"
  local toast_group="${2:-$ALERT_TOAST_GROUP}"
  local now last_event key previous_key lock_dir
  local should_notify=1

  key="$(hash_text "$message")"
  now="$(now_interval_ts)"
  previous_key=""
  lock_dir="$(group_lock_dir "$toast_group")"

  if ! acquire_dir_lock "$lock_dir" 20; then
    append_event_log "start_pending_alert: lock busy group=${toast_group}"
    return 0
  fi

  # If this group is already pending, avoid stacking immediate notifications.
  if get_pending_state "$toast_group"; then
    set_pending_message "$toast_group" "$message"
    append_event_log "start_pending_alert: already pending group=${toast_group}"
    release_dir_lock "$lock_dir"
    return 0
  fi

  last_event="$(read_unix_ts "$(group_state_file "$toast_group" last_event)")"
  if (( now - last_event < ALERT_MIN_GAP_SECONDS )); then
    should_notify=0
  fi

  previous_key="$(read_group_state "$toast_group" last_event_key 2>/dev/null || true)"
  if [[ "$previous_key" == "$key" ]] && (( now - last_event < ALERT_COOLDOWN_SECONDS )); then
    should_notify=0
  fi

  set_pending_message "$toast_group" "$message"
  set_pending_since "$toast_group" "$now"
  clear_ack_state "$toast_group"

  if [[ "$should_notify" == "1" ]]; then
    write_group_state "$toast_group" last_event "$now"
    write_group_state "$toast_group" last_event_key "$key"
  fi

  # Make reminder timestamps visible before the pending flag. The owner loop
  # reads pending state without taking this lock, so publishing pending first
  # can produce a second sound/toast immediately after the hook notification.
  write_group_state "$toast_group" last_sound "$now"
  write_group_state "$toast_group" last_toast "$now"
  write_group_state "$toast_group" next_sound "$((now + ALERT_REPEAT_SOUND_SECONDS))"
  write_group_state "$toast_group" next_toast "$((now + ALERT_REPEAT_TOAST_SECONDS))"
  set_pending_state "$toast_group" 1
  append_event_log "start_pending_alert: pending=1 group=${toast_group} notify=${should_notify} message=$(event_message_value "$message")"
  release_dir_lock "$lock_dir"

  if [[ "$should_notify" == "1" ]]; then
    start_notify_pending_process "$toast_group"
    append_event_log "start_pending_alert: notify_queued group=${toast_group}"
  fi
}

clear_pending_alert() {
  local request_group="${1:-}"
  local group
  if [[ -z "$request_group" ]]; then
    while IFS= read -r group; do
      [[ -n "$group" ]] && clear_pending_alert "$group"
    done < <(list_groups_with_flag pending)
    return 0
  fi

  if ! acquire_alert_lock; then
    append_event_log "clear_pending_alert: lock busy group=${request_group}"
    return 0
  fi

  set_pending_state "$request_group" 0
  remove_group_state "$request_group" message pending ack pending_since last_event last_event_key last_sound last_toast next_sound next_toast notify_id
  clear_alert_toast "$request_group"
  cleanup_group_identity_if_idle "$request_group"
  append_event_log "clear_pending_alert: group=${request_group}"
  release_alert_lock
}

OWNER_LAST_HOUSEKEEPING_TS=0

reminder_tick() {
  local now
  local group
  local repeat_toast_enabled=1

  now="$(now_interval_ts)"
  if is_wsl && [[ "$(resolve_notification_backend)" == "windows-toast" ]]; then
    repeat_toast_enabled=0
  fi
  if (( ALERT_JANITOR_INTERVAL_SECONDS > 0 )) && (( now - OWNER_LAST_HOUSEKEEPING_TS >= ALERT_JANITOR_INTERVAL_SECONDS )); then
    perform_owner_housekeeping
    OWNER_LAST_HOUSEKEEPING_TS="$now"
  fi

  while IFS= read -r group; do
    [[ -n "$group" ]] || continue
    local pending_since next_sound next_toast message sound_due toast_due timeout_due
    sound_due=0
    toast_due=0
    timeout_due=0

    if ! acquire_alert_lock; then
      append_event_log "reminder_tick: lock busy group=${group}"
      continue
    fi

    if ! get_pending_state "$group" || is_acknowledged "$group"; then
      release_alert_lock
      continue
    fi

    pending_since="$(get_pending_since "$group")"
    message="$(get_pending_message "$group")"
    next_sound="$(read_unix_ts "$(group_state_file "$group" next_sound)")"
    next_toast="$(read_unix_ts "$(group_state_file "$group" next_toast)")"

    if (( next_sound <= 0 )); then
      next_sound=$((pending_since + ALERT_REPEAT_SOUND_SECONDS))
    fi
    if (( repeat_toast_enabled == 1 )) && (( next_toast <= 0 )); then
      next_toast=$((pending_since + ALERT_REPEAT_TOAST_SECONDS))
    fi

    if (( ALERT_PENDING_TIMEOUT_SECONDS > 0 )) && (( now - pending_since >= ALERT_PENDING_TIMEOUT_SECONDS )); then
      timeout_due=1
    fi

    if [[ "$timeout_due" != "1" ]] && (( ALERT_REPEAT_SOUND_SECONDS > 0 )) && (( now >= next_sound )); then
      sound_due=1
      while (( next_sound <= now )); do
        next_sound=$((next_sound + ALERT_REPEAT_SOUND_SECONDS))
      done
      write_group_state "$group" next_sound "$next_sound"
      write_group_state "$group" last_sound "$now"
    fi

    if (( repeat_toast_enabled == 1 )) && (( ALERT_REPEAT_TOAST_SECONDS > 0 )) && (( now >= next_toast )); then
      toast_due=1
      while (( next_toast <= now )); do
        next_toast=$((next_toast + ALERT_REPEAT_TOAST_SECONDS))
      done
      write_group_state "$group" next_toast "$next_toast"
      write_group_state "$group" last_toast "$now"
    fi

    release_alert_lock

    if [[ "$sound_due" == "1" ]] && get_pending_state "$group" && ! is_acknowledged "$group"; then
      play_alert_sound
    fi

    if [[ "$toast_due" == "1" ]] && get_pending_state "$group" && ! is_acknowledged "$group"; then
      send_alert_toast "$message" "$group"
    fi

    if [[ "$timeout_due" == "1" ]] && get_pending_state "$group"; then
      append_event_log "reminder_tick: pending_timeout group=${group} age=$((now - pending_since))"
      clear_pending_alert "$group"
    fi
  done < <(list_groups_with_flag pending)
}

owner_supervisor_loop() {
  local was_owner=0

  while true; do
    claim_monitor_ownership
    if is_current_monitor_owner; then
      if [[ "$was_owner" != "1" ]]; then
        append_event_log "owner_supervisor: owner_acquired pid=${ALERT_OWNER_PID}"
        initialize_alert_state
      fi
      was_owner=1
      printf '%s' "$(now_interval_ts)" >"$ALERT_MONITOR_HEARTBEAT_FILE" 2>/dev/null || true
      reminder_tick
      sleep "$ALERT_LOOP_TICK_SECONDS"
      continue
    fi

    if [[ "$was_owner" == "1" ]]; then
      append_event_log "owner_supervisor: owner_lost"
    fi
    was_owner=0
    sleep "$ALERT_OWNER_CHECK_SECONDS"
  done
}

tui_line_indicates_command_progress() {
  local line="$1"
  [[ "$line" == *'ToolResult:'* ]] && return 0
  if [[ "$line" == *'ToolCall: exec_command '* ]] && [[ "$line" != *'"sandbox_permissions":"require_escalated"'* ]]; then
    return 0
  fi
  return 1
}

group_belongs_to_thread() {
  local group="$1"
  local thread_group="$2"
  [[ "$group" == "$thread_group" || "$group" == "$thread_group"-* ]]
}

clear_alerts_for_thread_group() {
  local thread_group="$1"
  local group

  while IFS= read -r group; do
    [[ -n "$group" ]] || continue
    if group_belongs_to_thread "$group" "$thread_group"; then
      acknowledge_group "$group"
      clear_pending_alert "$group"
    fi
  done < <(list_groups_with_flag pending)
}

json_get_string() {
  local json="$1"
  local path="$2"
  if command_exists jq; then
    printf '%s' "$json" | jq -er "$path // empty" 2>/dev/null && return 0
  fi

  local key
  key="${path##*.}"
  key="${key//\"/}"
  printf '%s' "$json" | perl -0777 -MEncode=decode -e '
    my $key = quotemeta shift @ARGV;
    my $json = do { local $/; <STDIN> };
    if ($json =~ /"$key"\s*:\s*"((?:\\.|[^"\\])*)"/s) {
      my $s = $1;
      $s =~ s/\\"/"/g;
      $s =~ s/\\\\/\\/g;
      $s =~ s/\\n/ /g;
      $s =~ s/\\r/ /g;
      $s =~ s/\\t/ /g;
      print $s;
    }
  ' "$key"
}

parse_permission_request_payload() {
  local json="$1"
  if command_exists jq; then
    printf '%s' "$json" | jq -r '[
      .hook_event_name // "",
      .session_id // "",
      .turn_id // "",
      .tool_name // "",
      .tool_input.command // "",
      .tool_input.description // "",
      .reason // ""
    ] | map(gsub("[\t\r\n]+"; " ")) | @tsv' 2>/dev/null && return 0
  fi

  printf '%s' "$json" | perl -0777 -e '
    my $json = do { local $/; <STDIN> };
    sub value {
      my ($key) = @_;
      my $q = quotemeta($key);
      return "" unless $json =~ /"$q"\s*:\s*"((?:\\.|[^"\\])*)"/s;
      my $s = $1;
      $s =~ s/\\"/"/g;
      $s =~ s/\\\\/\\/g;
      $s =~ s/\\n/ /g;
      $s =~ s/\\r/ /g;
      $s =~ s/\\t/ /g;
      $s =~ s/[\t\r\n]+/ /g;
      return $s;
    }
    print join("\t", map { value($_) } qw(hook_event_name session_id turn_id tool_name command description reason));
  '
}

truncate_message() {
  local message="$1"
  local max_chars="${2:-360}"
  printf '%s' "$message" | awk -v max="$max_chars" '
    BEGIN { ORS = "" }
    {
      gsub(/[[:space:]]+/, " ");
      if (length($0) > max) {
        print substr($0, 1, max - 3) "...";
      } else {
        print $0;
      }
    }
  '
}

approval_group_for_hook() {
  local session_id="$1"
  local turn_id="$2"
  local tool_name="$3"
  local command="$4"
  local base key

  if [[ -n "$session_id" ]]; then
    base="${ALERT_TOAST_GROUP}-${session_id}"
  else
    base="$ALERT_TOAST_GROUP"
  fi

  key="$(hash_text "${turn_id}|${tool_name}|${command}")"
  printf '%s-%s' "$base" "${key:0:12}"
}

hook_permission_request_command() {
  local payload hook_event session_id turn_id tool_name command description reason message group

  mkdir -p "$ALERT_STATE_DIR" >/dev/null 2>&1 || true
  payload="$(cat)"

  if [[ "$ALERT_HOOK_PERMISSION_REQUEST_ENABLED" != "1" ]]; then
    append_event_log "hook_permission_request: disabled"
    return 0
  fi

  IFS=$'\t' read -r hook_event session_id turn_id tool_name command description reason < <(parse_permission_request_payload "$payload") || true

  if [[ -n "$hook_event" ]] && [[ "$hook_event" != "PermissionRequest" ]]; then
    append_event_log "hook_permission_request: ignored_event event=${hook_event}"
    return 0
  fi

  if [[ -z "$description" ]]; then
    description="$reason"
  fi

  message="$description"
  if [[ -z "$message" ]]; then
    message="$command"
  fi
  if [[ -z "$message" ]]; then
    message="$ALERT_BODY"
  fi
  message="$(truncate_message "$message")"

  group="$(approval_group_for_hook "$session_id" "$turn_id" "$tool_name" "$command")"
  # Hooks may run even if Codex was started without the shell wrapper.
  # Ensure reminder loops are running so sound repeats are not lost.
  ensure_monitor_daemon_running
  append_event_log "hook_permission_request: start group=${group} tool=${tool_name:-unknown} message=$(event_message_value "$message")"
  start_pending_alert "$message" "$group"
  return 0
}

process_tui_log_line() {
  local line="$1"
  local thread_id thread_group line_is_progress
  line_is_progress=0
  thread_id="$(printf '%s' "$line" | sed -nE 's/.*thread_id=([0-9a-f-]+).*/\1/p' | head -n1)"
  if [[ -n "$thread_id" ]]; then
    thread_group="${ALERT_TOAST_GROUP}-${thread_id}"
  else
    thread_group="$ALERT_TOAST_GROUP"
  fi

  if tui_line_indicates_command_progress "$line"; then
    line_is_progress=1
    set_progress_state "$thread_group"
  fi

  if [[ "$line" == *'codex.op="exec_approval"'* ]] || [[ "$line" == *'op.dispatch.exec_approval'* ]]; then
    local exec_now
    exec_now="$(now_interval_ts)"
    if [[ "$thread_group" != "$TUI_LAST_EXEC_APPROVAL_GROUP" ]] || (( exec_now - TUI_LAST_EXEC_APPROVAL_EPOCH > 1 )); then
      append_event_log "monitor_tui_log: exec_approval group=${thread_group}"
      TUI_LAST_EXEC_APPROVAL_GROUP="$thread_group"
      TUI_LAST_EXEC_APPROVAL_EPOCH="$exec_now"
    fi
    clear_alerts_for_thread_group "$thread_group"
    if [[ "$thread_group" != "$ALERT_TOAST_GROUP" ]]; then
      clear_pending_alert "$ALERT_TOAST_GROUP"
    fi
    return 0
  fi

  if [[ "$line_is_progress" == "1" ]]; then
    append_event_log "monitor_tui_log: progress_observed group=${thread_group}"
  fi
}

monitor_tui_log() {
  local offset=0
  local size delta line
  TUI_LAST_EXEC_APPROVAL_GROUP=""
  TUI_LAST_EXEC_APPROVAL_EPOCH=0
  if [[ -f "$CODEX_TUI_LOG_FILE" ]]; then
    size="$(wc -c <"$CODEX_TUI_LOG_FILE" 2>/dev/null | tr -d '[:space:]' || true)"
    if [[ "$size" =~ ^[0-9]+$ ]]; then
      offset="$size"
    fi
  fi

  while true; do
    if [[ -f "$CODEX_TUI_LOG_FILE" ]]; then
      size="$(wc -c <"$CODEX_TUI_LOG_FILE" 2>/dev/null | tr -d '[:space:]' || true)"
      if [[ "$size" =~ ^[0-9]+$ ]]; then
        if (( size < offset )); then
          offset=0
        fi
        if (( size > offset )); then
          delta=$((size - offset))
          while IFS= read -r line || [[ -n "$line" ]]; do
            process_tui_log_line "$line"
          done < <(dd if="$CODEX_TUI_LOG_FILE" bs=1 skip="$offset" count="$delta" 2>/dev/null)
          offset="$size"
        fi
      fi
    else
      offset=0
    fi
    sleep "$ALERT_LOOP_TICK_SECONDS"
  done
}

cleanup() {
  # Cleanup must be best-effort; never fail the wrapper on exit.
  if [[ "${CLEANED_UP:-0}" == "1" ]]; then
    return 0
  fi
  CLEANED_UP=1
  set +e
  stop_monitor_processes
  if [[ "$IS_MONITOR_OWNER" == "1" ]] && [[ -n "$ALERT_OWNER_PID" ]] && [[ "${BASHPID:-$$}" == "$ALERT_OWNER_PID" ]]; then
    append_event_log "cleanup: owner exit"
    clear_pending_alert
  fi
  if [[ "$IS_MONITOR_OWNER" == "1" ]] && [[ -n "$ALERT_OWNER_PID" ]] && [[ "${BASHPID:-$$}" == "$ALERT_OWNER_PID" ]]; then
    if [[ -f "$ALERT_MONITOR_PID_FILE" ]] && [[ "$(cat "$ALERT_MONITOR_PID_FILE" 2>/dev/null || true)" == "$ALERT_OWNER_PID" ]]; then
      rm -f "$ALERT_MONITOR_PID_FILE" >/dev/null 2>&1 || true
    fi
    release_alert_lock
  fi
  release_alert_lock
  release_monitor_lock
  release_monitor_ownership
}

run_monitor_process() {
  # Background monitors must clean short-lived descendants themselves so the
  # parent shell does not print job diagnostics when Codex exits.
  set +e
  trap 'set +e; terminate_child_tree "${BASHPID:-$$}"; exit 0' INT TERM
  trap 'set +e; terminate_child_tree "${BASHPID:-$$}"' EXIT
  "$@"
}

start_monitor_process() {
  run_monitor_process "$@" >/dev/null 2>&1 &
  MONITOR_PIDS+=("$!")
}

stop_monitor_processes() {
  local pid
  for pid in "${MONITOR_PIDS[@]:-}"; do
    [[ -n "$pid" ]] || continue
    terminate_child_tree "$pid"
    kill -TERM "$pid" >/dev/null 2>&1 || true
  done

  for pid in "${MONITOR_PIDS[@]:-}"; do
    [[ -n "$pid" ]] || continue
    wait "$pid" 2>/dev/null || true
  done
  MONITOR_PIDS=()
}

start_monitor_daemon_command() {
  mkdir -p "$ALERT_STATE_DIR" >/dev/null 2>&1 || true
  nohup env CODEX_NO_ALERT=1 "$0" --owner-supervisor-loop >/dev/null 2>&1 &
  disown "$!" 2>/dev/null || true
  nohup env CODEX_NO_ALERT=1 "$0" --monitor-tui-log >/dev/null 2>&1 &
  disown "$!" 2>/dev/null || true
}

ensure_monitor_daemon_running() {
  local pid=""
  if [[ -f "$ALERT_MONITOR_PID_FILE" ]]; then
    pid="$(cat "$ALERT_MONITOR_PID_FILE" 2>/dev/null || true)"
  fi
  if [[ -n "$pid" ]] && is_pid_alive "$pid"; then
    return 0
  fi
  append_event_log "ensure_monitor_daemon_running: starting daemon"
  start_monitor_daemon_command
}

handle_signal() {
  local signal="$1"
  trap - "$signal"
  cleanup
  case "$signal" in
    INT) exit 130 ;;
    TERM) exit 143 ;;
    *) exit 1 ;;
  esac
}

run_codex_direct() {
  env CODEX_NO_ALERT=1 "$CODEX_BIN" "$@"
}

case "${1:-}" in
  --help|-h)
    show_usage
    exit 0
    ;;
  --doctor|doctor)
    mkdir -p "$ALERT_STATE_DIR" >/dev/null 2>&1 || true
    doctor
    exit $?
    ;;
  --status|status)
    mkdir -p "$ALERT_STATE_DIR" >/dev/null 2>&1 || true
    status_command
    exit 0
    ;;
  --clear|clear)
    clear_command
    exit 0
    ;;
  --install-hook|install-hook)
    install_hook_command
    exit $?
    ;;
  --uninstall-hook|uninstall-hook)
    uninstall_hook_command
    exit $?
    ;;
  --install-windows-toast|install-windows-toast)
    install_windows_toast_command
    exit $?
    ;;
  --uninstall-windows-toast|uninstall-windows-toast)
    uninstall_windows_toast_command
    exit $?
    ;;
  --start-monitor|start-monitor)
    start_monitor_daemon_command
    exit 0
    ;;
  --owner-supervisor-loop)
    mkdir -p "$ALERT_STATE_DIR" >/dev/null 2>&1 || true
    owner_supervisor_loop
    exit $?
    ;;
  --monitor-tui-log)
    mkdir -p "$ALERT_STATE_DIR" >/dev/null 2>&1 || true
    monitor_tui_log
    exit $?
    ;;
  --notify-pending)
    shift || true
    notify_pending_command "${1:-$ALERT_TOAST_GROUP}"
    exit $?
    ;;
  --hook-permission-request|hook-permission-request)
    hook_permission_request_command
    exit 0
    ;;
  --self-test|self-test)
    shift || true
    self_test_command "$*"
    exit $?
    ;;
  --backend-test|backend-test)
    backend_test_command
    exit $?
    ;;
  --tail-events|tail-events)
    tail_events_command
    exit 0
    ;;
  --version|version)
    show_version
    exit 0
    ;;
esac

need_cmd "$CODEX_BIN"

mkdir -p "$ALERT_STATE_DIR" >/dev/null 2>&1 || true

MONITOR_PIDS=()
IS_MONITOR_OWNER=0
ALERT_OWNER_PID=""

CLEANED_UP=0
trap cleanup EXIT
trap 'handle_signal INT' INT
trap 'handle_signal TERM' TERM

start_monitor_process owner_supervisor_loop

start_monitor_process monitor_tui_log

run_codex_direct "$@"
exit $?
