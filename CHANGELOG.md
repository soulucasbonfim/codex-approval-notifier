# Changelog

## 1.0.6 - 2026-05-09

- Migrate managed feature flag from deprecated `codex_hooks = true` to `hooks = true`.
- Update hook install/validation logic to enforce `features.hooks`.
- Update README and smoke test expectations for Codex `v0.130.0+`.

## 1.0.5 - 2026-04-27

- Improve Linux notification behavior defaults for `notify-send` with `normal` urgency, transient mode, and 5-second expiration.
- Add Linux notification cleanup by closing active notifications through DBus when approvals are resolved.
- Add a defensive scheduled DBus close for daemons that do not honor `--expire-time`.
- Prevent noisy `/dev/tty` errors from terminal bell fallback in non-interactive contexts.
- Avoid selecting `aplay` for unsupported sound formats like `.oga` to prevent distorted audio.
- Align README terminology with current Codex approval UI text: "Yes, and don't ask again for commands that start with ...".
- Update script help text and README defaults for new Linux notification variables.

## 1.0.4 - 2026-04-27

- Avoid `PermissionRequest` hook timeouts when multiple approval prompts start in parallel.

## 1.0.3 - 2026-04-27

- Add WSL support through Windows toast notifications and Windows sound.
- Install the Windows toast AppUserModelID automatically on WSL when WinRT is available.
- Use monotonic reminder scheduling to avoid duplicate or early alarms when the WSL wall clock shifts.
- Keep WSL toasts single-shot while sound reminders repeat until approval or timeout.
- Count the initial WSL notification sound as part of the reminder window.
- Queue pending notifications outside the `PermissionRequest` hook to avoid Codex hook timeout warnings.
- Fix restart cleanup for notifier lock directories.

## 1.0.2 - 2026-04-26

- Start TUI log cleanup monitoring at the current end of `codex-tui.log`.
- Prevent delayed approval cleanup caused by replaying old Codex log history.

## 1.0.1 - 2026-04-26

- Replace persistent `tail -F` TUI log monitoring with offset-based polling.
- Fix noisy shutdown diagnostics such as `Killed: 9` after exiting Codex.
- Keep stale `tail -F` detection in diagnostics for cleanup of older notifier processes.

## 1.0.0 - 2026-04-26

- Initial public-ready release.
- Detects Codex approval prompts through the `PermissionRequest` hook.
- Sends desktop notifications and sound reminders on macOS and Linux.
- Keeps TUI log monitoring only for clearing stale pending alerts.
- Supports multi-session reminder ownership.
- Includes installer, uninstaller, reset script, doctor command, backend test, and smoke tests.
