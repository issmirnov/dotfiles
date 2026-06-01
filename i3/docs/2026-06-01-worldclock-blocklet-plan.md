# Worldclock Blocklet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an i3blocks segment showing live time in Zagreb, Prague, and Kyiv, collapsing cities that share a clock (`ZAG·PRG 21:03  KYV 22:03`).

**Architecture:** One self-contained bash script (`i3/blocklets/worldclock`) that computes each city's `HH:MM` via `TZ=… date`, groups cities with identical times, and prints the i3blocks full_text/short_text lines. A `WORLDCLOCK_NOW=<epoch>` seam pins "now" for deterministic, DST-spanning tests. Wired into `i3blocks.conf` before `[time]`.

**Tech Stack:** bash, coreutils `date` (tz database), the repo's existing dependency-free `tests/assert.sh` harness.

---

### Task 1: Failing test — summer instant

**Files:**
- Test: `i3/blocklets/tests/test_worldclock.sh` (create)

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
DIR=$(dirname "$0"); . "$DIR/assert.sh"; S="$DIR/../worldclock"

# Fixed UTC instants -> deterministic regardless of host TZ.
# Summer: 2026-07-01 12:00 UTC -> Zagreb/Prague +2 (14:00), Kyiv +3 (15:00)
summer=$(date -u -d '2026-07-01 12:00:00' +%s)
out=$(WORLDCLOCK_NOW=$summer bash "$S" __render)
assert_eq "summer full"  "ZAG·PRG 14:00  KYV 15:00" "$(sed -n 1p <<<"$out")"
assert_eq "summer short" "14:00 15:00"              "$(sed -n 2p <<<"$out")"
finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash i3/blocklets/tests/test_worldclock.sh`
Expected: FAIL — `worldclock` does not exist yet (`No such file or directory` / empty output mismatch).

---

### Task 2: Implement the script — make summer pass

**Files:**
- Create: `i3/blocklets/worldclock` (mode 0755)

- [ ] **Step 1: Write minimal implementation**

```bash
#!/usr/bin/env bash
# worldclock — i3blocks segment: live time in Zagreb, Prague, Kyiv.
# Zagreb & Prague share CET (always equal); Kyiv is EET (+1h). Cities whose
# current HH:MM match are collapsed under a joined label. Pure date/TZ — no
# network, no secrets, always exits 0. Test seam: WORLDCLOCK_NOW=<epoch> pins now.
set -u

# label|tz, ordered west-to-east by offset
CITIES=(
  "ZAG|Europe/Zagreb"
  "PRG|Europe/Prague"
  "KYV|Europe/Kiev"
)

time_in() {  # <tz> -> HH:MM at the current (or pinned) instant
  local tz=$1
  if [ -n "${WORLDCLOCK_NOW:-}" ]; then
    TZ="$tz" date -d "@$WORLDCLOCK_NOW" +%H:%M
  else
    TZ="$tz" date +%H:%M
  fi
}

render() {
  local entry lab tz i gi found
  local labels=() times=()
  for entry in "${CITIES[@]}"; do
    lab=${entry%%|*}; tz=${entry#*|}
    labels+=("$lab"); times+=("$(time_in "$tz")")
  done
  # group cities by equal time, preserving first-appearance order
  local group_times=() group_labels=()
  for i in "${!times[@]}"; do
    found=-1
    for gi in "${!group_times[@]}"; do
      [ "${group_times[$gi]}" = "${times[$i]}" ] && { found=$gi; break; }
    done
    if [ "$found" -ge 0 ]; then
      group_labels[$found]="${group_labels[$found]}·${labels[$i]}"
    else
      group_times+=("${times[$i]}"); group_labels+=("${labels[$i]}")
    fi
  done
  local full="" short=""
  for gi in "${!group_times[@]}"; do
    [ -n "$full" ]  && full+="  "
    [ -n "$short" ] && short+=" "
    full+="${group_labels[$gi]} ${group_times[$gi]}"
    short+="${group_times[$gi]}"
  done
  printf '%s\n' "$full"   # full_text
  printf '%s\n' "$short"  # short_text (no color line -> inherits bar default)
}

case "${1:-}" in
  __render) render ;;
  *)        render ;;
esac
exit 0
```

- [ ] **Step 2: Make executable**

Run: `chmod +x i3/blocklets/worldclock`

- [ ] **Step 3: Run test to verify summer passes**

Run: `bash i3/blocklets/tests/test_worldclock.sh`
Expected: PASS (summer full + short).

---

### Task 3: Add winter + collapse invariant — prove DST

**Files:**
- Modify: `i3/blocklets/tests/test_worldclock.sh`

- [ ] **Step 1: Add assertions before `finish`**

```bash
# Winter: 2026-01-15 12:00 UTC -> Zagreb/Prague +1 (13:00), Kyiv +2 (14:00).
# Same UTC instant, different display => DST-aware; ZAG·PRG stays collapsed, KYV +1h.
winter=$(date -u -d '2026-01-15 12:00:00' +%s)
wout=$(WORLDCLOCK_NOW=$winter bash "$S" __render)
assert_eq "winter full"  "ZAG·PRG 13:00  KYV 14:00" "$(sed -n 1p <<<"$wout")"
assert_eq "winter short" "13:00 14:00"              "$(sed -n 2p <<<"$wout")"

# Collapse invariant: exactly two time tokens (ZAG·PRG share one, KYV the other).
assert_contains "summer collapses ZAG·PRG" "ZAG·PRG" "$(sed -n 1p <<<"$out")"
ntok=$(sed -n 2p <<<"$out" | tr ' ' '\n' | grep -c ':')
assert_eq "summer has two time tokens" "2" "$ntok"
```

- [ ] **Step 2: Run the full suite**

Run: `bash i3/blocklets/tests/run.sh`
Expected: every suite green, including the 6 new `test_worldclock` assertions.

- [ ] **Step 3: Commit**

```bash
git add i3/blocklets/worldclock i3/blocklets/tests/test_worldclock.sh
git commit -m "feat(i3): worldclock blocklet (Zagreb/Prague/Kyiv)"
```

---

### Task 4: Wire into the bar + deploy locally

**Files:**
- Modify: `i3/i3blocks.conf` (insert as the first block, before `[bt_vol]`)

- [ ] **Step 1: Insert the block as the first block, before `[bt_vol]`**

```ini
[worldclock]
command=$SCRIPT_DIR/worldclock
interval=30

[bt_vol]
```

- [ ] **Step 2: Deploy in place**

Run: `i3-msg restart`
Expected: `[{"success":true}]`; the bar reloads, new segment appears at the far left (before the 🎧 block).

- [ ] **Step 3: Eyeball the live segment**

Run: `BLOCK_INSTANCE= i3/blocklets/worldclock` and compare to the bar.
Expected: `ZAG·PRG HH:MM  KYV HH:MM` matching the real current time in those cities.

- [ ] **Step 4: Commit**

```bash
git add i3/i3blocks.conf
git commit -m "feat(i3): wire worldclock as the first (leftmost) block"
```

---

### Task 5: Document in the blocklets README

**Files:**
- Modify: `i3/blocklets/README.md` (add a `worldclock` section after `network`)

- [ ] **Step 1: Add the section**

```markdown
## `worldclock` — Zagreb / Prague / Kyiv

Single block (`[worldclock]`, `interval=30`). Prints the live time in three cities,
collapsing those that share a clock:

```
ZAG·PRG 21:03  KYV 22:03
```

Zagreb and Prague are both Central European Time (always equal); Kyiv is one hour ahead
(Eastern European Time). Grouping is computed from the actual rendered times, so it's
DST-aware and self-correcting. Pure `date`/`TZ` — no network, no secrets. The
`WORLDCLOCK_NOW=<epoch>` seam pins "now" for the deterministic summer/winter tests.
```

- [ ] **Step 2: Commit**

```bash
git add i3/blocklets/README.md
git commit -m "docs(i3): document worldclock blocklet in README"
```

---

## Self-Review

- **Spec coverage:** collapse-by-equal-time render (T2), full+short output (T2), `WORLDCLOCK_NOW`/`__render` seam (T2), summer+winter+invariant tests (T1/T3), config as first block before `[bt_vol]` interval=30 (T4), README (T5), design doc already committed. ✓
- **Placeholders:** none — every code/command step is concrete.
- **Type consistency:** test references `$S/../worldclock` and `__render`; script defines `__render` + default both calling `render`; label spelling `ZAG/PRG/KYV` and `·` separator consistent across script, tests, README, design doc. ✓
- **DST correctness:** summer (UTC+2/+3 → 14:00/15:00) and winter (UTC+1/+2 → 13:00/14:00) verified against the tz rules; fixed UTC epochs make assertions host-TZ-independent.
