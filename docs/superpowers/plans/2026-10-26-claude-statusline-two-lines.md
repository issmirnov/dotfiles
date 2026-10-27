# Two-line Claude Code status line Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split `claude/statusline-command.sh` into two rows: where the session is (host, launch directory, moves) and what it uses (model, effort, context, usage).

**Architecture:** The script still reads Claude Code's JSON payload on stdin and prints with `printf '%b'`. Line 2 reuses today's segments unchanged. Line 1 is rebuilt from new inputs (`$HOSTNAME`, `$SSH_CONNECTION`, `worktree.original_cwd`, `workspace.project_dir`, `$COLUMNS`) with three small bash helpers: `tildify`, `shorten_path`, `visible_len`.

**Tech Stack:** bash (3.2-compatible), jq, sed, git; Python 3 `unittest` for tests; GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-26-claude-statusline-two-lines-design.md`

## Global Constraints

- Work only in `/home/vania/.dotfiles-worktrees/statusline-host-dir` (branch `feat/statusline-host-dir`). Never edit `/home/vania/.dotfiles`: it is the live checkout and holds an unrelated uncommitted `hypr/hyprland.lua`.
- The agent shell is zsh with wrapped commands. Use `/usr/bin/cat` (not `cat`) and `command rm -f` (not `rm`). `>` does not overwrite (noclobber); use `>|`.
- Bash 3.2-compatible (the laptop's `/bin/bash`): no associative arrays, no `mapfile`, no `${var,,}`, no `|&`.
- No new dependencies. The script uses only bash, jq, git, sed, awk, basename, date.
- Colors: host `\033[2m` (local) or `\033[1;33m` (when `$SSH_CONNECTION` is not empty); launch directory and moved-to folder `\033[36m`; arrow `→` `\033[2m`; `🌿 <name>` `\033[33m`.
- Line 1 order: host, launch directory, `🌿 <name>`, `→ <folder>`, `git:(<branch>) ✗`, `[<session name>]`.
- Line 2 order: model and effort, context bar, cost, lines changed, cache %, duration, tokens/min with 5h/7d limits, output style.
- Shorten only when line 1 is wider than `COLUMNS - 4`. Shorten only the launch directory.
- The script ends with `printf '%b\n%b' "$LINE1" "$LINE2"`: two rows, no trailing newline, exit status 0.
- Commit messages: `feat(claude): …`, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `claude/statusline-command.sh` | Modify | Renders both rows. |
| `tests/test_statusline.py` | Create | Runs the script on JSON payloads with a pinned environment; checks the uncolored rows. |
| `.github/workflows/ci.yml` | Modify | New `test-statusline` job. |
| `claude/README.md` | Modify | Describes the two rows. |

---

### Task 1: Two rows, with the test harness and the CI job

**Files:**
- Create: `tests/test_statusline.py`
- Modify: `claude/statusline-command.sh:250-280` (from `# Context window progress bar` to the end)
- Modify: `.github/workflows/ci.yml` (new job after `test-zsh-paste`, line 59)

**Interfaces:**
- Produces: in the script, `LINE2` (string with literal `\033[…m` color codes). Line 1 stays `PROMPT_PART` until Task 2.
- Produces: in the tests, `ws(current, project=None)` and `render(payload, home="/home/u", columns=200, ssh=None, hostname="testhost") -> (raw_lines, plain_lines)`. Tasks 2 and 3 add test classes that use both.

- [ ] **Step 1: Write the failing test**

Create `tests/test_statusline.py`:

```python
"""Tests for claude/statusline-command.sh, the Claude Code status line.

Claude Code pipes a JSON payload into the script and shows each line it
prints as a row. Line 1 says where the session is (host, launch directory,
worktree, moves, git, session name). Line 2 says what it uses (model, effort,
context bar, cost, cache, duration).

Each test runs the script on a payload with a pinned environment and checks
the output with the colors stripped. Run from the repo root:

    python3 -m unittest tests.test_statusline
    BASH_BIN=/bin/bash python3 -m unittest tests.test_statusline   # another bash
"""
import json
import os
import pathlib
import re
import subprocess
import unittest
import uuid

REPO = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = REPO / "claude" / "statusline-command.sh"
BASH = os.environ.get("BASH_BIN", "bash")
ANSI = re.compile(r"\x1b\[[0-9;]*m")


def ws(current, project=None):
    """A workspace payload. project defaults to current: Claude hasn't moved."""
    return {"workspace": {"current_dir": current, "project_dir": project or current}}


def render(payload, home="/home/u", columns=200, ssh=None, hostname="testhost"):
    """Run the script on payload. Returns (raw_lines, plain_lines)."""
    sid = f"test-{uuid.uuid4().hex}"
    data = {"session_id": sid, "model": {"display_name": "Opus 5.5"}, **payload}
    env = {
        "PATH": os.environ["PATH"],
        "HOME": home,
        "HOSTNAME": hostname,
        "LC_ALL": "C.UTF-8",
        "CLAUDE_CODE_EFFORT_LEVEL": "max",
    }
    if columns is not None:
        env["COLUMNS"] = str(columns)
    if ssh is not None:
        env["SSH_CONNECTION"] = ssh
    try:
        out = subprocess.run(
            [BASH, str(SCRIPT)], input=json.dumps(data), env=env,
            capture_output=True, encoding="utf-8", check=True,
        ).stdout
    finally:
        # The script keeps per-session git and tokens/min state in /tmp.
        for f in pathlib.Path("/tmp").glob(f"claude-statusline-*-{sid}*"):
            f.unlink()
    raw = out.split("\n")
    return raw, [ANSI.sub("", line) for line in raw]


class TwoLines(unittest.TestCase):
    PAYLOAD = {
        **ws("/home/u/proj"),
        "session_name": "Fix it",
        "context_window": {
            "used_percentage": 14,
            "current_usage": {"cache_read_input_tokens": 99, "cache_creation_input_tokens": 1},
        },
        "cost": {"total_cost_usd": 2.17, "total_duration_ms": 16 * 60 * 1000},
    }

    def test_prints_exactly_two_lines(self):
        _, plain = render(self.PAYLOAD)
        self.assertEqual(len(plain), 2, plain)

    def test_line2_is_model_effort_bar_then_usage(self):
        _, plain = render(self.PAYLOAD)
        self.assertEqual(plain[1], "Opus 5.5 ⚡max | █░░░░░░░░░ 14% | ~$2.17 | cache 99% | ⏱ 16m")

    def test_line1_holds_no_line2_segments(self):
        _, plain = render(self.PAYLOAD)
        for segment in ("Opus", "⚡", "%", "$", "⏱"):
            self.assertNotIn(segment, plain[0])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /home/vania/.dotfiles-worktrees/statusline-host-dir && python3 -m unittest -v tests.test_statusline`
Expected: `FAILED (failures=2, errors=1)`. Today's script prints one line, `➜ proj [Fix it] | Opus 5.5 ⚡max | █░░░░░░░░░ 14% | ~$2.17 | cache 99% | ⏱ 16m`, so `plain[1]` raises `IndexError`.

- [ ] **Step 3: Write the minimal implementation**

In `claude/statusline-command.sh`, replace everything from `# Context window progress bar` (line 250) to the end of the file with:

```bash
# Line 2: model, effort and context bar, then usage
LINE2="${CYAN}${MODEL}${RESET}${EFFORT_DISPLAY}"
if [ -n "$PCT" ]; then
    PCT_INT=$(printf "%.0f" "$PCT")
    FILLED=$((PCT_INT / 10))
    EMPTY=$((10 - FILLED))
    printf -v FILL "%${FILLED}s"
    printf -v PAD "%${EMPTY}s"
    BAR="${FILL// /█}${PAD// /░}"

    if [ "$PCT_INT" -ge 90 ]; then
        BAR_COLOR="$RED"
    elif [ "$PCT_INT" -ge 70 ]; then
        BAR_COLOR="$YELLOW"
    else
        BAR_COLOR="$GREEN"
    fi

    LINE2="${LINE2} | ${BAR_COLOR}${BAR} ${PCT_INT}%${RESET}"
fi

# Append extra segments (only when non-empty)
[ -n "$COST_STR" ] && LINE2="${LINE2} | ${COST_STR}"
[ -n "$LINES_STR" ] && LINE2="${LINE2} | ${LINES_STR}"
[ -n "$CACHE_STR" ] && LINE2="${LINE2} | ${CACHE_STR}"
[ -n "$DURATION_STR" ] && LINE2="${LINE2} | ${CYAN}⏱ ${DURATION_STR}${RESET}"
[ -n "$RATE_PART" ] && LINE2="${LINE2} | ${RATE_PART}"
[ -n "$META_STR" ] && LINE2="${LINE2} | ${META_STR}"

printf '%b\n%b' "$PROMPT_PART" "$LINE2"
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd /home/vania/.dotfiles-worktrees/statusline-host-dir && python3 -m unittest -v tests.test_statusline`
Expected: `Ran 3 tests` … `OK`.

- [ ] **Step 5: Add the CI job**

In `.github/workflows/ci.yml`, insert after line 59 (`run: python3 -m unittest -v tests.test_zsh_paste`), keeping one blank line before the `# tmux-resurrect boot restore` comment:

```yaml

  # Status line rendering for claude/statusline-command.sh: both rows, the host,
  # the launch directory, moves, worktrees and narrow-window shortening. Runs the
  # script on JSON payloads; the runner image already has bash, jq and git.
  test-statusline:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run status line tests
        run: python3 -m unittest -v tests.test_statusline
```

Check the YAML parses: `python3 -c "import yaml,sys; print(list(yaml.safe_load(open(sys.argv[1]))['jobs']))" .github/workflows/ci.yml`
Expected: `['install-dotfiles', 'check-zsh', 'test-zsh-paste', 'test-statusline', 'test-tmux-resurrect']`

- [ ] **Step 6: Commit**

```bash
cd /home/vania/.dotfiles-worktrees/statusline-host-dir
git add tests/test_statusline.py claude/statusline-command.sh .github/workflows/ci.yml
git commit -F - <<'EOF'
feat(claude): split the status line into two rows

Line 2 now holds the model, effort, context bar and usage numbers, so
line 1 has room for the host and launch directory.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 2: Line 1 shows the host, the launch directory and moves

**Files:**
- Modify: `claude/statusline-command.sh` (color block, lines 4-13; directory block, lines 15-19; prompt, lines 31-32; git/worktree/session block, lines 67-78; last line)
- Test: `tests/test_statusline.py` (new `LineOne` class)

**Interfaces:**
- Consumes: `ws()`, `render()` from Task 1; `LINE2` from Task 1.
- Produces: in the script, `tildify <path>` (prints the path with a leading `$HOME` component as `~`), `HOST_PART`, `REST_PART` (everything on line 1 after the launch directory, starting with a space or empty), `LAUNCH_SHOWN`, `LINE1`. Task 3 uses all of these.

- [ ] **Step 1: Write the failing tests**

In `tests/test_statusline.py`, add `import tempfile` after `import subprocess`, then add this class before the `if __name__ == "__main__":` line:

```python
class LineOne(unittest.TestCase):
    WT = "/home/u/proj/.claude/worktrees/feat"
    WT_INFO = {"name": "feat", "path": WT, "original_cwd": "/home/u/proj"}

    def test_not_moved_shows_host_and_launch_dir(self):
        _, plain = render(ws("/home/u/proj"))
        self.assertEqual(plain[0], "testhost ~/proj")

    def test_moved_shows_arrow_and_current_folder(self):
        _, plain = render(ws("/home/u/proj", project="/home/u"))
        self.assertEqual(plain[0], "testhost ~ → proj")

    def test_worktree_root_shows_leaf_not_arrow(self):
        _, plain = render({**ws(self.WT), "worktree": self.WT_INFO})
        self.assertEqual(plain[0], "testhost ~/proj 🌿 feat")

    def test_worktree_subdir_shows_leaf_then_arrow(self):
        _, plain = render({**ws(self.WT + "/charts", project=self.WT), "worktree": self.WT_INFO})
        self.assertEqual(plain[0], "testhost ~/proj 🌿 feat → charts")

    def test_session_name_comes_last(self):
        _, plain = render({**ws("/home/u/proj", project="/home/u"), "session_name": "Fix it"})
        self.assertEqual(plain[0], "testhost ~ → proj [Fix it]")

    def test_git_segment_follows_the_move(self):
        with tempfile.TemporaryDirectory() as home:
            repo = pathlib.Path(home, "proj")
            subprocess.run(["git", "init", "-q", "-b", "main", str(repo)], check=True)
            subprocess.run(
                ["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@t",
                 "-c", "commit.gpgsign=false", "commit", "-q", "--no-verify",
                 "--allow-empty", "-m", "init"],
                check=True,
            )
            _, plain = render(ws(str(repo), project=home), home=home)
        self.assertEqual(plain[0], "testhost ~ → proj git:(main)")

    def test_no_project_dir_falls_back_to_current_dir(self):
        _, plain = render({"workspace": {"current_dir": "/home/u/proj"}})
        self.assertEqual(plain[0], "testhost ~/proj")

    def test_launch_dir_outside_home_stays_absolute(self):
        _, plain = render(ws("/srv/data"))
        self.assertEqual(plain[0], "testhost /srv/data")

    def test_home_prefix_must_be_a_whole_component(self):
        _, plain = render(ws("/home/u2/x"))
        self.assertEqual(plain[0], "testhost /home/u2/x")

    def test_host_is_cut_at_the_first_dot(self):
        _, plain = render(ws("/home/u/proj"), hostname="lorium.local")
        self.assertEqual(plain[0], "lorium ~/proj")

    def test_local_host_is_dim(self):
        raw, _ = render(ws("/home/u/proj"))
        self.assertTrue(raw[0].startswith("\x1b[2mtesthost\x1b[0m "), repr(raw[0]))

    def test_ssh_host_is_bold_yellow(self):
        raw, _ = render(ws("/home/u/proj"), ssh="10.0.0.2 50000 10.0.0.1 22")
        self.assertTrue(raw[0].startswith("\x1b[1;33mtesthost\x1b[0m "), repr(raw[0]))
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd /home/vania/.dotfiles-worktrees/statusline-host-dir && python3 -m unittest -v tests.test_statusline`
Expected: `FAILED (failures=12)`. Line 1 is still `➜ proj …`. The 3 `TwoLines` tests pass.

- [ ] **Step 3: Replace the color block (lines 4-13)**

`BOLD_GREEN` was only used for `➜`. Replace:

```bash
BOLD_GREEN='\033[1;32m'
CYAN='\033[36m'
BOLD_BLUE='\033[1;34m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
```

with:

```bash
CYAN='\033[36m'
BOLD_BLUE='\033[1;34m'
GREEN='\033[32m'
YELLOW='\033[33m'
BOLD_YELLOW='\033[1;33m'
RED='\033[31m'
```

- [ ] **Step 4: Replace the directory block (lines 15-19)**

Replace:

```bash
DIR=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
HOME_DIR="$HOME"
DIR="${DIR/#$HOME_DIR/~}"
BASENAME=$(basename "$DIR")
REAL_DIR="${DIR/#\~/$HOME_DIR}"
```

with:

```bash
# Where Claude is now, and where the session was launched. EnterWorktree
# re-points project_dir at the worktree; worktree.original_cwd keeps the launch dir.
REAL_DIR=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
LAUNCH_DIR=$(echo "$input" | jq -r '.worktree.original_cwd // .workspace.project_dir // empty')
[ -z "$LAUNCH_DIR" ] && LAUNCH_DIR="$REAL_DIR"
```

- [ ] **Step 5: Replace the prompt (lines 31-32) with the `tildify` helper**

Replace:

```bash
# Robbyrussell-style prompt
PROMPT_PART="${BOLD_GREEN}➜${RESET} ${CYAN}${BASENAME}${RESET}"
```

with:

```bash
# ~-abbreviate $HOME itself or a $HOME/ prefix only, so /home/vania2 stays put
tildify() {
    case "$1" in
        "$HOME") printf '%s' "~" ;;
        "$HOME"/*) printf '%s' "~${1#"$HOME"}" ;;
        *) printf '%s' "$1" ;;
    esac
}
```

- [ ] **Step 6: Replace the git/worktree/session block (lines 67-78)**

Replace:

```bash
PROMPT_PART="${PROMPT_PART}${GIT_PART}"

# Worktree indicator
WORKTREE=$(echo "$input" | jq -r '.worktree.name // ""')
if [ -n "$WORKTREE" ]; then
    PROMPT_PART="${PROMPT_PART} ${YELLOW}🌿 ${WORKTREE}${RESET}"
fi

# Session name
if [ -n "$SESSION_NAME" ]; then
    PROMPT_PART="${PROMPT_PART} ${MAGENTA}[${SESSION_NAME}]${RESET}"
fi
```

with:

```bash
# Line 1: host, launch dir, worktree, where Claude moved to, git, session name
HOST="${HOSTNAME%%.*}"
if [ -n "$SSH_CONNECTION" ]; then
    HOST_PART="${BOLD_YELLOW}${HOST}${RESET}"
else
    HOST_PART="${DIM}${HOST}${RESET}"
fi

WORKTREE=$(echo "$input" | jq -r '.worktree.name // ""')
WORKTREE_PATH=$(echo "$input" | jq -r '.worktree.path // ""')
REST_PART=""
if [ -n "$WORKTREE" ]; then
    REST_PART="${REST_PART} ${YELLOW}🌿 ${WORKTREE}${RESET}"
fi
# Moved away from the launch dir (the worktree root is already shown by 🌿)
if [ "$REAL_DIR" != "$LAUNCH_DIR" ] && [ "$REAL_DIR" != "$WORKTREE_PATH" ]; then
    REST_PART="${REST_PART} ${DIM}→${RESET} ${CYAN}$(basename "$REAL_DIR")${RESET}"
fi
REST_PART="${REST_PART}${GIT_PART}"
if [ -n "$SESSION_NAME" ]; then
    REST_PART="${REST_PART} ${MAGENTA}[${SESSION_NAME}]${RESET}"
fi

LAUNCH_SHOWN=$(tildify "$LAUNCH_DIR")
LINE1="${HOST_PART} ${CYAN}${LAUNCH_SHOWN}${RESET}${REST_PART}"
```

- [ ] **Step 7: Print line 1**

Replace the last line, `printf '%b\n%b' "$PROMPT_PART" "$LINE2"`, with:

```bash
printf '%b\n%b' "$LINE1" "$LINE2"
```

Check that nothing still uses the removed names:
Run: `cd /home/vania/.dotfiles-worktrees/statusline-host-dir && grep -n -E 'PROMPT_PART|BASENAME|HOME_DIR|BOLD_GREEN|RESULT' claude/statusline-command.sh`
Expected: no output.

- [ ] **Step 8: Run the tests to verify they pass**

Run: `cd /home/vania/.dotfiles-worktrees/statusline-host-dir && python3 -m unittest -v tests.test_statusline`
Expected: `Ran 15 tests` … `OK`.

- [ ] **Step 9: Commit**

```bash
cd /home/vania/.dotfiles-worktrees/statusline-host-dir
git add tests/test_statusline.py claude/statusline-command.sh
git commit -F - <<'EOF'
feat(claude): show host and launch directory on status line row 1

Row 1 now starts with the host (dim locally, bold yellow over SSH) and
the directory Claude was launched in, then `→ <folder>` once Claude
moves away from it. The launch directory prefers worktree.original_cwd,
because EnterWorktree re-points workspace.project_dir at the worktree.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 3: Shorten the launch path in narrow windows, and document both rows

**Files:**
- Modify: `claude/statusline-command.sh` (add two helpers after `tildify`; change the `LAUNCH_SHOWN`/`LINE1` lines from Task 2)
- Modify: `claude/README.md` (the `## statusline-command.sh` section)
- Test: `tests/test_statusline.py` (new `NarrowWindows` class)

**Interfaces:**
- Consumes: `tildify`, `HOST_PART`, `REST_PART`, `LAUNCH_SHOWN`, `LINE1` from Task 2; `render()`, `ws()` from Task 1.
- Produces: `shorten_path <path>` (fish-style: every component but the last cut to its first character, two for dot-names) and `visible_len <string>` (character count with literal `\033[…m` codes removed).

- [ ] **Step 1: Write the failing tests**

In `tests/test_statusline.py`, add this class before the `if __name__ == "__main__":` line:

```python
class NarrowWindows(unittest.TestCase):
    LONG = "/home/u/Projects/1.Personal/ai/shotcraft-videos"

    def test_wide_window_keeps_the_full_path(self):
        _, plain = render(ws(self.LONG), columns=200)
        self.assertEqual(plain[0], "testhost ~/Projects/1.Personal/ai/shotcraft-videos")

    def test_narrow_window_shortens_the_launch_path_fish_style(self):
        _, plain = render(ws(self.LONG), columns=40)
        self.assertEqual(plain[0], "testhost ~/P/1/a/shotcraft-videos")

    def test_dot_component_keeps_two_characters(self):
        _, plain = render(ws("/home/u/.dotfiles-worktrees/statusline"), columns=20)
        self.assertEqual(plain[0], "testhost ~/.d/statusline")

    def test_only_the_launch_path_is_shortened(self):
        moved = ws("/home/u/Projects/1.Personal/ops/argo-k8s", project="/home/u/Projects/1.Personal/ops")
        _, plain = render(moved, columns=30)
        self.assertEqual(plain[0], "testhost ~/P/1/ops → argo-k8s")

    def test_no_columns_means_no_shortening(self):
        _, plain = render(ws(self.LONG), columns=None)
        self.assertEqual(plain[0], "testhost ~/Projects/1.Personal/ai/shotcraft-videos")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd /home/vania/.dotfiles-worktrees/statusline-host-dir && python3 -m unittest -v tests.test_statusline`
Expected: `FAILED (failures=3)`: the narrow, dot-component and only-launch-path tests. The wide and no-`COLUMNS` tests pass already.

- [ ] **Step 3: Add the helpers**

In `claude/statusline-command.sh`, directly after the closing `}` of `tildify`, add:

```bash

# fish-style: every component but the last cut to 1 char (2 for dot-names)
shorten_path() {
    local IFS=/ out="" i c last
    local -a parts
    read -ra parts <<< "$1"
    last=$(( ${#parts[@]} - 1 ))
    for i in "${!parts[@]}"; do
        c=${parts[i]}
        if [ "$i" -lt "$last" ] && [ -n "$c" ] && [ "$c" != "~" ]; then
            if [[ $c == .* ]]; then c=${c:0:2}; else c=${c:0:1}; fi
        fi
        out="${out}${c}"
        [ "$i" -lt "$last" ] && out="${out}/"
    done
    printf '%s' "${out:-/}"
}

# Characters a string takes on screen, minus the literal \033[…m color codes
visible_len() {
    local s
    s=$(printf '%s' "$1" | sed 's/\\033\[[0-9;]*m//g')
    printf '%s' "${#s}"
}
```

- [ ] **Step 4: Shorten when line 1 won't fit**

Replace the two lines from Task 2:

```bash
LAUNCH_SHOWN=$(tildify "$LAUNCH_DIR")
LINE1="${HOST_PART} ${CYAN}${LAUNCH_SHOWN}${RESET}${REST_PART}"
```

with:

```bash
# Narrow window: if line 1 won't fit, shorten only the launch path, fish-style.
# The 4 columns of slack cover Claude Code's own spacing and the double-width 🌿.
LAUNCH_SHOWN=$(tildify "$LAUNCH_DIR")
if [[ $COLUMNS =~ ^[0-9]+$ ]]; then
    LINE1_WIDTH=$(( $(visible_len "${HOST_PART} ${REST_PART}") + ${#LAUNCH_SHOWN} ))
    if [ "$LINE1_WIDTH" -gt $((COLUMNS - 4)) ]; then
        LAUNCH_SHOWN=$(shorten_path "$LAUNCH_SHOWN")
    fi
fi
LINE1="${HOST_PART} ${CYAN}${LAUNCH_SHOWN}${RESET}${REST_PART}"
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd /home/vania/.dotfiles-worktrees/statusline-host-dir && python3 -m unittest -v tests.test_statusline`
Expected: `Ran 20 tests` … `OK`.

- [ ] **Step 6: Update the README**

In `claude/README.md`, replace the paragraph under `## \`statusline-command.sh\`` (it starts with `Custom statusline renderer invoked on each prompt.`) with:

```markdown
Custom status line renderer. Claude Code runs it on each update and shows each printed line as a row, above its own permission-mode row. It prints two lines:

1. **Where the session is:** the host (dim locally, bold yellow over SSH), the directory Claude was launched in, `🌿 <worktree>`, `→ <folder>` after Claude moves away from the launch directory, the git branch with a dirty mark, and the session name.
2. **What the session uses:** model, effort, context bar, cost, lines changed, cache hit rate, duration, and rate-limit headroom.

The launch directory comes from `worktree.original_cwd`, else `workspace.project_dir`, because EnterWorktree points `project_dir` at the worktree. If line 1 is wider than the window (`$COLUMNS`), the launch path shortens fish-style, for example `~/P/1/a/shotcraft-videos`.

Git results are cached for 10 seconds. Temp files are per session, so concurrent sessions don't overwrite each other's state. Tests: `python3 -m unittest -v tests.test_statusline`.
```

- [ ] **Step 7: Commit**

```bash
cd /home/vania/.dotfiles-worktrees/statusline-host-dir
git add tests/test_statusline.py claude/statusline-command.sh claude/README.md
git commit -F - <<'EOF'
feat(claude): shorten the launch path when status line row 1 won't fit

If row 1 is wider than COLUMNS - 4, the launch directory shortens
fish-style (~/P/1/a/shotcraft-videos). Nothing else on the row is cut.
The README now describes both rows.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 4: Verify end to end

**Files:** none changed.

- [ ] **Step 1: Run every Python test suite in `tests/`**

Run: `cd /home/vania/.dotfiles-worktrees/statusline-host-dir && python3 -m unittest -v tests.test_statusline tests.test_hexane_nightlight tests.test_zsh_paste 2>&1 | tail -3`
Expected: `OK`.

- [ ] **Step 2: Preview at a half-width window**

Run:

```bash
cd /home/vania/.dotfiles-worktrees/statusline-host-dir
printf '%s' '{"session_id":"preview-1","model":{"display_name":"Opus 5.5"},"workspace":{"current_dir":"/home/vania/.dotfiles-worktrees/statusline-host-dir","project_dir":"/home/vania"},"session_name":"Claude statusline host and directory","context_window":{"used_percentage":14,"current_usage":{"cache_read_input_tokens":99,"cache_creation_input_tokens":1}},"cost":{"total_cost_usd":2.17,"total_duration_ms":960000}}' \
  | COLUMNS=158 bash claude/statusline-command.sh; echo
command rm -f /tmp/claude-statusline-*-preview-1*
```

Expected: two colored rows. Row 1: `hexane ~ → statusline-host-dir git:(feat/statusline-host-dir) [Claude statusline host and directory]`. Row 2: `Opus 5.5 ⚡max | █░░░░░░░░░ 14% | ~$2.17 | cache 99% | ⏱ 16m`.

- [ ] **Step 3: Smoke-test under the laptop's bash 3.2**

Run:

```bash
cd /home/vania/.dotfiles-worktrees/statusline-host-dir
scp -q claude/statusline-command.sh laptop:/tmp/sl-smoke.sh
ssh laptop "printf '%s' '{\"session_id\":\"smoke-1\",\"model\":{\"display_name\":\"Opus 5.5\"},\"workspace\":{\"current_dir\":\"/Users/vania/.dotfiles\",\"project_dir\":\"/Users/vania\"},\"cost\":{\"total_cost_usd\":1}}' | COLUMNS=40 LC_ALL=en_US.UTF-8 /bin/bash /tmp/sl-smoke.sh | sed 's/\x1b\[[0-9;]*m//g'; echo; command rm -f /tmp/sl-smoke.sh /tmp/claude-statusline-*-smoke-1*"
```

Expected: `lorium ~ → .dotfiles git:(master)` (a `✗` follows if the laptop checkout is dirty) on row 1, and a row 2 that starts with `Opus 5.5`.

- [ ] **Step 4: Hand off**

Use superpowers:finishing-a-development-branch. The PR is one squash PR from `feat/statusline-host-dir` into `master`.

After the merge (spec § Rollout), with the user's go-ahead:

1. Bring `/home/vania/.dotfiles` up to `origin/master`. Its local `master` is often behind or diverged, and it holds an uncommitted `hypr/hyprland.lua` that must survive. Check `git -C /home/vania/.dotfiles rev-list --left-right --count master...origin/master` before choosing how to update.
2. On the laptop: `ssh laptop 'cd ~/.dotfiles && git fetch && git merge --ff-only origin/master'`. First check that the laptop has no local edits to any incoming file.
