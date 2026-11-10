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
