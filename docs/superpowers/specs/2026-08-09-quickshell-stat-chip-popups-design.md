# Quickshell stat-chip detail popups + sparklines — design

**Date:** 2026-08-09
**Status:** Approved in brainstorming — not yet built.
**Author:** Ivan + Claude

## Motivation

The right cluster of the bar shows five live system readouts — `↓↑ net`,
`CPU %`, `MEM %`, `°C`, `LOAD` — rendered by `Stats.qml` as pure colored pills
with **no interaction at all**. You can see a number spike but can't do
anything with it. "Enrich the badges": make each chip a click target that drops
down a small detail panel — top processes, sensors, per-interface rates — with a
live mini-graph of recent history for that metric.

The neighboring `auto` / AutoDim toggles and the system tray already do things;
they are out of scope. This is only about the five inert `Stats.qml` chips.

## Decisions (locked in brainstorming)

- **Interaction model:** in-bar **drop-down popups**, not launched apps. Each
  chip opens a `PopupWindow` beneath itself, dismissed on click-away — the exact
  mechanism `Audio.qml` already uses for its volume slider.
- **Content:** **read-only** (lists + numbers). No process killing, no other
  destructive actions.
- **Extra:** **history sparklines** — a small live mini-graph per metric.
- **Scope:** all five chips (net included).
- **History window:** ~2 minutes (~60 samples at the existing 2 s poll),
  tunable via one constant.

## Out of scope (YAGNI)

- No click-to-kill / any mutating action.
- No per-core 24-bar strip (busy at 24 cores; sparkline + top-procs carries it).
- No right-click / scroll behaviors on the stat chips.
- No config knobs / preferences UI.
- `auto`, AutoDim, tray, and every other module untouched.

## Architecture

Two data paths, deliberately split by cadence:

1. **Always-on, cheap (sparklines):** the existing `Sys` singleton already polls
   `lib/sysinfo.sh` every 2 s for cpu%/mem%/temp/net/load. Extend it to also
   push each sample into a fixed-length rolling buffer. Because `Sys` runs from
   login, opening a popup shows the **last ~2 minutes already populated** — not a
   graph that starts blank and fills while you watch.

2. **On-demand, richer (detail lists):** a new `lib/sysdetail.sh <section>`
   script fetches the heavier detail (top processes, full sensor list, per-iface
   rates) **only while a popup is open**, refreshed on a ~2 s timer that stops
   when the popup closes. A rarely-opened popup costs zero `ps`/`sensors` calls.

### Files

| File | Change |
|---|---|
| `Sys.qml` | **+** rolling history arrays: `cpuHist`, `memHist`, `tempHist`, `loadHist`, `netRxHist`, `netTxHist`. Cap at `HIST_LEN` (≈60). Reassign the array each tick (in-place `push` doesn't notify QML bindings). |
| `lib/sysdetail.sh` | **new** — `sysdetail.sh <cpu\|mem\|temp\|load\|net>` → one JSON object on stdout. Uses only `/usr/bin` tools (`ps`, `free`, `sensors`, `nvidia-smi`, `awk`, `/proc`, hwmon), so qs's minimal `PATH=/usr/local/bin:/usr/bin` is fine — **no `~/.local/bin` dependency** (avoids the blocklet-PATH gotcha). |
| `Sparkline.qml` | **new** — reusable `Canvas` polyline. Props: `values` (array), `stroke` (color), optional `values2`/`stroke2` (net's dual rx/tx), `minY`/`maxY` (fixed 0–100 for %, autoscale otherwise). `requestPaint()` on data change. |
| `StatChip.qml` | **new** — the clickable pill **+** the drop-down popup shell. Owns: the colored `Rectangle` pill + `MouseArea` (left-click toggles), the `PopupWindow` (anchor + focus-grab cloned from `Audio.qml`), a `Sparkline`, the detail `Process` + refresh `Timer`, and a `contentComponent` slot the caller fills per section. |
| `Stats.qml` | Replace the five inline `Chip`s with five `StatChip`s — each given its `label` binding, `accent`, `section`, bound `history` array, and a `contentComponent` delegate that renders that section's parsed JSON. |

`Bar.qml` is **unchanged** — `Stats {}` stays in its Row exactly where it is.

### `StatChip.qml` responsibilities (the one reused unit)

The pill looks identical to today's `Chip`. On click it toggles a `PopupWindow`
that:

- **Anchors** like Audio's: `anchor.item: <pill>`, `anchor.edges: Bottom|Right`,
  `anchor.gravity: Bottom|Left`, transparent window + inner `Rectangle`
  (`Theme.barBg`, `topMargin: 6` see-through gap). Never sets `anchor.rect.x`
  (collapses the rect — gotcha 5).
- **Dismisses on click-away** by **reusing Audio's imperative focus-grab
  arming verbatim**: a 150 ms `grabArm` Timer + a `Connections` on
  `onVisibleChanged`. The naive `active: popup.visible` binding is known-broken
  here; the code comment in `Audio.qml` explains why, so we don't reintroduce it.
- **Header:** the metric's current big value (same text as the pill) in the
  metric's accent color.
- **Sparkline:** full popup width, ~28 px tall, `stroke: <accent>`, fed the
  bound `Sys.*Hist` array.
- **Detail body:** rendered by the per-section `contentComponent` from the
  parsed JSON `model`. Re-fetched every ~2 s **only while `popup.visible`**.

### Popup content per chip

| Chip | Section | Sparkline | Detail body (from `sysdetail.sh`) |
|---|---|---|---|
| **CPU** | `cpu` | cpu% 0–100 | Top 5 processes by CPU% — `comm` + `pcpu` |
| **MEM** | `mem` | mem% 0–100 | `used / cached / available / swap` line + top 5 by RSS (`comm` + MB) |
| **63°C** | `temp` | package °C (autoscale) | CPU package + a few hottest cores, NVMe composite, **GPU temp + fan% via `nvidia-smi`**, chassis fan RPM via `sensors` |
| **LOAD** | `load` | 1-min load (autoscale) | `1 / 5 / 15` averages · `3.85 / 24 cores (16% saturated)` · uptime |
| **net** | `net` | dual: ↓rx + ↑tx | Per-interface (non-`lo`, up) current ↓/↑ rate (script self-samples ~0.4 s to get a delta) + session totals for the primary iface |

### `sysdetail.sh` output contract

One JSON object per invocation, e.g. `sysdetail.sh cpu`:

```json
{ "procs": [ {"name":"chrome","pct":42.1}, ... ] }
```

`mem` → `{ "used_mb":…, "cached_mb":…, "avail_mb":…, "swap_mb":…, "procs":[{"name","mb"}…] }`
`temp` → `{ "sensors":[{"label":"CPU pkg","c":63},{"label":"GPU","c":51,"fan":38}, …] }`
`load` → `{ "l1":…, "l5":…, "l15":…, "cores":24, "uptime":"3d 4h" }`
`net` → `{ "ifaces":[{"name":"enp…","rx":12345,"tx":678}, …], "primary":"enp…" }`

QML parses with `JSON.parse` in the `Process`'s `StdioCollector.onStreamFinished`.
Malformed / empty output leaves the last-good model in place (no flicker).

## Interaction & edge cases

- Left-click toggles; a second click or any click-away closes.
- Only one popup meaningfully open at a time in practice; no explicit
  mutual-exclusion needed (click-away closes the previous before the next opens).
- Detail refresh Timer is `running: popup.visible` — no work while closed.
- `net` per-iface sampling adds ~0.4 s latency to that popup's refresh only;
  acceptable and isolated to the net section.
- History arrays are seeded empty; the sparkline renders nothing until it has
  ≥2 points, then draws a growing line (normal for a fresh login).

## Testing / QA (per the quickshell-bar dev loop)

1. **`sysdetail.sh` standalone first** — run each section, validate JSON with
   `jq`, before touching QML. This is the only part with real logic to get wrong.
2. **Relaunch** `qs` via `hyprctl dispatch exec` (never trust hot-reload);
   `grep -iE 'error|warning' /tmp/qs.log` — expect `Configuration Loaded`.
3. **Screenshot each popup open** (grim per-output + crop, or hypr-cua
   `screenshot`/`click`) to confirm anchor, click-away, sparkline, and body.
4. Confirm the bar still renders (no accidental `border` → QTBUG-137166 blank).

## Commit hygiene

`~/.dotfiles` is shared `master` with concurrent agent sessions + the user's own
uncommitted edits (`hypr/hyprland.lua`, `waybar/config.jsonc`,
`claude/settings.json`). **Stage only these explicit files** — never `git add -A`:
`Sys.qml`, `Stats.qml`, `Sparkline.qml`, `StatChip.qml`, `lib/sysdetail.sh`, and
this spec. Commit-message trailer: `Co-Authored-By: Claude …`.
