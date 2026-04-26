# Contributing

Thanks for considering a contribution to Codex Approval Notifier.

## Development Setup

Clone the repository:

```bash
git clone https://github.com/soulucasbonfim/codex-approval-notifier.git
cd codex-approval-notifier
```

Run the local checks:

```bash
bash -n install.sh uninstall.sh scripts/*.sh
./scripts/test-codex-approval-notifier.sh
```

If ShellCheck is available, run:

```bash
shellcheck --exclude=SC2317 \
  scripts/codex-approval-notifier.sh \
  scripts/install-codex-approval-notifier.sh \
  scripts/restart-codex-approval-monitor.sh \
  scripts/uninstall-codex-approval-notifier.sh \
  scripts/test-codex-approval-notifier.sh \
  install.sh \
  uninstall.sh
```

## Pull Requests

- Keep changes focused and small.
- Include tests for behavior changes when practical.
- Update `README.md` or `CHANGELOG.md` when user-facing behavior changes.
- Avoid adding platform-specific assumptions unless they are guarded and documented.

## Reporting Bugs

Please include:

- Operating system and shell.
- Codex CLI version when available.
- Notification backend in use.
- Output from `codex-approval-notifier --doctor`.
- Whether the issue happens with one Codex session or multiple sessions.

