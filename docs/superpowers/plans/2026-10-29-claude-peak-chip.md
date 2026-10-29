# Claude Peak-Hours Chip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show Claude's weekday peak hours as a chip at the left of the Claude usage chips on the hexane Quickshell bar.

**Architecture:** A bash blocklet, `i3/blocklets/claude_peak`, does the Pacific-time math with `TZ=America/Los_Angeles date` and prints the i3blocks 3-line protocol. The existing `Blocklet.qml` shows it in `Bar.qml`. No new QML component.

**Tech Stack:** bash + GNU `date` + tzdata, Quickshell 0.3.0 (QML), the dependency-free `i3/blocklets/tests` harness.

**Spec:** `docs/superpowers/specs/2026-10-29-claude-peak-chip-design.md`

## Global Constraints

- Peak window: Monday to Friday, 05:00 (inclusive) to 11:00 (exclusive), `America/Los_Angeles`.
- Heads-up: at most 3600 s before the start, same Pacific day.
- Peak output: `⚡ peak <left>` / `peak <left>` / `#f0c489`.
- Heads-up output: `peak in <left>` / `peak in <left>` / no color line.
- Off-peak output: an empty full_text and short_text.
- Countdown format, copied from `quickshell/lib/cal-next`: `%dh%dm` at 3600 s or more, `<1m` under 60 s, else `%dm`.
- Test seam: `CLAUDE_PEAK_NOW=<epoch seconds>`.
- The script uses no network and no secrets, and always exits 0.
- `Bar.qml` refers to the script as `Quickshell.shellDir + "/../i3/blocklets/claude_peak"`, interval 30000.
- `i3/i3blocks.conf` does not change.
- Worktree: `WT=/home/vania/.dotfiles-worktrees/claude-peak-chip`, branch `feat/claude-peak-chip`, based on `origin/master`.
- Stage only the files named in each task. Never `git add -A`.

---

### Task 1: The `claude_peak` blocklet

**Files:**
- Create: `i3/blocklets/claude_peak` (mode 755)
- Create: `i3/blocklets/tests/test_claude_peak.sh` (mode 644, like the other tests)
- Modify: `i3/blocklets/README.md` (intro line, new section, Tests section)

**Interfaces:**
- Produces: `i3/blocklets/claude_peak`. It takes no arguments. It reads `CLAUDE_PEAK_NOW` if set. It prints line 1 full_text, line 2 short_text, and on peak only, line 3 the color.

- [ ] **Step 1: Write the failing test**

`i3/blocklets/tests/test_claude_peak.sh`:

```bash
#!/usr/bin/env bash
DIR=$(dirname "$0"); . "$DIR/assert.sh"; S="$DIR/../claude_peak"

# Run the blocklet at a fixed UTC instant -> deterministic regardless of host TZ.
peak_at() { CLAUDE_PEAK_NOW=$(date -u -d "$1" +%s) bash "$S"; }
nth() { sed -n "${1}p" <<<"$2"; }   # line N of an output: 1 full, 2 short, 3 color

# PDT (UTC-7): peak is 12:00-18:00 UTC on Thu 2026-10-29.
out=$(peak_at '2026-10-29 17:11:00')                                  # 10:11 PDT
assert_eq "pdt peak full"  "⚡ peak 49m" "$(nth 1 "$out")"
assert_eq "pdt peak short" "peak 49m"    "$(nth 2 "$out")"
assert_eq "pdt peak color" "#f0c489"     "$(nth 3 "$out")"
assert_eq "pdt start is inclusive" "⚡ peak 6h0m" "$(nth 1 "$(peak_at '2026-10-29 12:00:00')")"
assert_eq "pdt last seconds"       "⚡ peak <1m"  "$(nth 1 "$(peak_at '2026-10-29 17:59:30')")"
assert_eq "pdt end is exclusive"   ""             "$(nth 1 "$(peak_at '2026-10-29 18:00:00')")"
# 11:11 PDT: ccflare's fixed 13:00-19:00 UTC flag still says peak here.
assert_eq "pdt 11:11 is off-peak"  ""             "$(nth 1 "$(peak_at '2026-10-29 18:11:00')")"

out=$(peak_at '2026-10-29 11:15:00')                                  # 04:15 PDT
assert_eq "pdt heads-up full"     "peak in 45m" "$(nth 1 "$out")"
assert_eq "pdt heads-up short"    "peak in 45m" "$(nth 2 "$out")"
assert_eq "pdt heads-up no color" ""            "$(nth 3 "$out")"
assert_eq "pdt heads-up opens at 1h" "peak in 1h0m" "$(nth 1 "$(peak_at '2026-10-29 11:00:00')")"
assert_eq "pdt before the heads-up"  ""             "$(nth 1 "$(peak_at '2026-10-29 10:59:00')")"

# PST (UTC-8): peak is 13:00-19:00 UTC on Thu 2026-01-15.
assert_eq "pst start"    "⚡ peak 6h0m" "$(nth 1 "$(peak_at '2026-01-15 13:00:00')")"
assert_eq "pst heads-up" "peak in 30m"  "$(nth 1 "$(peak_at '2026-01-15 12:30:00')")"
assert_eq "pst end"      ""             "$(nth 1 "$(peak_at '2026-01-15 19:00:00')")"

# Weekends: never. DST ends 2026-11-01 at 09:00 UTC.
assert_eq "saturday" "" "$(nth 1 "$(peak_at '2026-10-31 16:00:00')")"   # 09:00 PDT
assert_eq "sunday"   "" "$(nth 1 "$(peak_at '2026-11-01 16:00:00')")"   # 08:00 PST

# The first weekday after the DST change.
assert_eq "monday heads-up" "peak in 45m" "$(nth 1 "$(peak_at '2026-11-02 12:15:00')")"   # 04:15 PST
assert_eq "monday peak"     "⚡ peak 6h0m" "$(nth 1 "$(peak_at '2026-11-02 13:00:00')")"  # 05:00 PST

# The host TZ must not leak in. 17:11 UTC is already Friday 02:11 in Tokyo.
t=$(date -u -d '2026-10-29 17:11:00' +%s)
assert_eq "host TZ does not leak" "$(CLAUDE_PEAK_NOW=$t bash "$S")" "$(TZ=Asia/Tokyo CLAUDE_PEAK_NOW=$t bash "$S")"

# Without the seam it reads the clock and still exits 0.
bash "$S" >/dev/null; assert_eq "live run exits 0" "0" "$?"
finish
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash $WT/i3/blocklets/tests/test_claude_peak.sh`
Expected: many `FAIL` lines (`bash: .../claude_peak: No such file or directory`) and a non-zero exit.

- [ ] **Step 3: Write the blocklet**

`i3/blocklets/claude_peak`, then `chmod 755`:

```bash
#!/usr/bin/env bash
# claude_peak — i3blocks segment: Claude peak hours, Mon–Fri 05:00–11:00
# America/Los_Angeles (the window claude-peak-time.pages.dev shows).
#   peak                 -> "⚡ peak 49m"   amber, counts down to the end
#   up to 1h before peak -> "peak in 45m"  no color line (the bar's dim default)
#   any other time       -> empty (hides the block)
# Pure date/TZ — no network, no secrets, always exits 0. Test seam:
# CLAUDE_PEAK_NOW=<epoch> pins now.
set -u

PEAK_TZ=America/Los_Angeles
PEAK_START=05:00       # Pacific, inclusive
PEAK_END=11:00         # Pacific, exclusive
WARN_S=3600            # heads-up this long before the start
PEAK_COLOR='#f0c489'   # pastel amber (Theme.usageWarn)

fmt() {   # seconds -> 1h49m / 49m / <1m (same as quickshell/lib/cal-next)
  local s=$1
  if   [ "$s" -ge 3600 ]; then printf '%dh%dm' $(( s / 3600 )) $(( (s % 3600) / 60 ))
  elif [ "$s" -lt 60 ];   then printf '<1m'
  else printf '%dm' $(( s / 60 )); fi
}

now=${CLAUDE_PEAK_NOW:-$(date +%s)}
read -r dow day < <(TZ=$PEAK_TZ date -d "@$now" '+%u %F')   # 1=Mon..7=Sun, Pacific date
pt() { TZ=$PEAK_TZ date -d "$day $1" +%s; }                 # <HH:MM> Pacific that day -> epoch

if [ "$dow" -le 5 ]; then
  start=$(pt "$PEAK_START"); end=$(pt "$PEAK_END")
  if [ "$now" -ge "$start" ] && [ "$now" -lt "$end" ]; then
    left=$(fmt $(( end - now )))
    printf '⚡ peak %s\npeak %s\n%s\n' "$left" "$left" "$PEAK_COLOR"
    exit 0
  fi
  if [ "$now" -lt "$start" ] && [ $(( start - now )) -le "$WARN_S" ]; then
    left=$(fmt $(( start - now )))
    printf 'peak in %s\npeak in %s\n' "$left" "$left"
    exit 0
  fi
fi
printf '\n\n'   # off-peak: empty full_text hides the block
exit 0
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash $WT/i3/blocklets/tests/test_claude_peak.sh`
Expected: `21 passed, 0 failed`, exit 0.

Then the whole suite: `bash $WT/i3/blocklets/tests/run.sh`
Expected: every file ends `N passed, 0 failed`, exit 0.

- [ ] **Step 5: Document it in `i3/blocklets/README.md`**

1. In the intro, replace
   `The three\ndocumented below — `ai_usage`, `network`, and `worldclock` — are custom.`
   with
   `The four\ndocumented below — `ai_usage`, `network`, `worldclock`, and `claude_peak` — are custom.`
2. Insert this section between the `worldclock` section and `## Tests`:

```markdown
## `claude_peak` — Claude peak hours

Claude's weekday peak hours: Monday to Friday, 05:00–11:00 `America/Los_Angeles`, the
window that [claude-peak-time.pages.dev](https://claude-peak-time.pages.dev/) shows. The
Quickshell bar shows it as a chip left of the Claude usage chips. `i3blocks.conf` has no
block for it.

| When (Pacific, Mon–Fri) | Renders | Color |
|-------------------------|---------|-------|
| 05:00–11:00 | `⚡ peak 49m` (time left) | amber `#f0c489` |
| 04:00–05:00 | `peak in 45m` | none (bar default) |
| any other time | nothing (block hidden) | |

The start is inclusive and the end is exclusive. The script follows Pacific time, not
ccflare's `peakHours.active`: ccflare hard-codes 13:00–19:00 UTC, one hour late during PDT.
Since 2026-05-06 the peak-hour cut no longer applies to Claude Code on Pro and Max
([Anthropic](https://www.anthropic.com/news/higher-limits-spacex)).

Pure `date`/`TZ`: no network, no secrets, always exits 0. The `CLAUDE_PEAK_NOW=<epoch>` seam
pins "now" so the tests cover both window edges in PDT and PST.
```

3. In `## Tests`, replace `All three custom scripts` with `All four custom scripts`, replace `` `WORLDCLOCK_NOW`) `` with `` `WORLDCLOCK_NOW`, `CLAUDE_PEAK_NOW`) ``, and replace `world-clock\nDST collapse —` with `world-clock\nDST collapse, peak-hour edges —`.

- [ ] **Step 6: Commit**

```bash
git -C $WT add i3/blocklets/claude_peak i3/blocklets/tests/test_claude_peak.sh i3/blocklets/README.md
git -C $WT commit -m "i3blocks: claude_peak blocklet for Claude peak hours"
```

(End the message with the `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` trailer.)

---

### Task 2: The chip on the bar

**Files:**
- Modify: `quickshell/Bar.qml` (top deck right `Row`, before `ClaudePool {}`)
- Modify: `quickshell/README.md` (file map rows for `Bar.qml` and `Blocklet.qml`)

**Interfaces:**
- Consumes: `i3/blocklets/claude_peak` from Task 1, and `Blocklet { exec; interval }` from `quickshell/Blocklet.qml`. Blocklet hides itself when line 1 is empty, and uses `Theme.subtext` when there is no color line.

- [ ] **Step 1: Add the Blocklet to `Bar.qml`**

Change the cluster comment
`// right — AI usage (Claude/Codex), brightness, audio, stats, idle-inhibitor`
to
`// right — Claude peak hours, AI usage (Claude/Codex), brightness, audio, stats, idle-inhibitor`.

Insert before the `// One chip per ccflare Anthropic account…` comment that sits above `ClaudePool {}`:

```qml
                // Claude peak hours (Mon–Fri 05:00–11:00 Pacific): amber "⚡ peak 49m" until the
                // end, a dim "peak in 45m" the hour before, hidden otherwise. The path is relative
                // to shellDir (like ClaudePool), so a worktree build runs its own script.
                Blocklet {
                    exec: Quickshell.shellDir + "/../i3/blocklets/claude_peak"
                    interval: 30000
                }
```

- [ ] **Step 2: Update `quickshell/README.md`**

- `Bar.qml` row: replace `right = AI-usage +` with `right = Claude peak hours + AI-usage +`.
- `Blocklet.qml` row: replace `verbatim (worldclock).` with `verbatim (worldclock, claude_peak).`

- [ ] **Step 3: Load the worktree bar with "now" pinned to a peak instant**

```bash
WT=/home/vania/.dotfiles-worktrees/claude-peak-chip
peak=$(date -u -d '2026-10-29 17:11:00' +%s)    # Thu 10:11 PDT
pkill -x qs
hyprctl dispatch "hl.dsp.exec_cmd(\"CLAUDE_PEAK_NOW=$peak qs -p $WT/quickshell >/tmp/qs-peak.log 2>&1\")"
```

Wait for `Configuration Loaded` in `/tmp/qs-peak.log` (use Monitor, not `sleep`). Then:
`grep -iE 'error|warning|invalid|not a type' /tmp/qs-peak.log`
Expected: no QML errors. An `sni.watcher` warning is benign.

- [ ] **Step 4: Screenshot the peak look**

```bash
grim -o DP-1 -t png /tmp/peak-b.png && magick /tmp/peak-b.png -crop 2000x96+1840+0 +repage /tmp/peak-c.png
```

View `/tmp/peak-c.png`. Expected: `⚡ peak 49m` in amber on a dark chip, directly left of the first `CC` chip, with the normal 9 px gap. The clock must not overlap the cluster. If the screen is locked (`pgrep -x hyprlock`), use the offscreen `_qa.qml` route from the KB instead.

- [ ] **Step 5: Screenshot the heads-up look**

Repeat Steps 3–4 with `peak=$(date -u -d '2026-10-29 11:15:00' +%s)` (04:15 PDT).
Expected: `peak in 45m` in the dim lavender default text.

- [ ] **Step 6: Restore the live bar**

```bash
pkill -x qs
hyprctl dispatch 'hl.dsp.exec_cmd("qs >/tmp/qs.log 2>&1")'
```

Expected: the live bar is back. It still runs master, so it has no peak chip yet.

- [ ] **Step 7: Commit**

```bash
git -C $WT add quickshell/Bar.qml quickshell/README.md
git -C $WT commit -m "quickshell: Claude peak-hours chip left of the Claude chips"
```

(End the message with the `Co-Authored-By` trailer.)

---

### Task 3: Ship

**Files:**
- Modify: `~/docs/docs/systems/hexane/hyprland-bars.md` (a separate repo: stage only this file)

- [ ] **Step 1: Push and open the PR**

```bash
git -C $WT push -u origin feat/claude-peak-chip
gh pr create --repo issmirnov/dotfiles --base master --head feat/claude-peak-chip \
  --title "quickshell: Claude peak-hours chip" --body-file /tmp/claude-peak-pr.md
```

The body covers What / How / Testing in the style of #73. It is de-slopped and ends with the `🤖 Generated with [Claude Code](https://claude.com/claude-code)` line.

- [ ] **Step 2: Wait for the bots and CI**

Use the watching-pr-bot-reviews skill: run `prbots wait <PR>` in the background, then `prbots <PR>`. If the verdict is FIX, fix real findings on the branch and push, then wait again. If `install-dotfiles` fails at "Install bat" with `jq: error … Cannot iterate over null`, run `gh run rerun <id> --failed`.

- [ ] **Step 3: Merge**

```bash
gh pr merge <PR> --repo issmirnov/dotfiles --squash
git -C $WT push origin --delete feat/claude-peak-chip
```

- [ ] **Step 4: Make it live in the main checkout**

```bash
git -C ~/.dotfiles fetch -q origin
git -C ~/.dotfiles diff --name-only master origin/master   # incoming files
git -C ~/.dotfiles status --short                          # local edits
```

Continue only if no incoming file has local edits. Then:

```bash
git -C ~/.dotfiles merge --ff-only origin/master
pkill -x qs
hyprctl dispatch 'hl.dsp.exec_cmd("qs >/tmp/qs.log 2>&1")'
```

Check `/tmp/qs.log` for `Configuration Loaded` and no QML errors. Off-peak the chip is hidden. Confirm it runs with `~/.dotfiles/i3/blocklets/claude_peak; echo rc=$?`.

- [ ] **Step 5: Add the KB note**

In `~/docs/docs/systems/hexane/hyprland-bars.md`, add one bullet after the `ccflare-aware Claude chips` bullet. It covers: the window, the three states, the script and test paths, the ccflare 13:00–19:00 UTC caveat, the May 2026 Pro/Max change, and the `CLAUDE_PEAK_NOW` + `qs -p` QA trick. Commit only that file:

```bash
git -C ~/docs add docs/systems/hexane/hyprland-bars.md
git -C ~/docs commit -m "docs(hexane): Claude peak-hours chip on the Quickshell bar"
```

- [ ] **Step 6: Clean up**

```bash
git -C ~/.dotfiles worktree remove $WT
git -C ~/.dotfiles branch -D feat/claude-peak-chip
```
