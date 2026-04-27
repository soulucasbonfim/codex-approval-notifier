#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
NOTIFIER="${CODEX_ALERT_TEST_NOTIFIER:-${SCRIPT_DIR}/codex-approval-notifier.sh}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-approval-smoke.XXXXXX")"
TEST_LOG="${TMP_ROOT}/backend.log"

cleanup() {
  set +e
  if [[ -n "${RUN_PID:-}" ]]; then
    kill "$RUN_PID" >/dev/null 2>&1 || true
    wait "$RUN_PID" >/dev/null 2>&1 || true
  fi
  pkill -f "$NOTIFIER --notify-pending" >/dev/null 2>&1 || true
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$*" >&2
  if [[ -f "$TEST_LOG" ]]; then
    printf '\nbackend log:\n' >&2
    cat "$TEST_LOG" >&2
  fi
  exit 1
}

pass() {
  printf 'ok - %s\n' "$*"
}

make_fake_bin() {
  local bin_dir="$1"
  mkdir -p "$bin_dir"

  cat >"${bin_dir}/codex" <<'FAKE'
#!/usr/bin/env bash
sleep "${FAKE_CODEX_SLEEP:-2}"
FAKE

  cat >"${bin_dir}/terminal-notifier" <<'FAKE'
#!/usr/bin/env bash
if [[ " $* " == *" -remove "* ]]; then
  printf 'terminal-notifier-remove %s\n' "$*" >>"$NOTIFIER_TEST_LOG"
  if [[ "${FAKE_TERMINAL_NOTIFIER_REMOVE_HANG:-0}" == "1" ]]; then
    sleep 5
  fi
  exit 0
fi
printf 'terminal-notifier %s\n' "$*" >>"$NOTIFIER_TEST_LOG"
if [[ "${FAKE_TERMINAL_NOTIFIER_HANG:-0}" == "1" ]]; then
  sleep 5
fi
[[ "${FAKE_TERMINAL_NOTIFIER_FAIL:-0}" == "1" ]] && exit 1
exit 0
FAKE

  cat >"${bin_dir}/osascript" <<'FAKE'
#!/usr/bin/env bash
printf 'osascript %s\n' "$*" >>"$NOTIFIER_TEST_LOG"
[[ "${FAKE_OSASCRIPT_FAIL:-0}" == "1" ]] && exit 1
exit 0
FAKE

  cat >"${bin_dir}/notify-send" <<'FAKE'
#!/usr/bin/env bash
if [[ "${1:-}" == "--help" ]]; then
  cat <<'HELP'
Usage: notify-send [OPTIONS] <summary> [body]
  --urgency=LEVEL
  --app-name=APP_NAME
  --category=TYPE
  --expire-time=TIME
  --print-id
  --replace-id=ID
HELP
  exit 0
fi
printf 'notify-send %s\n' "$*" >>"$NOTIFIER_TEST_LOG"
[[ "${FAKE_NOTIFY_SEND_FAIL:-0}" == "1" ]] && exit 1
if [[ " $* " == *" --print-id "* ]]; then
  printf '101\n'
fi
exit 0
FAKE

  cat >"${bin_dir}/zenity" <<'FAKE'
#!/usr/bin/env bash
printf 'zenity %s\n' "$*" >>"$NOTIFIER_TEST_LOG"
[[ "${FAKE_ZENITY_FAIL:-0}" == "1" ]] && exit 1
exit 0
FAKE

  cat >"${bin_dir}/kdialog" <<'FAKE'
#!/usr/bin/env bash
printf 'kdialog %s\n' "$*" >>"$NOTIFIER_TEST_LOG"
exit 0
FAKE

  cat >"${bin_dir}/afplay" <<'FAKE'
#!/usr/bin/env bash
printf 'afplay %s\n' "$*" >>"$NOTIFIER_TEST_LOG"
exit 0
FAKE

  cat >"${bin_dir}/paplay" <<'FAKE'
#!/usr/bin/env bash
printf 'paplay %s\n' "$*" >>"$NOTIFIER_TEST_LOG"
exit 0
FAKE

  cat >"${bin_dir}/canberra-gtk-play" <<'FAKE'
#!/usr/bin/env bash
printf 'canberra-gtk-play %s\n' "$*" >>"$NOTIFIER_TEST_LOG"
exit 0
FAKE

  cat >"${bin_dir}/aplay" <<'FAKE'
#!/usr/bin/env bash
printf 'aplay %s\n' "$*" >>"$NOTIFIER_TEST_LOG"
exit 0
FAKE

  chmod +x "${bin_dir}"/*
}

start_notifier() {
  local platform="$1"
  local state_dir="$2"
  local tui_log="$3"
  local sound_file="$4"
  shift 4

  mkdir -p "$state_dir" "$(dirname "$tui_log")"
  : >"$TEST_LOG"
  : >"$tui_log"
  (
    PATH="${FAKE_BIN}:$PATH" \
    NOTIFIER_TEST_LOG="$TEST_LOG" \
    CODEX_BIN="${FAKE_BIN}/codex" \
    CODEX_ALERT_PLATFORM="$platform" \
    CODEX_TUI_LOG_FILE="$tui_log" \
    CODEX_ALERT_STATE_DIR="$state_dir" \
    CODEX_ALERT_SOUND_FILE="$sound_file" \
    CODEX_ALERT_PROGRESS_SUPPRESS_SECONDS=0.25 \
    CODEX_ALERT_LOOP_TICK_SECONDS=0.05 \
    CODEX_ALERT_OWNER_CHECK_SECONDS=0.05 \
    CODEX_ALERT_REPEAT_SOUND_SECONDS=60 \
    CODEX_ALERT_REPEAT_TOAST_SECONDS=60 \
    CODEX_ALERT_PENDING_TIMEOUT_SECONDS=5 \
    FAKE_CODEX_SLEEP=2 \
    "$@" \
    "$NOTIFIER" >/"${state_dir}/stdout.log" 2>/"${state_dir}/stderr.log"
  ) &
  RUN_PID="$!"
  sleep 0.35
}

stop_notifier() {
  if [[ -n "${RUN_PID:-}" ]]; then
    kill "$RUN_PID" >/dev/null 2>&1 || true
    wait "$RUN_PID" >/dev/null 2>&1 || true
    RUN_PID=""
  fi
  local attempts=0
  while (( attempts < 40 )); do
    if ! pgrep -f "$NOTIFIER --notify-pending" >/dev/null 2>&1; then
      return 0
    fi
    attempts=$((attempts + 1))
    sleep 0.05
  done
}

append_prompt_line() {
  local tui_log="$1"
  printf '%s\n' '2026-04-25T00:00:00Z thread_id=aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa ToolCall: exec_command {"cmd":"echo smoke >> /tmp/smoke","sandbox_permissions":"require_escalated","justification":"Smoke approval prompt"}' >>"$tui_log"
}

append_progress_line() {
  local tui_log="$1"
  printf '%s\n' '2026-04-25T00:00:01Z thread_id=aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa ToolResult: exec_command {"exit_code":0}' >>"$tui_log"
}

append_model_noise_lines() {
  local tui_log="$1"
  printf '%s\n' '2026-04-25T00:00:01Z thread_id=aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa codex_core_plugins::manifest: ignoring interface.defaultPrompt' >>"$tui_log"
  printf '%s\n' '2026-04-25T00:00:01Z thread_id=aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa codex_core::client: new' >>"$tui_log"
}

append_exec_approval_line() {
  local tui_log="$1"
  printf '%s\n' '2026-04-25T00:00:02Z thread_id=aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa codex.op="exec_approval"' >>"$tui_log"
}

send_permission_request_hook() {
  local platform="$1"
  local state_dir="$2"
  local tui_log="$3"
  local sound_file="$4"
  local description="${5:-Smoke approval prompt}"
  local log_messages="${6:-1}"
  if (($# >= 6)); then
    shift 6
  else
    set --
  fi
  if [[ "${1:-}" == "env" ]]; then
    shift
  fi
  local -a env_args=(
    "PATH=${FAKE_BIN}:$PATH"
    "NOTIFIER_TEST_LOG=$TEST_LOG"
    "CODEX_BIN=${FAKE_BIN}/codex"
    "CODEX_ALERT_PLATFORM=$platform"
    "CODEX_TUI_LOG_FILE=$tui_log"
    "CODEX_ALERT_STATE_DIR=$state_dir"
    "CODEX_ALERT_SOUND_FILE=$sound_file"
    "CODEX_ALERT_LOG_MESSAGES=$log_messages"
    "CODEX_ALERT_BACKEND_TIMEOUT_SECONDS=${CODEX_ALERT_BACKEND_TIMEOUT_SECONDS:-2}"
    "CODEX_ALERT_REPEAT_SOUND_SECONDS=60"
    "CODEX_ALERT_REPEAT_TOAST_SECONDS=60"
    "FAKE_TERMINAL_NOTIFIER_FAIL=${FAKE_TERMINAL_NOTIFIER_FAIL:-0}"
    "FAKE_TERMINAL_NOTIFIER_HANG=${FAKE_TERMINAL_NOTIFIER_HANG:-0}"
    "FAKE_NOTIFY_SEND_FAIL=${FAKE_NOTIFY_SEND_FAIL:-0}"
  )
  env_args+=("$@")

  env "${env_args[@]}" "$NOTIFIER" --hook-permission-request <<JSON
{"session_id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","transcript_path":null,"cwd":"${TMP_ROOT}","hook_event_name":"PermissionRequest","model":"gpt-test","turn_id":"turn-smoke","tool_name":"Bash","tool_input":{"command":"echo smoke >> /tmp/smoke","description":"${description}"}}
JSON
}

wait_for_log() {
  local pattern="$1"
  local attempts=0
  while (( attempts < 80 )); do
    if [[ -f "$TEST_LOG" ]] && grep -q -- "$pattern" "$TEST_LOG"; then
      return 0
    fi
    attempts=$((attempts + 1))
    sleep 0.1
  done
  return 1
}

assert_log_contains() {
  local pattern="$1"
  wait_for_log "$pattern" || fail "expected backend log to contain: $pattern"
}

assert_log_not_contains() {
  local pattern="$1"
  sleep 0.8
  if [[ -f "$TEST_LOG" ]] && grep -q -- "$pattern" "$TEST_LOG"; then
    fail "expected backend log not to contain: $pattern"
  fi
}

wait_for_no_pending() {
  local state_dir="$1"
  local attempts=0
  while (( attempts < 80 )); do
    if ! find "$state_dir" -maxdepth 1 -name 'codex-approval.*.pending' -print -quit 2>/dev/null | grep -q .; then
      return 0
    fi
    attempts=$((attempts + 1))
    sleep 0.1
  done
  return 1
}

run_real_prompt_case() {
  local name="$1"
  local platform="$2"
  local expected_visual="$3"
  local expected_sound="$4"
  shift 4
  local case_dir="${TMP_ROOT}/${name}"
  local tui_log="${case_dir}/codex-tui.log"
  local sound_file="${case_dir}/sound.aiff"
  mkdir -p "$case_dir"
  : >"$sound_file"

  start_notifier "$platform" "${case_dir}/state" "$tui_log" "$sound_file" "$@"
  send_permission_request_hook "$platform" "${case_dir}/state" "$tui_log" "$sound_file" "Smoke approval prompt" 1 "$@"
  assert_log_contains "$expected_visual"
  assert_log_contains "$expected_sound"
  stop_notifier
  pass "$name"
}

run_auto_approved_case() {
  local case_dir="${TMP_ROOT}/auto-approved"
  local tui_log="${case_dir}/codex-tui.log"
  local sound_file="${case_dir}/sound.aiff"
  mkdir -p "$case_dir"
  : >"$sound_file"

  start_notifier linux "${case_dir}/state" "$tui_log" "$sound_file"
  append_prompt_line "$tui_log"
  append_progress_line "$tui_log"
  assert_log_not_contains 'notify-send'
  assert_log_not_contains 'paplay'
  stop_notifier
  pass "auto-approved command stays silent"
}

run_tui_monitor_starts_at_eof_case() {
  local case_dir="${TMP_ROOT}/tui-starts-at-eof"
  local tui_log="${case_dir}/codex-tui.log"
  local sound_file="${case_dir}/sound.oga"
  local state_dir="${case_dir}/state"
  mkdir -p "$case_dir"
  : >"$sound_file"
  append_exec_approval_line "$tui_log"
  append_progress_line "$tui_log"

  start_notifier linux "$state_dir" "$tui_log" "$sound_file" env FAKE_CODEX_SLEEP=5
  sleep 0.5
  if [[ -f "${state_dir}/codex-approval.events.log" ]] && grep -Eq 'exec_approval|clear_thread_pending_on_progress' "${state_dir}/codex-approval.events.log"; then
    fail "TUI monitor reprocessed historical log lines at startup"
  fi

  send_permission_request_hook linux "$state_dir" "$tui_log" "$sound_file"
  assert_log_contains 'notify-send'
  append_exec_approval_line "$tui_log"
  wait_for_no_pending "$state_dir" || fail "new exec approval did not clear pending alert"
  stop_notifier
  pass "TUI monitor starts at EOF and still clears new approvals"
}

run_model_noise_does_not_suppress_prompt_case() {
  local case_dir="${TMP_ROOT}/model-noise"
  local tui_log="${case_dir}/codex-tui.log"
  local sound_file="${case_dir}/sound.aiff"
  mkdir -p "$case_dir"
  : >"$sound_file"

  start_notifier linux "${case_dir}/state" "$tui_log" "$sound_file"
  send_permission_request_hook linux "${case_dir}/state" "$tui_log" "$sound_file"
  append_model_noise_lines "$tui_log"
  assert_log_contains 'notify-send'
  assert_log_contains 'paplay'
  stop_notifier
  pass "model/plugin log noise does not suppress real prompt"
}

run_remove_hang_case() {
  local case_dir="${TMP_ROOT}/remove-hang"
  local tui_log="${case_dir}/codex-tui.log"
  local sound_file="${case_dir}/sound.aiff"
  local started elapsed
  mkdir -p "$case_dir"
  : >"$sound_file"

  start_notifier darwin "${case_dir}/state" "$tui_log" "$sound_file" env FAKE_CODEX_SLEEP=5 FAKE_TERMINAL_NOTIFIER_REMOVE_HANG=1
  send_permission_request_hook darwin "${case_dir}/state" "$tui_log" "$sound_file" "Smoke approval prompt" 1 FAKE_TERMINAL_NOTIFIER_REMOVE_HANG=1
  assert_log_contains 'terminal-notifier '
  append_exec_approval_line "$tui_log"
  assert_log_contains 'terminal-notifier-remove'
  started="$(date +%s)"
  stop_notifier
  elapsed=$(( $(date +%s) - started ))
  (( elapsed < 12 )) || fail "terminal-notifier -remove blocked shutdown"
  pass "hanging terminal-notifier remove is bounded"
}

run_orphan_lock_case() {
  local case_dir="${TMP_ROOT}/orphan-lock"
  local tui_log="${case_dir}/codex-tui.log"
  local sound_file="${case_dir}/sound.aiff"
  local state_dir="${case_dir}/state"
  mkdir -p "${state_dir}/codex-approval.lock" "$case_dir"
  printf '999999' >"${state_dir}/codex-approval.lock/owner"
  : >"$sound_file"

  start_notifier linux "$state_dir" "$tui_log" "$sound_file"
  send_permission_request_hook linux "$state_dir" "$tui_log" "$sound_file"
  assert_log_contains 'notify-send'
  stop_notifier
  pass "orphan lock is reclaimed"
}

run_self_status_clear_case() {
  local case_dir="${TMP_ROOT}/self-status-clear"
  local state_dir="${case_dir}/state"
  local sound_file="${case_dir}/sound.oga"
  local output
  mkdir -p "$state_dir" "$case_dir"
  : >"$sound_file"
  : >"$TEST_LOG"

  output="$(
    PATH="${FAKE_BIN}:$PATH" \
    NOTIFIER_TEST_LOG="$TEST_LOG" \
    CODEX_BIN="${FAKE_BIN}/codex" \
    CODEX_ALERT_PLATFORM=linux \
    CODEX_ALERT_STATE_DIR="$state_dir" \
    CODEX_ALERT_SOUND_FILE="$sound_file" \
    "$NOTIFIER" --self-test "Smoke self-test"
  )"
  printf '%s' "$output" | grep -q 'self-test sent' || fail "self-test did not report success"
  assert_log_contains 'notify-send'
  assert_log_contains 'paplay'

  output="$(
    PATH="${FAKE_BIN}:$PATH" \
    NOTIFIER_TEST_LOG="$TEST_LOG" \
    CODEX_BIN="${FAKE_BIN}/codex" \
    CODEX_ALERT_PLATFORM=linux \
    CODEX_ALERT_STATE_DIR="$state_dir" \
    CODEX_ALERT_SOUND_FILE="$sound_file" \
    "$NOTIFIER" --status
  )"
  printf '%s' "$output" | grep -q 'notification_backend=notify-send' || fail "status did not include notify-send backend"

  printf '1' >"${state_dir}/codex-approval.fake.pending"
  PATH="${FAKE_BIN}:$PATH" \
  NOTIFIER_TEST_LOG="$TEST_LOG" \
  CODEX_BIN="${FAKE_BIN}/codex" \
  CODEX_ALERT_PLATFORM=linux \
  CODEX_ALERT_STATE_DIR="$state_dir" \
  CODEX_ALERT_SOUND_FILE="$sound_file" \
  "$NOTIFIER" --clear >/dev/null
  [[ ! -e "${state_dir}/codex-approval.fake.pending" ]] || fail "--clear did not remove pending state"

  pass "self-test, status, and clear commands work"
}

run_private_log_case() {
  local case_dir="${TMP_ROOT}/private-log"
  local tui_log="${case_dir}/codex-tui.log"
  local sound_file="${case_dir}/sound.oga"
  local event_log="${case_dir}/state/codex-approval.events.log"
  mkdir -p "$case_dir"
  : >"$sound_file"

  start_notifier linux "${case_dir}/state" "$tui_log" "$sound_file" env CODEX_ALERT_LOG_MESSAGES=0
  send_permission_request_hook linux "${case_dir}/state" "$tui_log" "$sound_file" "Smoke approval prompt" 0
  assert_log_contains 'notify-send'
  stop_notifier
  grep -Fq 'message=[redacted]' "$event_log" || fail "private log mode did not redact messages"
  if grep -Fq 'Smoke approval prompt' "$event_log"; then
    fail "private log mode leaked prompt message"
  fi
  pass "private event log mode redacts prompt messages"
}

run_backend_timeout_fallback_case() {
  local case_dir="${TMP_ROOT}/backend-timeout"
  local tui_log="${case_dir}/codex-tui.log"
  local sound_file="${case_dir}/sound.aiff"
  mkdir -p "$case_dir"
  : >"$sound_file"

  start_notifier darwin "${case_dir}/state" "$tui_log" "$sound_file" env FAKE_TERMINAL_NOTIFIER_HANG=1 CODEX_ALERT_BACKEND_TIMEOUT_SECONDS=0.2
  send_permission_request_hook darwin "${case_dir}/state" "$tui_log" "$sound_file" "Smoke approval prompt" 1 FAKE_TERMINAL_NOTIFIER_HANG=1 CODEX_ALERT_BACKEND_TIMEOUT_SECONDS=0.2
  assert_log_contains 'terminal-notifier '
  assert_log_contains 'osascript '
  stop_notifier
  pass "backend timeout falls back to next visual backend"
}

run_hook_install_uninstall_case() {
  local case_dir="${TMP_ROOT}/hook-install"
  local config_file="${case_dir}/config.toml"
  local installed_path="${case_dir}/bin/codex-approval-notifier"
  local output
  mkdir -p "$(dirname "$config_file")" "$(dirname "$installed_path")"
  cp "$NOTIFIER" "$installed_path"
  chmod +x "$installed_path"
  : >"${case_dir}/sound.oga"
  cat >"$config_file" <<'CONFIG'
model = "gpt-test"

[features]
multi_agent = true
CONFIG

  output="$(
    CODEX_CONFIG_FILE="$config_file" \
    CODEX_ALERT_INSTALLED_PATH="$installed_path" \
    "$installed_path" --install-hook
  )"
  printf '%s' "$output" | grep -q 'installed PermissionRequest hook' || fail "--install-hook did not report success"
  grep -q 'codex_hooks = true' "$config_file" || fail "--install-hook did not enable codex_hooks"
  grep -Fq '[[hooks.PermissionRequest]]' "$config_file" || fail "--install-hook did not add PermissionRequest hook"
  grep -Fq "${installed_path} --hook-permission-request" "$config_file" || fail "--install-hook command path mismatch"

  CODEX_CONFIG_FILE="$config_file" \
  CODEX_ALERT_INSTALLED_PATH="$installed_path" \
  CODEX_ALERT_PLATFORM=linux \
  CODEX_ALERT_SOUND_FILE="${case_dir}/sound.oga" \
  PATH="${FAKE_BIN}:$PATH" \
  NOTIFIER_TEST_LOG="$TEST_LOG" \
  "$installed_path" --doctor >/dev/null || fail "--doctor rejected installed hook config"

  output="$(
    CODEX_CONFIG_FILE="$config_file" \
    CODEX_ALERT_INSTALLED_PATH="$installed_path" \
    "$installed_path" --uninstall-hook
  )"
  printf '%s' "$output" | grep -q 'removed managed PermissionRequest hook' || fail "--uninstall-hook did not report success"
  if grep -Fq '[[hooks.PermissionRequest]]' "$config_file"; then
    fail "--uninstall-hook did not remove PermissionRequest hook"
  fi
  pass "hook install, doctor validation, and uninstall work"
}

FAKE_BIN="${TMP_ROOT}/bin"
make_fake_bin "$FAKE_BIN"
export CODEX_ALERT_WSL=0

run_real_prompt_case "macos terminal-notifier backend" darwin 'terminal-notifier ' 'afplay '
run_real_prompt_case "macos osascript fallback" darwin 'osascript ' 'afplay ' env FAKE_TERMINAL_NOTIFIER_FAIL=1
run_real_prompt_case "linux notify-send backend" linux 'notify-send ' 'paplay '
run_real_prompt_case "linux zenity fallback" linux 'zenity ' 'paplay ' env FAKE_NOTIFY_SEND_FAIL=1
run_auto_approved_case
run_tui_monitor_starts_at_eof_case
run_model_noise_does_not_suppress_prompt_case
run_self_status_clear_case
run_private_log_case
run_backend_timeout_fallback_case
run_remove_hang_case
run_orphan_lock_case
run_hook_install_uninstall_case

printf 'all smoke tests passed\n'
