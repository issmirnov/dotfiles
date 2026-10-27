# Claude Code config

Personal config for [Claude Code](https://claude.com/claude-code) — the CLI/desktop coding agent. These files are symlinked into `~/.claude/` by dotbot (see `default.conf.yaml`):

| Source (this dir)         | Symlinked to                       |
|---------------------------|------------------------------------|
| `settings.json`           | `~/.claude/settings.json`          |
| `statusline-command.sh`   | `~/.claude/statusline-command.sh`  |

Edit the files here — `~/.claude/settings.json` is just a pointer.

## `settings.json`

The user-level Claude Code config. Notable knobs in use:

- **Model** — `opus[1m]` (Opus with the 1M-token context window).
- **Effort tuning** — _two_ knobs are intentionally set in tandem:
  - `effortLevel: "xhigh"` — top-level effort hint.
  - `env.CLAUDE_CODE_EFFORT_LEVEL: "max"` — runtime override via env var.

  The env var is the modern lever; the top-level field is a fallback. Setting both means you don't need to remember which one wins after a Claude Code release. Allowed values escalate roughly `low → medium → high → xhigh → max`.
- **`env.ENABLE_TOOL_SEARCH: "true"`** — defers some tool schemas behind `ToolSearch` to keep the system prompt smaller; tools are loaded on demand.
- **`alwaysThinkingEnabled: true`** — extended thinking always on.
- **`skipDangerousModePermissionPrompt: true`** — pairs with the `cc = claude --dangerously-skip-permissions` shell alias so the bypass-permissions warning doesn't prompt every launch.
- **`verbose: true`** — fuller transcript output.
- **`hooks.Notification`** — fires `notify-send` (Linux desktop notifications) when Claude wants attention.
- **`enabledPlugins`** — plugins from the marketplaces below: `superpowers`, `presentation-tools`, `skill-codex`, `nonstop`, `git-recon`, `visual-explainer`, `gopls-lsp`, `document-skills`.
- **`extraKnownMarketplaces`** — registers GitHub-hosted plugin marketplaces beyond the defaults.
- **`statusLine`** — points to `statusline-command.sh` (see below).

## `statusline-command.sh`

Custom status line renderer. Claude Code runs it on each update and shows each printed line as a row, above its own permission-mode row. It prints two lines:

1. **Where the session is:** the host (dim locally, bold yellow over SSH), the directory Claude was launched in, `🌿 <worktree>`, `→ <folder>` after Claude moves away from the launch directory, the git branch with a dirty mark, and the session name.
2. **What the session uses:** model, effort, context bar, cost, lines changed, cache hit rate, duration, and rate-limit headroom.

The launch directory comes from `worktree.original_cwd`, else `workspace.project_dir`, because EnterWorktree points `project_dir` at the worktree. If line 1 is wider than the window (`$COLUMNS`), the launch path shortens fish-style, for example `~/P/1/a/shotcraft-videos`.

The script caches git results for 10 seconds. Temp files are per session, so concurrent sessions don't overwrite each other's state. Tests: `python3 -m unittest -v tests.test_statusline`.

## Workspace-trust quirk (gotcha)

Claude Code does **not** persist `hasTrustDialogAccepted: true` for `$HOME` through the normal "Yes, I trust this folder" UI flow when launched with `--dangerously-skip-permissions`. The dialog re-prompts on every launch.

Fix by writing the flag directly into `~/.claude.json` (this file is _not_ part of dotfiles — it's local state):

```sh
jq '.projects["/Users/vania"].hasTrustDialogAccepted = true' ~/.claude.json > ~/.claude.json.tmp \
  && command mv -f ~/.claude.json.tmp ~/.claude.json
```

Re-apply if a Claude Code upgrade flips it back. Note `command mv -f` is needed because `mv` is aliased `-i` (interactive) in this user's zsh.

The workspace-trust flag (per-project, in `~/.claude.json`) is **separate** from the bypass-permissions warning suppression (`skipDangerousModePermissionPrompt` in `settings.json`). They look similar; they aren't.

## What's deliberately _not_ in this dir

- `~/.claude.json` — large local state file (onboarding flags, project trust, caches). Not portable across machines, not version-controlled.
- `~/.claude/settings.local.json` — per-machine overrides that shouldn't be shared (kept out of the symlink intentionally).
- `~/.claude/projects/`, `~/.claude/sessions/`, `~/.claude/history.jsonl` — runtime state and conversation history.
