# Two-line Claude Code status line with host and launch directory: design

**Date:** 2026-10-26
**Status:** DESIGN (approved in brainstorming; not yet implemented)
**Author:** Ivan + Claude

## Motivation

`claude/statusline-command.sh` prints one line. The line starts with
`➜ <folder>`, the basename of `workspace.current_dir`. That causes two problems.

1. **The folder follows Claude, not the launch.** A Bash `cd` persists if it
   stays under the launch directory, so a session started in `~` can end up
   anywhere. 23 sessions active in the 4 days to 2026-10-26 changed folders
   mid-session. One went `~` → `ops/fleet` → `ops/argo-k8s` →
   `argo-k8s-worktrees/longhorn-upgrade`. Entering a worktree moves the folder
   too. Nothing on screen shows where the session started.
2. **No host.** Some foot windows run `ssh laptop` or
   `ssh claude@claude-netops…`. Their titles look the same as local sessions
   (`✳ <title>`). Nothing on screen shows which machine runs the session.

The line is also full. In a half-width foot window, the session name, model,
effort, context bar, cost, cache and duration leave no room for more.

## Goal

- Show the host and the launch directory in every session.
- Show when Claude moves away from the launch directory, and where it went.
- Split the output into two lines:
  - Line 1 holds the parts that vary in length: host, directories, worktree,
    git, session name.
  - Line 2 holds the same segments every time: model, effort, context bar and
    the usage numbers.

## Data sources (Claude Code 2.1.311)

| Shown | Source | Notes |
|---|---|---|
| Host | bash `$HOSTNAME`, cut at the first `.` | No fork. `hexane` here, `lorium` on the laptop. Bash keeps a value passed in the environment, so tests can pin it. |
| Launch directory | At the session's first render: `.worktree.original_cwd // .workspace.project_dir`. The script saves it to `/tmp/claude-statusline-launch-<session_id>.dir` and reuses it. | The payload loses the launch directory later. EnterWorktree points `project_dir` at the worktree (seen in the 2.1.311 binary). `worktree.original_cwd` is wherever Claude was when it entered, so a `cd` before the worktree changes it. ExitWorktree restores `project_dir`. |
| Current directory | `.workspace.current_dir // .cwd` | Same as today. |
| Worktree | `.worktree.name`, `.worktree.path` | Present only in a worktree session. |
| Width | `$COLUMNS` | Claude Code sets it before it runs the script. |
| SSH | `$SSH_CONNECTION` is not empty | The SSH login sets it. claude and the script inherit it. |

Claude Code shows each output line as its own row. Its own footer row
(`▸▸ bypass permissions on …`) comes after them. The script cannot write to
that footer row.

## Layout

```
hexane ~/.dotfiles git:(master) ✗ [Claude statusline host and directory]
Opus 5.5 ⚡max | ██░░░░░░░░ 14% | ~$2.17 | cache 99% | ⏱ 16m
▸▸ bypass permissions on (shift+tab to cycle)        ← Claude Code's own row
```

### Line 1: where the session is

Segments, left to right. Each segment shows only when it applies.

1. **Host.** Dim for a local session. Bold yellow if `$SSH_CONNECTION` is not
   empty.
2. **Launch directory.** Cyan. A leading `$HOME` becomes `~` only for `$HOME`
   itself or a `$HOME/` prefix, so `/home/vania2` stays as it is. This segment
   replaces `➜ <folder>`.
3. **`🌿 <name>`.** Worktree sessions only. It moves here from after the git
   segment.
4. **`→ <folder>`.** The basename of the current directory, with a dim arrow
   and a cyan name. It shows only if the current directory is not the launch
   directory. It does not show at the worktree root (`worktree.path`). The 🌿
   segment already says that.
5. **`git:(<branch>) ✗`.** For the current directory, with the same 10-second
   cache as today.
6. **`[<session name>]`.** Same as today.

Examples:

```
hexane ~ → argo-k8s git:(main) [fleet-parity]
hexane ~/Projects/1.Personal/ops/argo-k8s 🌿 upgrade git:(worktree-upgrade)
hexane ~/Projects/1.Personal/ops/argo-k8s 🌿 upgrade → charts git:(worktree-upgrade)
lorium ~/.dotfiles git:(master)        ← "lorium" in bold yellow: the session runs over SSH
```

### Line 2: what the session uses

1. Model and effort, as today.
2. The context bar and percentage, as today.
3. Today's trailing segments, in today's order and colors: cost, lines changed,
   cache %, duration, tokens per minute with the 5h/7d limits, output style.

Each optional segment hides under the same rules as today. Line 2 is never
empty, because the model is always present.

## Narrow windows

The script measures the visible width of line 1. It strips the color codes and
counts characters with `${#s}` (UTF-8 locale). If the width is more than
`COLUMNS - 4`, the script shortens the launch directory fish-style:

- Every component except the last becomes its first character.
- A component that starts with `.` keeps two characters.

Examples: `~/Projects/1.Personal/ai/shotcraft-videos` becomes
`~/P/1/a/shotcraft-videos`. `~/.dotfiles-worktrees/x` becomes `~/.d/x`.

The 4 columns of slack cover the interface's built-in spacing and the
double-width 🌿. Nothing else is cut. If line 1 still does not fit, Claude Code
truncates it. If `COLUMNS` is not set, the script does not shorten the path.
Line 2 has no width check.

## Edge cases

- **No `project_dir` (older Claude Code):** the launch directory falls back to
  the current directory. Line 1 then shows the host and the full path of the
  current directory.
- **Launch directory outside `$HOME`:** shown as an absolute path.
- **Current directory inside or outside the launch directory:** both show only
  the basename after `→`. No relative paths.
- **No git repository:** no git segment, as today.
- **Claude moves, then enters a worktree:** line 1 keeps the saved launch
  directory. The live demo found this case: `worktree.original_cwd` pointed at
  the subdirectory.
- **No `session_id`:** the script saves nothing and reads the launch directory
  from the payload on each render.

## Testing

Add `tests/test_statusline.py` (unittest, like `tests/test_zsh_paste.py`). Each
test does this:

1. Run `claude/statusline-command.sh` with a JSON payload on stdin.
2. Pin `HOSTNAME`, `HOME` and `COLUMNS`, and set or unset `SSH_CONNECTION`.
3. Give each payload a unique `session_id`, so the `/tmp` cache files do not
   collide.
4. Strip the color codes and check the two lines.

Cases:

- Not moved: line 1 is `<host> ~/proj`, with no `→`.
- Moved: the directory part of line 1 ends with `→ <basename>`.
- Worktree session at the worktree root: the launch directory is
  `original_cwd`, `🌿 <name>` shows, and `→` does not.
- Worktree session in a subdirectory: `🌿 <name> → <subdir>`.
- One session that moves into `sub/` and then enters a worktree: line 1 keeps
  the launch directory from the first render.
- SSH: the raw output wraps the host in bold yellow. Local: dim.
- Narrow `COLUMNS`: the script shortens the path. Wide `COLUMNS`: the full
  path shows.
- `HOME=/home/vania` and a path under `/home/vania2`: no `~`.
- Line 2 holds the model, effort, bar, cost, cache and duration. Line 1 holds
  none of them.

Add a `test-statusline` CI job next to `test-zsh-paste`. The `ubuntu-latest`
image has bash and jq.

## Rollout

1. Build on `feat/statusline-host-dir`, in a worktree off `origin/master`.
2. Update the status line paragraph in `claude/README.md`.
3. Open one PR and squash-merge it.
4. Pull master into `~/.dotfiles`. Every local session then shows the new
   layout on its next refresh. The uncommitted `hypr/hyprland.lua` there stays
   untouched.
5. On the laptop, run `git fetch && git merge --ff-only origin/master`.

## Out of scope

- Text in Claude Code's own footer row. The script cannot write there.
- A 🌿 marker for manual `git worktree` checkouts (`workspace.git_worktree`).
- A width check for line 2.
