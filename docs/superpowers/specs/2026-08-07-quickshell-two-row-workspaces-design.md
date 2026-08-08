# Quickshell bar — two-row (two-deck) workspaces — design

**Date:** 2026-08-07
**Status:** SHIPPED 2026-08-07 — default bar. `barHeight` 80 (two decks); knobs `Theme.deckHeight` (inter-row gap) + `Workspaces.wsBudget` (wrap point). Durable facts → KB `systems/hexane/hyprland-bars.md`.
**Author:** Ivan + Claude

## Motivation

The workspace pills are a single `Row` in the top-left, vertically centered in a
46 px bar. With long named-workspace labels (`pinley-office`, `pinley`, `cara`,
`skills`, …) the left cluster grows until it slides *under* the centered clock — it
neither wraps nor truncates. Goal: **keep the full names** (no truncation) and gain
headroom by wrapping onto a **second deck**.

## Decisions (locked in brainstorming)

- **Layout — Option C "Time tier":** the bar becomes **two decks** (~90 px tall).
  Workspaces own the left of *both* decks. The top deck stays the live/interactive
  strip; the bottom deck carries the glanceable secondary content.
  - **Top deck:** `[workspaces →]` · `[Clock: date · time · ZAG · KYV]` ·
    `[AI-usage · Brightness · AutoDim · Audio · Stats · IdleToggle]`
  - **Bottom deck:** `[← overflow workspaces]` ·
    `[world-clock · calendar (current + next)]` · `[SysTray]`
- **Height — always-tall:** fixed ~90 px at all times (not dynamic).
  `exclusiveZone` reserves the taller strip once, so there is **no window reflow**
  when workspaces come and go. Because the calendar + tray live on the bottom deck,
  row 2 is never empty even with 2–3 workspaces open.
- **Fill order — top-row-first, then spill:** pills flow left→right and wrap down
  (plain `Flow` / flex-wrap). Pill positions stay stable as spaces open/close.
- **Kept as-is:** full workspace names, the named-workspace sort, click-to-
  `activate()`, the per-app `overrideIcon` map, the `◆ scratch` special badge.
- **Per-monitor** rendering unchanged — each bar shows only its own monitor's
  workspaces (DP-1 + DP-2; the Xeneon Edge HDMI-A-2 stays excluded).

## Rejected alternatives

- **A — centered clusters** (clock/stats float at mid-height): simplest change, but
  only workspaces use row 2 and the right side reads empty.
- **B — top row stays today's bar, overflow-only second row:** most familiar, but
  row 2's right two-thirds is dead space.
- **Icon-only / collapse inactive pills:** fits more on one row, but drops the long
  names the whole change exists to preserve.
- **Grow-when-needed height:** reclaims space when idle, but reflows every tiled
  window on each wrap-threshold crossing.

## Architecture — three files change

Flat layout under `~/.dotfiles/quickshell/` (dir-symlinked to `~/.config/quickshell/`).
Quickshell auto-imports uppercase neighbours — no `qmldir`, no sibling imports.

### 1. `Theme.qml` — metrics
- `barHeight: 46 → 90` (two `chipHeight` 32 rows + inter-deck gap + padding; final
  value tuned visually against a screenshot).
- Add a `deckGap` metric (inter-row gap, ~6–8 px). `exclusiveZone` in `Bar.qml` is
  `barHeight + marginTop`, so windows re-reserve the taller strip automatically.

### 2. `Bar.qml` — two-deck restructure
Today the inner `Rectangle` holds three children anchored `verticalCenter`
(Workspaces left, a center `Row`, a right `Row`). Change to **two half-height decks**:
- `topDeck` and `bottomDeck`, each `height: (parent.height − deckGap) / 2`;
  `topDeck` anchored top, `bottomDeck` anchored bottom; both left+right anchored.
- Within each deck: **center** cluster anchored `horizontalCenter` + `verticalCenter`;
  **right** cluster anchored `right` + `verticalCenter`.
  - `topDeck` center = `Clock`; `topDeck` right = the AI-usage blocklets +
    `Brightness` + `AutoDimToggle` + `Audio` + `Stats` + `IdleToggle`.
  - `bottomDeck` center = world-clock blocklet + the two `cal-next` blocklets;
    `bottomDeck` right = `SysTray`.
- **Workspaces** is a sibling overlaying the **left of both decks** (anchored
  top + left, `height: parent.height`), width-budgeted so it stops short of the
  centered clock/calendar.
- Keep **no `border`** on the transparent window (QTBUG-137166 blanks the bar).

### 3. `Workspaces.qml` — wrap across the decks
- `Row → Flow` (QtQuick `Flow` wraps to the next line when it runs out of width).
  `width` = budget from the left margin to just before the centered clock
  (≈ `parent.width/2 − clockHalfWidth − gap`, or a tuned fixed cap); `height` = the
  full bar height so it wraps into two rows.
- Row-band height / `spacing` tuned so the two pill rows sit on the top-deck and
  bottom-deck vertical centers (align against `deckGap`).
- Keep: the monitor filter, the named-workspace sort, per-pill icon + `overrideIcon`
  resolution, and click `activate()`.
- The **special-workspace badge** stays; keep it at the end of the workspace flow
  (still in the top-left region).

## Key risks / gotchas

- **Deck alignment** is the main visual fiddle: the `Flow`'s two rows must line up
  with the two deck centers — tune `Flow` top offset + row spacing against `deckGap`.
- **Width budget:** too wide → pills collide with the clock again; too narrow → they
  wrap too early. Budget to just before the centered clock; verify at a realistic
  worst-case name count.
- **QTBUG-137166:** no Rectangle `border` on the transparent bar window.
- **Relaunch to test** — hot-reload is unreliable through Edit + the dir symlink:
  `pkill -x qs` then relaunch via `hl.dsp.exec_cmd("qs …")`, grep `/tmp/qs.log`,
  screenshot with grim.
- **Both monitors:** confirm on DP-1 and DP-2 (both 4K).

## Out of scope

Dynamic/animated height, per-workspace window previews, an icon-only crowded mode, a
third deck, and runtime chip re-distribution. Which chips sit on which deck is a
static choice in `Bar.qml`, easily edited later.

## Testing / acceptance

- Bar renders ~90 px, two decks, no black/blank; `/tmp/qs.log` shows a clean parse
  (`Configuration Loaded`), no QML errors.
- ~12 long-named workspaces: pills fill the top-left, overflow to the bottom-left,
  **no collision** with the clock; full names intact.
- 2–3 workspaces: bottom deck still shows calendar + tray (not empty); top deck normal.
- Clock centered on the top deck; calendar centered on the bottom deck; tray
  bottom-right; live stats top-right.
- Clicking a pill on either deck switches workspace; the `◆ scratch` badge still
  appears/toggles.
- Verified on DP-1 and DP-2; tiled windows do **not** reflow when opening/closing
  workspaces (always-tall holds the height constant).
