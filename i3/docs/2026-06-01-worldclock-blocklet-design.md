# i3blocks: world-clock blocklet — design

**Date:** 2026-06-01
**Host:** hexane
**Repo:** `issmirnov/dotfiles` (public) — script lives in `i3/blocklets/`, wired via `i3/i3blocks.conf`

## Goal

Add a world-clock segment to the hexane i3blocks bar showing the live time in **Zagreb,
Prague, and Kyiv**. hexane runs on `America/Denver`, so the existing `[time]` block already
covers local time; this block adds the three European cities (≈8–9h ahead).

Among the three there are only **two distinct offsets**: Zagreb and Prague are both Central
European Time (UTC+1 winter / +2 summer) and always show the *same* clock; Kyiv is Eastern
European Time (UTC+2 / +3), exactly one hour ahead. Both zones switch DST on the same dates,
so the 1-hour gap holds year-round and Zagreb always equals Prague.

## Rendering decision

Render **`ZAG·PRG 21:03  KYV 22:03`** — cities that currently show the same time are
collapsed under a joined label, groups separated by two spaces. 24-hour, DST-aware.

Chosen (over listing all three explicitly, flags, or bare TZ names) because the user
explicitly flagged the shared-timezone redundancy: collapsing avoids printing the identical
Zagreb/Prague number twice while still naming every city. The collapse is computed from the
*actual* rendered times rather than hardcoded, so it always reflects reality — DST-correct,
and it would split automatically in the (practically impossible) event the offsets diverged.

Plain text, **no icon** (matches the chosen style; zero font-rendering risk). No color line,
so the segment inherits the bar default like the neighbouring `[time]` block.

## Component — `blocklets/worldclock`

Single script, same conventions as `ai_usage` / `network`:

- **Cities** — an ordered `label|tz` list, west-to-east by offset:
  `ZAG|Europe/Zagreb`, `PRG|Europe/Prague`, `KYV|Europe/Kiev`.
- **Render logic** — for each city compute `HH:MM` via `TZ=$tz date +%H:%M`; group the
  cities that share an identical `HH:MM` (preserving first-appearance order); join each
  group's labels with `·`; join groups with two spaces. Today → `ZAG·PRG 21:03  KYV 22:03`.
- **Output (i3blocks 3-line protocol):**
  - `full_text`: `ZAG·PRG 21:03  KYV 22:03`
  - `short_text`: the distinct times only, space-joined — `21:03 22:03` (drops labels when
    the bar is cramped)
  - *(no color line — inherit default)*
- **Test seam** — `WORLDCLOCK_NOW=<epoch seconds>`, when set, pins "now" so every `date`
  call renders that fixed instant (`TZ=$tz date -d "@$WORLDCLOCK_NOW" +%H:%M`). Lets tests
  assert exact strings deterministically across DST boundaries. Unset → real current time.
- **Dispatch verb** — `__render` prints the three protocol lines to stdout (the hook the
  tests drive), mirroring `ai_usage`'s hidden verbs.
- **Robustness** — pure `date`; no network, no files, no secrets. Always `exit 0` so it can
  never break the bar. (No failure modes beyond a missing `date`/tz database, which would be
  a broken system; in that case it still exits 0 with whatever `date` emits.)

### Config (`i3/i3blocks.conf`)

```ini
[worldclock]
command=$SCRIPT_DIR/worldclock
interval=30
```

Inserted as the **first (leftmost) block, before `[bt_vol]`**, so the bar's left end reads
`worldclock, bt_vol, …`. `interval=30`: the display is minute-granular and `date` is
effectively free, so 30 s keeps worst-case skew under half a minute at negligible cost
(trivially tunable; could match `[time]`'s `5` for lockstep ticks).
`~/.i3blocks.conf` is a symlink to this file, so editing the repo file is the deployed change.

## Tests — `blocklets/tests/test_worldclock.sh`

Auto-discovered by `tests/run.sh` (globs `test_*.sh`). Drives `__render` with
`WORLDCLOCK_NOW` pinned to fixed UTC instants, asserting exact output:

- **Summer instant** (e.g. `2026-07-01 12:00 UTC`): Zagreb/Prague +2, Kyiv +3 →
  `full_text` = `ZAG·PRG 14:00  KYV 15:00`; `short_text` = `14:00 15:00`.
- **Winter instant** (e.g. `2026-01-15 12:00 UTC`): Zagreb/Prague +1, Kyiv +2 →
  `full_text` = `ZAG·PRG 13:00  KYV 14:00`. Same UTC time, different display ⇒ proves the
  block is DST-aware, ZAG·PRG stays collapsed, and Kyiv stays exactly +1h in both seasons.
- **Collapse invariant**: in both fixtures Zagreb and Prague share one `ZAG·PRG` group and
  the output contains exactly two time tokens.

Fixed-instant epochs are derived in-test with `date -u -d '<iso>' +%s` (no hardcoded magic
numbers), so the suite stays dependency-free and offline like the rest of the harness.

## Key-leakage safeguards

None needed — the script reads no credentials and emits only city labels and clock times.
Recorded here only to stay consistent with the other blocklet docs: this block touches no
files under `$HOME` and writes nothing to the repo.

## Verification plan

- `i3/blocklets/worldclock __render` → three lines, `ZAG·PRG HH:MM  KYV HH:MM` matching the
  current real time in those cities.
- `WORLDCLOCK_NOW=$(date -u -d '2026-07-01 12:00 UTC' +%s) i3/blocklets/worldclock __render`
  → `ZAG·PRG 14:00  KYV 15:00`.
- `bash i3/blocklets/tests/run.sh` → all suites green (existing + new).
- `i3-msg restart` → eyeball the new segment at the far left of the bar (before the 🎧 block).

## Out of scope (YAGNI)

- Click actions, seconds, date-per-city, configurable city list (hardcoded three is the ask).
- An icon/label (explicitly chosen plain).
- Signalling i3blocks on the exact minute boundary (interval polling is sufficient).
