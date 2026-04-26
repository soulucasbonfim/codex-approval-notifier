#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${CODEX_ALERT_INSTALL_DIR:-${HOME}/.local/bin}"
INSTALL_NAME="${CODEX_ALERT_INSTALL_NAME:-codex-approval-notifier}"
TARGET="${INSTALL_DIR}/${INSTALL_NAME}"
BEGIN_MARKER="# >>> codex-approval-notifier >>>"
END_MARKER="# <<< codex-approval-notifier <<<"
HOOK_BEGIN_MARKER="# >>> codex-approval-notifier-hooks >>>"
HOOK_END_MARKER="# <<< codex-approval-notifier-hooks <<<"
CODEX_CONFIG="${CODEX_CONFIG_FILE:-${HOME}/.codex/config.toml}"

log() {
  printf '[codex-alert-uninstall] %s\n' "$*"
}

detect_shell_rc() {
  if [[ -n "${CODEX_ALERT_SHELL_RC:-}" ]]; then
    printf '%s' "$CODEX_ALERT_SHELL_RC"
    return 0
  fi

  case "${SHELL:-}" in
    */zsh) printf '%s/.zshrc' "$HOME" ;;
    */bash) printf '%s/.bashrc' "$HOME" ;;
    */fish)
      echo "[codex-alert-uninstall] fish shell detected. Automatic shell wrapper uninstall supports zsh/bash only." >&2
      echo "[codex-alert-uninstall] Set CODEX_ALERT_SHELL_RC to the rc file that contains the managed block." >&2
      exit 1
      ;;
    *)
      if [[ -f "${HOME}/.zshrc" ]]; then
        printf '%s/.zshrc' "$HOME"
      else
        printf '%s/.bashrc' "$HOME"
      fi
      ;;
  esac
}

backup_file() {
  local path="$1"
  [[ -f "$path" ]] || return 0
  cp "$path" "${path}.codex-alert.bak.$(date +%Y%m%d-%H%M%S)"
}

remove_managed_block() {
  local path="$1"
  local tmp
  [[ -f "$path" ]] || return 0
  tmp="${path}.codex-alert.tmp.$$"
  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
    $0 == begin {skip=1; next}
    $0 == end {skip=0; next}
    !skip {print}
  ' "$path" >"$tmp"
  mv "$tmp" "$path"
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

main() {
  local shell_rc
  shell_rc="$(detect_shell_rc)"

  if [[ -f "$shell_rc" ]]; then
    backup_file "$shell_rc"
    remove_managed_block "$shell_rc"
    log "updated shell rc: $shell_rc"
  else
    log "shell rc not found: $shell_rc"
  fi

  if [[ -x "$TARGET" ]]; then
    CODEX_CONFIG_FILE="$CODEX_CONFIG" CODEX_ALERT_INSTALLED_PATH="$TARGET" "$TARGET" --uninstall-hook
  elif [[ -f "$CODEX_CONFIG" ]]; then
    backup_file "$CODEX_CONFIG"
    remove_managed_hook_block "$CODEX_CONFIG"
    log "updated Codex config hooks: $CODEX_CONFIG"
  fi

  if [[ -f "$TARGET" ]]; then
    rm -f "$TARGET"
    log "removed notifier: $TARGET"
  fi

  log "uninstalled."
}

main "$@"
