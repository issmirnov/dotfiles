# Quickshell bar for Hyprland — design

**Date:** 2026-08-05
**Status:** SHIPPED 2026-08-05 — default bar (waybar one uncomment away). See addendum + `project_hexane_quickshell_bar` memory for the living details/gotchas.
**Author:** Ivan + Claude

## Motivation

Waybar's click-to-switch-workspace is broken on Hyprland 0.56's Lua dispatch
(waybar issue #5008 — `hyprland/workspaces` hardcodes the dead
`dispatch workspace N`, and it isn't overridable in config). Rather than patch
and maintain a forked waybar, we replace it with a **Quickshell** bar (QtQuick
toolkit, the current momentum in the Hyprland ecosystem), where we control the
click handler and can send the working `hl.dsp.focus({workspace=N})`.

Secondary goal: a fresh, nicer look. **Waybar is kept as an instant fallback**
(one uncommented line) so we can switch back anytime.

## Decisions (locked in brainstorming)

- **Structure:** a single unified, rounded "floating" bar at the top, inset from
  the screen edges (option B).
- **Monitors:** DP-1 (left) + DP-2 (right) only — one bar per monitor. The
  Corsair Xeneon Edge (HDMI-A-2) keeps its own dashboard, no bar.
- **Theme:** pastel / Catppuccin-ish by default; **vivid** (today's colorful
  per-module style) kept as a swappable alternate. Theming is first-class: a
  `Theme` singleton, swapping the whole palette is a one-line change.
- **v1 modules (MVP):** clickable **workspaces with live per-workspace window
  icons**, clock, audio (Pipewire volume), network, CPU, memory, temperature,
  system tray.
- **Clicks:** `Hyprland.dispatch("hl.dsp.focus({workspace=N})")`.

## Out of scope for v1 (iterate later)

Media/Mpris, power-profiles, backlight, submap indicator, idle-inhibitor toggle,
a live theme-switch UI, and any bar on the Xeneon Edge.

## Architecture

Config lives in the dotfiles and is symlinked in by dotbot:
`~/.dotfiles/quickshell/` → `~/.config/quickshell/` (Quickshell's default config
dir; entrypoint `shell.qml`).

```
quickshell/
├── shell.qml               # entrypoint: Variants over screens → one Bar per DP-1/DP-2
├── Theme.qml               # SINGLETON palette + metrics (pastel default, vivid alt)
├── qmldir                  # registers the Theme singleton (if required by 0.3 pattern)
├── bar/
│   └── Bar.qml             # the floating rounded PanelWindow; left / center / right slots
├── modules/
│   ├── Workspaces.qml      # per-monitor pills: number + window app icons; click→focus
│   ├── Clock.qml
│   ├── Audio.qml           # Pipewire default sink volume/mute; scroll to adjust
│   ├── Stats.qml           # cpu / mem / temp / net
│   └── SysTray.qml         # Quickshell.Services.SystemTray
└── lib/
    └── Sys.qml             # SINGLETON: polls /proc + hwmon on a Timer, exposes cpu/mem/temp/net
```

Each unit has one job and a narrow interface:

- **shell.qml** — instantiates one `Bar` per real monitor (filtering to DP-1/DP-2).
- **Bar.qml** — pure layout container (rounded, inset). Knows nothing about data;
  composes the module components into left/center/right. Takes the monitor it's on.
- **Workspaces.qml** — reads `Hyprland` workspaces + toplevels, filters to this
  monitor, renders pills with app icons, dispatches focus on click. The only
  component that talks to Hyprland dispatch.
- **Sys.qml** (singleton) — the only thing that reads `/proc` and hwmon; polls on a
  timer and exposes reactive `cpu`, `memUsed`, `tempC`, `netUp`/`netDown`. Stats.qml
  is a dumb view over it. (Isolates all the fragile /proc parsing in one place.)
- **Audio.qml / SysTray.qml** — thin views over Quickshell's Pipewire / SystemTray
  services.
- **Theme.qml** (singleton) — colors + metrics (radius, gap, bar height, margins,
  font); every component reads from it. Swapping `variant` flips the whole look.

### Data flow

```
Hyprland singleton ─┬─ workspaces (id, focused, monitor, occupied) ─┐
                    └─ toplevels (class/appId, workspace) ──────────┤→ Workspaces.qml ──click──> Hyprland.dispatch("hl.dsp.focus({workspace=N})")
Pipewire service ───── default sink volume/mute ───────────────────→ Audio.qml
Sys singleton ──────── cpu/mem/temp/net (Timer + FileView on /proc) → Stats.qml
SystemTray service ─── items[] ────────────────────────────────────→ SysTray.qml
Theme singleton ────── colors + metrics ───────────────────────────→ (all)
```

Per-monitor workspace filtering matches the Hyprland rule (1–5 → DP-1, 6–10 → DP-2).

### App icons per workspace

For each toplevel on a workspace, map its `class`/`appId` → an icon via the icon
theme / `DesktopEntries` lookup, rendered as an `IconImage`, with a neutral
fallback glyph for unmatched classes. This replaces waybar's manual
`window-rewrite` map **and** the `workstyle` daemon (the bar reads the client list
directly), so `workstyle` can be dropped from autostart later.

## Theming

`Theme.qml` exposes: `bg`, `barBg`, `surface`, `accent`, `activeWs`, `text`,
`subtext`; per-stat accents `vol`, `net`, `cpu`, `mem`, `temp`; metrics `radius`,
`barRadius`, `gap`, `barHeight`, `marginTop`, `marginSide`; and `font`. A single
`property string variant` selects pastel vs vivid palettes. Later we can make it
watch a file for live switching, but v1 just needs the swap to be a one-liner.

## Rollout & fallback

1. Build files in `~/.dotfiles/quickshell/` on a feature branch `feat/quickshell-bar`.
2. dotbot: add `quickshell` → `~/.config/quickshell` to `default.conf.yaml`; link it
   (or `ln -sfn` directly for testing).
3. Test **without disturbing waybar**: launch via `hyprctl dispatch exec` so
   Hyprland spawns `qs` (the agent shell can't spawn GUIs directly). Iterate with
   `grim` screenshots. Stop waybar temporarily when comparing.
4. Switch autostart in `~/.dotfiles/hypr/hyprland.lua`: comment
   `hl.exec_cmd("waybar")`, add `hl.exec_cmd("qs")` (and drop the `workstyle` line if
   unused). **Keep the waybar line one uncomment away** — reverting is a git checkout.

## Testing / acceptance

- `qs` loads `~/.config/quickshell/shell.qml` and hot-reloads on save.
- Bar renders on DP-1 **and** DP-2, inset/rounded/pastel.
- Workspaces show with correct numbers + window app icons; the active one is
  highlighted; **clicking a workspace switches to it** (the whole point).
- Clock ticks; audio shows/adjusts volume; cpu/mem/temp/net update; tray shows
  the same items as waybar (chrome, slack, etc.).
- Waybar can be restored instantly.

## Risks / unknowns

- Exact Quickshell 0.3.0 API (imports, property names, dispatch signature) —
  mitigated by a dedicated API-research agent before writing QML.
- Temperature sensor path varies by board (Z690) — discover the right
  `hwmon`/`thermal_zone` at build time.
- Launching GUIs from the agent shell is sandboxed (exit 144) — always launch/reload
  via `hyprctl dispatch exec`.

## Addendum — what actually shipped (2026-08-05)

Built and verified on-screen; layout ended up **flat** (no `bar/ modules/ lib/`
subdirs — Quickshell 0.3.0 auto-imports uppercase-neighbor `.qml`, so nesting +
qmldir were unnecessary). Beyond the v1 MVP:

- **Idle-inhibitor toggle** (`IdleToggle.qml`, was out-of-scope) — native
  `Quickshell.Wayland.IdleInhibitor`; file must NOT be named `IdleInhibitor.qml`.
- **Center cluster:** local date/time (`Clock.qml`) + timezones ZAG·PRG·KYV, via a
  generic **`Blocklet.qml`** i3blocks-script runner that reuses `~/.dotfiles/i3/blocklets/*`
  verbatim (worldclock, ai_usage claude/codex, load).
- **Google Calendar** (`lib/cal-next` + `lib/cal-notify`): merges timed events across
  ALL ~17 calendars into **two center chips** — `● happening now · Nm left` (mint) and
  `◷ next event <countdown>` (yellow<15m/red<5m) — plus swaync alerts at 10/5/1 min.
  Both self-hide when empty; `cal-next current` vs `cal-next` (mode = `$1`); cache is
  atomic + `flock`-serialized (3 callers), refreshed from the server every **15 min**
  (chips grey out with a `(stale)` tag if a refresh hasn't landed in 2× that — `CAL_STALE_AFTER`).
  **LIVE.** Auth chain (all required): gws `calendar.readonly` scope → delete stale
  `token_cache.json` → `serviceusage.serviceUsageConsumer` IAM on the OAuth client's
  project. Creds stay in `~/.config/gws`, **out of the dotfiles**.
- **Audio popup:** left-click the volume chip opens a **draggable slider `PopupWindow`**
  (scroll still ±5%, right-click mutes). Anchor: `edges/gravity` flags for the drop-down
  (NOT `anchor.rect.x` — that collapses the rect); dismiss via `HyprlandFocusGrab`.

Gotchas that cost real time (do not re-chase): **QTBUG-137166** — a Rectangle `border`
on a `color:"transparent"` window blanks the whole bar (this was the "black bar", NOT a
grim/dmabuf capture limit; grim captures fine). Hot-reload through the dir-symlink is
flaky → **relaunch** `qs` to apply. `DesktopEntries.heuristicLookup` is a no-op here →
icons resolve by `hasThemeIcon(class)` + `/usr/share/pixmaps/<class>` + an `overrideIcon`
map. **⚠️ qs launches blocklets with a minimal `PATH` (`/usr/local/bin:/usr/bin`)** — any
script that shells out to a `~/.local/bin` tool (e.g. `gws`) must set its own `PATH` or the
call silently fails and the cache freezes (this exact bug showed hours-stale calendar events
while the fetch quietly no-op'd). Full living notes in the hexane bar KB doc under `~/docs`.

### Still open
- **Codex `CX ?`** — needs a user `codex` re-auth (access_token expired = 401).
- Not yet in dotbot `ubuntu.conf.yaml` (currently `ln -sfn`; adding it fires the
  vim-pluginstall hook, so deferred). Possible later: media/Mpris, network/disk blocklets.
