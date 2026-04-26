#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_NOTIFIER="${CODEX_ALERT_SOURCE_NOTIFIER:-${SCRIPT_DIR}/codex-approval-notifier.sh}"
INSTALL_DIR="${CODEX_ALERT_INSTALL_DIR:-${HOME}/.local/bin}"
INSTALL_NAME="${CODEX_ALERT_INSTALL_NAME:-codex-approval-notifier}"
TARGET="${INSTALL_DIR}/${INSTALL_NAME}"
BEGIN_MARKER="# >>> codex-approval-notifier >>>"
END_MARKER="# <<< codex-approval-notifier <<<"
CODEX_CONFIG="${CODEX_CONFIG_FILE:-${HOME}/.codex/config.toml}"

log() {
  printf '[codex-alert-install] %s\n' "$*"
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
      echo "[codex-alert-install] fish shell detected. Automatic shell wrapper install supports zsh/bash only." >&2
      echo "[codex-alert-install] Set CODEX_ALERT_SHELL_RC to a zsh/bash rc file or install the wrapper manually." >&2
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

append_managed_block() {
  local path="$1"
  cat >>"$path" <<EOF

${BEGIN_MARKER}
# Notify when Codex is waiting for an approval prompt.

codex() {
  if [ -n "\${CODEX_NO_ALERT:-}" ]; then
    command codex "\$@"
    return \$?
  fi

  local notifier="\${CODEX_ALERT_NOTIFIER:-${TARGET}}"
  if [ -x "\$notifier" ]; then
    "\$notifier" "\$@"
  else
    command codex "\$@"
  fi
}
${END_MARKER}
EOF
}

main() {
  local shell_rc
  shell_rc="$(detect_shell_rc)"

  if [[ ! -f "$SOURCE_NOTIFIER" ]]; then
    echo "[codex-alert-install] notifier not found: $SOURCE_NOTIFIER" >&2
    exit 1
  fi

  mkdir -p "$INSTALL_DIR"
  cp "$SOURCE_NOTIFIER" "$TARGET"
  chmod +x "$TARGET"
  log "installed notifier: $TARGET"

  mkdir -p "$(dirname "$shell_rc")"
  touch "$shell_rc"
  backup_file "$shell_rc"
  remove_managed_block "$shell_rc"
  append_managed_block "$shell_rc"
  log "updated shell rc: $shell_rc"
  CODEX_CONFIG_FILE="$CODEX_CONFIG" CODEX_ALERT_INSTALLED_PATH="$TARGET" "$TARGET" --install-hook
  log "open a new terminal or run: source \"$shell_rc\""
}

main "$@"
