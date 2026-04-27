# Codex Approval Notifier

[![CI](https://github.com/soulucasbonfim/codex-approval-notifier/actions/workflows/ci.yml/badge.svg)](https://github.com/soulucasbonfim/codex-approval-notifier/actions/workflows/ci.yml)

Desktop notification and sound reminder for Codex approval prompts.

Current release: `1.0.5`.

The notifier uses Codex's `PermissionRequest` hook as the primary approval signal, then watches Codex's TUI log (`~/.codex/log/codex-tui.log`) only to clear stale alerts when the approval/command flow advances. This avoids pseudo-terminal rendering issues and avoids heuristic false positives from normal command logs.

License: MIT. See `LICENSE`.

## Requirements

- Codex CLI available as `codex`.
- Bash.
- macOS or Linux.
- Core shell tools: `tail`, `sed`, `awk`, `perl`, `dd`, and one of `shasum`, `sha1sum`, or `openssl`.

Notification backends:

- macOS preferred: `terminal-notifier`.
- macOS fallback: built-in `osascript display notification`.
- WSL: Windows toast through PowerShell/WinRT, with Windows Forms fallback.
- Linux preferred: `notify-send`.
- Linux fallback: `zenity`, then `kdialog`.

Sound backends:

- macOS: `afplay`, then terminal bell.
- WSL: Windows sound through PowerShell.
- Linux: `paplay`, then `canberra-gtk-play`, then `aplay` (for `wav`/`au`/`voc` files), then terminal bell.

Linux package hints:

- Debian/Ubuntu: `sudo apt install libnotify-bin pulseaudio-utils libcanberra-gtk-module alsa-utils zenity`
- Fedora: `sudo dnf install libnotify pulseaudio-utils libcanberra-gtk3 alsa-utils zenity`
- Arch: `sudo pacman -S libnotify libpulse libcanberra alsa-utils zenity`

macOS package hint:

- Optional preferred notifier: `brew install terminal-notifier`

Only one visual notification backend is required. Sound is optional and can be disabled with `CODEX_ALERT_PLAY_SOUND=0`.

Linux `notify-send` defaults:

- `CODEX_ALERT_NOTIFY_EXPIRE_MS=5000`
- `CODEX_ALERT_NOTIFY_URGENCY=normal`
- `CODEX_ALERT_NOTIFY_TRANSIENT=1`

These defaults aim for a visible banner that auto-dismisses, while avoiding sticky notification-center entries on common GNOME setups.

## Quick Start

```bash
git clone https://github.com/soulucasbonfim/codex-approval-notifier.git
cd codex-approval-notifier
./install.sh
```

The installer:

- Copies `codex-approval-notifier.sh` to `${HOME}/.local/bin/codex-approval-notifier`.
- Adds a managed `codex()` shell wrapper to `~/.zshrc` or `~/.bashrc`.
- Enables `codex_hooks` and adds a managed `PermissionRequest` hook to `~/.codex/config.toml`.
- On WSL, installs the Windows toast AppUserModelID when WinRT is available.
- Creates a backup of the shell rc before editing it.

Automatic shell wrapper installation supports zsh and bash. After installing, open a new terminal or reload your shell rc:

```bash
# zsh
source ~/.zshrc

# bash
source ~/.bashrc
```

If you use another shell, set `CODEX_ALERT_SHELL_RC` to a zsh/bash-compatible rc file or install the wrapper manually.

Start a new Codex session after installing so Codex loads the managed shell wrapper and hook configuration.

Validate the installation:

```bash
codex-approval-notifier --doctor
```

If `--doctor` reports a missing hook, run:

```bash
codex-approval-notifier --install-hook
```

To bypass the notifier for one command:

```bash
CODEX_NO_ALERT=1 codex
```

## How Detection Works

The reliable approval signal is the Codex `PermissionRequest` hook:

```toml
[features]
codex_hooks = true

[[hooks.PermissionRequest]]
matcher = "^Bash$"

[[hooks.PermissionRequest.hooks]]
type = "command"
command = '/path/to/codex-approval-notifier --hook-permission-request'
timeout = 2
statusMessage = "Notify approval request"
```

The hook creates the pending alert and exits with no output, so Codex still shows its normal approve/deny prompt. The notifier does not approve or deny anything.

The TUI log monitor remains active only for cleanup:

- Clear alerts when Codex records approval/command progress.
- Keep one reminder owner across multiple open Codex sessions.
- Reclaim stale locks and rotate notifier logs.

## Uninstall

```bash
./uninstall.sh
```

Then open a new terminal or reload your shell rc:

```bash
# zsh
source ~/.zshrc

# bash
source ~/.bashrc
```

Start a new terminal session after uninstalling so the managed shell wrapper is no longer active.

## Diagnostics

```bash
codex-approval-notifier --doctor
```

Or from this repository:

```bash
./scripts/codex-approval-notifier.sh --doctor
```

`--doctor` prints the effective notification backend, sound backend, process state, state directory, and Linux `notify-send` capabilities when available. It exits non-zero if no visual notification backend is available.

Useful operational commands:

```bash
codex-approval-notifier --status
codex-approval-notifier --self-test
codex-approval-notifier --backend-test
codex-approval-notifier --clear
codex-approval-notifier --install-hook
codex-approval-notifier --uninstall-hook
codex-approval-notifier --install-windows-toast
codex-approval-notifier --uninstall-windows-toast
codex-approval-notifier --tail-events
```

- `--status`: compact health summary.
- `--self-test`: sends one toast/sound without requiring a Codex approval prompt.
- `--backend-test`: tests every available visual/sound backend individually.
- `--clear`: clears pending notifier state without killing Codex.
- `--install-hook`: installs the managed `PermissionRequest` hook in `~/.codex/config.toml`.
- `--uninstall-hook`: removes the managed hook block.
- `--install-windows-toast`: installs the WSL Windows toast AppUserModelID shortcut.
- `--uninstall-windows-toast`: removes the WSL Windows toast shortcut.
- `--tail-events`: follows the notifier troubleshooting log.

## Reset Monitor

Close Codex first, then run:

```bash
./scripts/restart-codex-approval-monitor.sh
```

The reset script stops stale notifier/tail processes and clears notifier state. It intentionally does not close Codex sessions for you.

Dry-run:

```bash
./scripts/restart-codex-approval-monitor.sh --dry-run
```

## Local Smoke Test

The smoke test uses fake notification backends and does not require a real Codex approval prompt:

```bash
./scripts/test-codex-approval-notifier.sh
```

It covers:

- macOS `terminal-notifier` backend.
- macOS `osascript` fallback.
- Linux `notify-send` backend.
- Linux `zenity` fallback.
- `PermissionRequest` hook alert creation.
- Auto-approved command suppression.
- Self-test command.
- Status command.
- Clear command.
- Privacy mode with redacted prompt messages.
- Hook install/uninstall and `--doctor` hook validation.
- Backend timeout fallback.
- Bounded handling for a hanging `terminal-notifier -remove`.
- Orphan lock recovery.

## Behavior Matrix

| Event | Toast | Sound | Reason |
| --- | --- | --- | --- |
| Real Codex approval prompt | Yes | Yes | Codex emitted a `PermissionRequest` hook. |
| WSL pending prompt remains unapproved | No repeat toast | Initial sound, then repeats every 5 seconds until timeout | Windows toasts stay single-shot while reminders continue. |
| Auto-approved command after selecting "Yes, and don't ask again for commands that start with ..." | No | No | No `PermissionRequest` hook is emitted because Codex auto-approves future commands for that prefix. |
| Normal sandboxed command | No | No | No approval path. |
| Multiple prompts in parallel | One grouped alert per thread | Independent reminder state per thread | Avoids cross-session suppression. |
| Original monitor-owner session exits | Existing live session takes over reminders | Continues alerting pending prompts | Prevents alert loss in multi-session usage. |
| Click macOS notification Show with `terminal-notifier` | Reminders silence for that pending prompt | Stops repeats | The click writes an ack flag. |

Linux notification click callbacks are not portable across notification daemons. The notifier still repeats sound/toast until Codex clears the pending approval or the pending timeout expires. On WSL, only sound repeats after the initial Windows toast.

## Files Created

Default state directory:

```text
${TMPDIR:-/tmp}/codex-approval-notifier/$USER
```

Important files:

- `codex-approval.events.log`: troubleshooting log, rotated to 1 MB.
- `codex-approval.monitor_pid`: active monitor owner process.
- `codex-approval.<group-hash>.pending`: pending approval state for one Codex thread/group.
- `codex-approval.<group-hash>.ack`: notification click acknowledgement for one pending prompt.
- `codex-approval.<group-hash>.notify_id`: Linux notification id when `notify-send --print-id` is available.
- `codex-approval.<group-hash>.message`, `.last_sound`, `.last_toast`, `.next_sound`, `.next_toast`: small per-thread reminder state files rewritten in place.

Each open Codex session runs a lightweight supervisor. Exactly one supervisor owns reminder scheduling at a time. If that session exits while other Codex sessions remain open, another supervisor claims ownership automatically.

Codex itself owns:

- `~/.codex/log/codex-tui.log`

This notifier reads that file but does not rotate, truncate, or delete it. The file is written by Codex itself and can grow over time because it records TUI/runtime activity across Codex sessions. It is intentionally outside this notifier's cleanup policy so the notifier does not destroy Codex troubleshooting history.

If you want to inspect its size:

```bash
ls -lh ~/.codex/log/codex-tui.log
```

If you decide to clean it manually, close Codex first. The conservative option is to move it aside instead of deleting it:

```bash
mv ~/.codex/log/codex-tui.log ~/.codex/log/codex-tui.log.bak
```

Codex should recreate the log on the next run. Do this only when you do not need old Codex troubleshooting history.

## Configuration

Common variables:

```bash
export CODEX_ALERT_PLAY_SOUND=1
export CODEX_ALERT_SOUND=Funk
export CODEX_ALERT_NOTIFY_EXPIRE_MS=5000
export CODEX_ALERT_NOTIFY_URGENCY=normal
export CODEX_ALERT_NOTIFY_TRANSIENT=1
export CODEX_ALERT_BACKEND_TIMEOUT_SECONDS=2
export CODEX_ALERT_LOG_MESSAGES=1
export CODEX_ALERT_HOOK_PERMISSION_REQUEST_ENABLED=1
export CODEX_ALERT_PROGRESS_SUPPRESS_SECONDS=0.5
export CODEX_ALERT_OWNER_CHECK_SECONDS=1
export CODEX_ALERT_ORPHAN_LOCK_GRACE_SECONDS=1
export CODEX_ALERT_REMOVE_TOAST_TIMEOUT_SECONDS=1
export CODEX_ALERT_REPEAT_SOUND_SECONDS=5
export CODEX_ALERT_REPEAT_TOAST_SECONDS=30
```

WSL Windows options:

```bash
export CODEX_ALERT_WINDOWS_APP_ID=Codex
export CODEX_ALERT_WINDOWS_SHORTCUT_NAME='Codex Approval Notifier.lnk'
export CODEX_ALERT_WINDOWS_SOUND_FILE='C:\Windows\Media\Speech On.wav'
```

macOS advanced option:

```bash
export CODEX_ALERT_TOAST_SENDER_BUNDLE_ID=com.apple.Terminal
```

This is optional. Leave it unset for generic notifications without binding the notifier to a specific editor or terminal.

## Privacy

`codex-approval.events.log` can include approval prompt justifications because those messages are useful for troubleshooting missed, duplicated, or stale alerts. The file is local, lives under the notifier state directory, and is rotated to 1 MB. Do not publish this log.

To redact prompt messages in the event log:

```bash
export CODEX_ALERT_LOG_MESSAGES=0
```

## Troubleshooting

Run:

```bash
codex-approval-notifier --doctor
```

If alerts stop:

1. Exit Codex.
2. Run `./scripts/restart-codex-approval-monitor.sh`.
3. Start Codex again from a fresh terminal.

If the terminal UI flickers or typed text disappears:

1. Start Codex with `CODEX_NO_ALERT=1 codex` to verify whether the issue is notifier-related.
2. Run `codex-approval-notifier --doctor` and inspect the state directory.
