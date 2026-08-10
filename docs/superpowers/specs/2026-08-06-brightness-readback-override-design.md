# Brightness read-back + manual-override coordination — design

**Date:** 2026-08-06
**Status:** DESIGN (approved in brainstorming; not yet implemented)
**Author:** Ivan + Claude

## Motivation

The Quickshell bar's `Brightness.qml` writes monitor backlight via `ddcutil` (VCP
`0x10`) but only *reads* it at startup and when the slider popup opens. Meanwhile
`hexane-nightlight` (a systemd **user** timer, every 2 min) ramps the same VCP
`0x10` down 100→80 % at sunset and back up at sunrise. Two consequences:

1. **Stale slider.** When nightlight ramps, the bar chip/slider don't update until
   the popup is reopened or `qs` restarts.
2. **The two fight.** A manual dim is silently reverted: early in the evening ramp
   nightlight's target is still high (~92–98 %), so on its next tick it *raises*
   the user back toward its schedule. Observed live 2026-08-06: user at 79 % at
   20:14 → nightlight pulled it to 92 % by 20:27.

They fight because the bar writes `ddcutil` directly while nightlight tracks its
own `~/.cache/hexane-nightlight/last` cache; neither sees the other's writes (this
also makes `last` drift from reality — 98 cached vs 79 actual).

## Goal

- The slider reflects external (nightlight) changes **event-driven, no polling**
  ("minimal resource usage").
- A **manual override wins**: touching the bar disables auto-dim so it stops
  fighting.
- Auto-dim **re-arms daily** (resumes at the next sunrise), plus a **visible bar
  toggle** to see/flip the state.

## The contract — two files in `~/.cache/hexane-nightlight/`

| File | Format | Writer | Reader | Meaning |
|---|---|---|---|---|
| `last` *(exists)* | `{ "<serial>": <pct>, … }` | nightlight | **bar (FileView watch)** | last brightness nightlight applied, per panel |
| `override` *(new)* | `{ "since": "<ISO8601>", "value": <pct> }` | bar (deleted by nightlight on expiry) | nightlight, bar | a valid marker present = "user is in control" |

Both files are written **atomically** (tmp + `rename`). Readers tolerate a
missing/short/corrupt file by treating it as **absent**.

## State machine

- **ARMED** — no `override`, or an expired one. nightlight applies its schedule
  each tick; the bar follows `last` live.
- **HELD** — a valid, unexpired `override`. nightlight leaves the panels alone;
  the bar shows the user's manual value and ignores `last`.

Transitions:
- Manual brightness change on the bar (drag / scroll) → write `override` → **HELD**.
- Toggle chip → *pause* = write `override` (**HELD**); *re-arm* = delete
  `override` (**ARMED**) + kick nightlight once for instant takeover.
- nightlight tick, override present but **expired** → delete `override` + apply
  schedule → **ARMED** (the daily re-arm).

**Expiry = first sunrise after `since`.** nightlight computes the most-recent
sunrise ≤ now (today's sunrise, or yesterday's if now is pre-dawn) from its
existing NOAA `sun_times`; the override is expired iff `since < most_recent_sunrise`.
So an evening dim holds all night and auto-dim resumes at dawn.

## nightlight changes (`bin/hexane-nightlight`)

- New helpers: `_read_override()`, `_clear_override()`, and a classifier that maps
  `(override, now)` → **held / expired / absent**. Expiry compares `since` to the
  most-recent sunrise ≤ `now`: today's sunrise if `now ≥` it, else **yesterday's**
  (`sun_times(now.date() - 1 day)`) so an evening override stays held through the
  pre-dawn hours and expires only after the *next* sunrise.
- The marker's `value` is **informational only** — nightlight ignores it and keys
  solely off `since`. (A toggle-pause with no known value writes `-1`.)
- In the timer path (`main` with no args), before applying `target(...)`:
  - **held** (present, not expired) → **skip apply**; if `last` cache is non-empty,
    blank it (write `{}`) so a later re-arm force-applies. Return.
  - **expired** → `_clear_override()`, then fall through to `apply(...)` (cache is
    `{}` from the held period → force-applies, correcting any drift).
  - **absent** → normal `apply(...)`.
- `_write_state` becomes **atomic** (tmp + `os.replace`).
- `--check` also prints override state (since / held vs expired) for debugging.
- No behavioral change when no override exists → the existing tests stay green.

## Bar changes (flat `~/.dotfiles/quickshell/`)

**New singleton `AutoDim.qml`** (`pragma Singleton`, like `Theme`) — the bar's
single source of truth for override state:
- `FileView` on `~/.cache/hexane-nightlight/override`, `watchChanges: true` →
  `property bool active` (a valid marker is present).
- `pause(v)` → atomically write `{ "since": "<ISO now>", "value": v }` via a small
  `Process` (`date -Iseconds` stamps the time). `arm()` → `rm -f` the marker, then
  run nightlight **once** by **absolute path** (`/home/vania/.dotfiles/bin/hexane-nightlight`
  — qs's minimal `PATH` excludes `~/…/dotbin`, per the quickshell-bar PATH gotcha)
  for instant takeover. `rm -f` per house rule.

**`Brightness.qml`:**
- Add a `FileView` on `~/.cache/hexane-nightlight/last`, `watchChanges: true`. On a
  *subsequent* change (ignore the initial load), if `!AutoDim.active && !dragging`,
  `_follow(DP7HGJ4 value)` — set `value` **and** `applied` (passive: no `ddcutil`
  write, no override). The startup `getvcp` remains the seed of truth.
- In `set(v)` (the only manual path — scroll + slider drag), after clamping, call
  `AutoDim.pause(value)`. Keep the existing write throttle and the popup-open
  reconcile read.
- When `AutoDim.active` transitions **false** (re-armed), run the reconcile
  `getvcp` once — races-free instant catch-up to whatever nightlight just applied,
  regardless of `last`/marker FileView ordering.

**New module `AutoDimToggle.qml`** (mirrors `IdleToggle.qml`): a chip reading
`AutoDim.active` → `auto` (armed, `Theme.subtext`) / `held` (overridden,
highlighted `Theme.briCol` + bold); click → `AutoDim.active ? AutoDim.arm() :
AutoDim.pause(-1)`.

**`Bar.qml`:** insert `AutoDimToggle {}` in the right `Row`, immediately after
`Brightness {}`.

## Why this is low-resource

No polling anywhere. The bar adds two inotify `FileView` watches (≈ free) and one
tiny marker write per manual change. nightlight adds one small file read per tick
and, **while HELD, stops its `ddcutil` writes entirely** — overriding makes it
*quieter*, not busier. Startup and popup-open `getvcp` reads are unchanged.

## Edge cases

- **Active drag** is never stomped: `_follow` is gated on `!dragging`.
- **Corrupt/short marker** → treated as absent → ARMED (auto-dim on — the
  non-sticky failure). Atomic writes make this rare.
- **Re-arm correctness:** because `last` cache is blanked while HELD, the first
  ARMED tick force-applies the schedule even if the target coincidentally equalled
  the stale cache.
- **Raw `ddcutil` in a terminal** is *not* treated as a manual override (bar-only
  detection); it's reconciled the next time the popup opens (existing `getvcp`).
- **Initial `last` load** must not stomp the startup truth (ignore the first
  FileView signal).

## Testing

- **nightlight (unit, `tests/test_hexane_nightlight.py`):** held override skips
  apply; expired override clears + applies; expiry boundary at sunrise (an evening
  `since` is honored pre-dawn, expires after the next sunrise); blanked cache forces
  re-apply on re-arm; atomic write round-trips; **no-override path unchanged**
  (existing tests green).
- **bar (manual, per the quickshell-bar dev loop):** relaunch `qs`, screenshot;
  drive with hypr-cua — drag the slider → `override` appears + `hexane-nightlight
  --check` shows held + `--dry-run` would skip; `--simulate` a ramp tick with the
  marker present → no write; click the toggle → marker cleared, `auto`↔`held`
  flips; `--simulate` past sunrise → expired → applies.

## Out of scope

Showing the exact re-arm time on the chip (would need nightlight to stamp
`rearm_at`); per-monitor independent overrides; treating raw-CLI `ddcutil` as an
override.
