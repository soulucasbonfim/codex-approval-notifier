# Changelog

## 1.0.3 - 2026-04-27

- Add WSL support through Windows toast notifications and Windows sound.
- Install the Windows toast AppUserModelID automatically on WSL when WinRT is available.
- Use monotonic reminder scheduling to avoid duplicate or early alarms when the WSL wall clock shifts.
- Keep WSL toasts single-shot while sound reminders repeat until approval or timeout.
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
