# Codex status line

The shared status line shows hostname, directory, Git branch, model/effort,
context remaining, and five-hour/weekly usage headroom. It uses theme colors.
Hostname comes first so it stays visible in narrow terminals. Codex omits
unavailable fields.

`./install` runs the installer when Codex is on PATH. To apply it separately:

```sh
python3 codex/install-statusline.py
```

Requires Python 3.11 or newer. Verified with Codex CLI 0.167.0.
Restart Codex after installation. `/statusline` can adjust the display, but
the next dotfiles install restores the settings in `statusline.toml`.

The installer updates only `tui.status_line` and `tui.status_line_use_colors`
in `$CODEX_HOME/config.toml` (default `~/.codex/config.toml`). Other settings
and comments stay intact. The full config remains local, including model,
provider, permissions, and project settings.

Before a change, the installer saves a private `config.toml.bak-statusline-*`
backup beside the config. Repeated installs make no changes or new backups.
It supports a conventional `[tui]` table, including multiline status-line
arrays. For unsupported layouts, such as quoted keys or inline tables, copy
the two settings from `statusline.toml` manually. Validation rejects edits
that alter other settings.

To undo an installation, restore its backup after checking for later local
edits. On a fresh config, remove the two status-line keys instead.

Validation: `python3 -m unittest -v tests.test_codex_statusline`.

## OOM score hook

`~/.codex/hooks.json` is local, not part of the dotfiles, and Orca writes its
own entries there. On the Linux boxes that run Orca, it also has one
SessionStart entry added by hand on 2026-11-26. That entry runs the command
from the first SessionStart hook in `claude/settings.json` (see
`claude/README.md`), which raises the codex process's OOM score to 700.

The entry is the last group in `SessionStart`. Codex keys each hook's trust by
its position, for example `hooks.json:session_start:1:0`, so adding it last
leaves the keys of Orca's entries unchanged. The app server's `hooks/list`
reports a new entry as `untrusted` until `config.toml` records its hash. To
trust it, take the entry's `currentHash` from `hooks/list` and write it to
`hooks.state."<key>".trusted_hash` with `config/batchWrite`. Orca trusts its
own entries the same way. Trust the entry again after changing its command.
