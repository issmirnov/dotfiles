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
- **`modelSettings`** saves `xhigh` as Opus 5.5's effort level, so every session starts there. Opus 5.5 and newer models ignore a top-level `effortLevel` in this file, which now covers only older models. Running `/effort xhigh` writes the same entry. `max` can't be saved, so type `/effort max` in a session that needs it.
- **`env.CLAUDE_CODE_SUBAGENT_EFFORT: "high"`** runs every subagent that has no `effort` of its own at `high`, whatever level the session uses. An agent's `effort` frontmatter and a level Claude passes for one run still win. The variable is in the Claude Code client but not in its docs. If a release drops it, a subagent on the session's model follows the session, and other subagents use their model's default (`medium` on the 5.5 models).
- Leave `CLAUDE_CODE_EFFORT_LEVEL` unset. It overrides every other level, subagents included, so no subagent could run lower than the session.
- **`env.ENABLE_TOOL_SEARCH: "true"`** — defers some tool schemas behind `ToolSearch` to keep the system prompt smaller; tools are loaded on demand.
- **`alwaysThinkingEnabled: true`** — extended thinking always on.
- **`autoCompactWindow: 500000`** compacts the main conversation at 500K tokens instead of near the 1M limit. Every call re-reads the whole context from cache, so a long thread's cost grows with the square of its length. On a measured 1,000-call session, 300K was the cheapest point. 500K compacts half as often there (3 times instead of 6) for about 30% more, which suits long marathon sessions.
- **`promptCacheTtl: "1h"`** keeps the main conversation's prompt cache for an hour instead of five minutes. Cache writes cost 2x the input price instead of 1.25x. In exchange, a 5 to 60 minute wait on bot reviews or subagents no longer rewrites the whole context. Subagents keep the 5-minute default, since they rarely pause.
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

The script saves the launch directory at a session's first render (`workspace.project_dir`, or `worktree.original_cwd` in a worktree session) to a per-session file in `/tmp`. The payload loses it later: EnterWorktree points `project_dir` at the worktree, and `worktree.original_cwd` is wherever Claude was when it entered. If line 1 is wider than the window (`$COLUMNS`), the launch path shortens fish-style, for example `~/P/1/a/shotcraft-videos`.

The bracket at the end of line 1 holds the name other sessions use to message this one (ListAgents, SendMessage). Each session picks its own name and saves it in `~/.claude/sessions/<pid>.json`, or under `$CLAUDE_CONFIG_DIR` if set. `/rename` updates that entry too. The payload has `session_name` only after `/rename`, so the script reads the entry whose `sessionId` matches and falls back to `session_name`. It drops backslashes and control characters from the name, because line 1 goes through `printf %b`.

The script caches git results for 10 seconds. Temp files are per session, so concurrent sessions don't overwrite each other's state. Tests: `python3 -m unittest -v tests.test_statusline`.

## Shell options for Claude sessions

`zsh/config/zz-claude-code.zsh` turns off `nomatch` and `aliases` in shells that have `CLAUDECODE` set, which Claude Code sets for the shells it starts. An unmatched glob then reaches the command as typed. Commands run as written, not through the interactive aliases such as `rm -i`, `cp -i` and `mv -i`. In 21 days of Claude sessions, these two causes made about 180 of 1,779 Bash calls fail. `noclobber` stays on. Commands you type with `!` in a session also run without aliases.

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
