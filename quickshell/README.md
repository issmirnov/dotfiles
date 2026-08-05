# Quickshell bar (hexane)

A custom Qt6/QML status bar for **Hyprland** on hexane, built with
[Quickshell](https://quickshell.outfoxxed.me). It replaces waybar and is the
default bar (the Hyprland autostart runs `qs`).

Design spec: `../docs/superpowers/specs/2026-08-05-quickshell-bar-design.md`.

## Why not waybar?

Hyprland 0.56 on this machine is configured in **Lua**, so `hyprctl dispatch <name>`
is parsed *as Lua* and the legacy `dispatch workspace N` IPC form is dead. waybar's
`hyprland/workspaces` click handler hardcodes that legacy form, so **clicking a
workspace silently did nothing**. Quickshell calls `HyprlandWorkspace.activate()`
(the correct Lua-aware path), so click-to-switch works — and we also get live
per-window app icons, native Wayland popups, and a floating rounded pastel bar.

See `../hypr/hyprland.lua` for the compositor side.

## How it loads

- `~/.config/quickshell` is a **symlink** to `~/.dotfiles/quickshell` (this folder),
  so edits here are live config.
- **Flat layout, no `qmldir`**: Quickshell auto-imports any uppercase-neighbour
  `*.qml` as a type, so `Bar {}`, `Workspaces {}`, `Theme.x` resolve by filename.
- Entry `shell.qml` → a `Variants` block spawns one `Bar` per screen **except the
  Corsair Xeneon Edge** (`HDMI-A-2`, which runs its own dashboard).

## File map

| File | Role |
|------|------|
| `shell.qml` | Entry. One `Bar` per monitor; a 5 s timer calls `Hyprland.refreshToplevels()` (keeps window classes / icons fresh — `lastIpcObject.class` isn't reactive); a 1 min timer runs `lib/cal-notify`. |
| `Bar.qml` | One floating, rounded `PanelWindow` per monitor. Pure layout: left = `Workspaces`, center = `Clock` + worldclock + calendar, right = AI-usage + `Audio` + `Stats` + `IdleToggle` + `SysTray`. |
| `Workspaces.qml` | **Per-monitor workspace pills** — sort, click, and app icons (the focus of this doc). |
| `Theme.qml` | Singleton palette + metrics; `variant` flips `"pastel"`/`"vivid"`. |
| `Clock.qml` | Center date/time (`SystemClock`). |
| `Blocklet.qml` | Generic i3blocks-script runner; reuses `../i3/blocklets/*` verbatim (worldclock, `ai_usage`). |
| `Audio.qml` | PipeWire volume; left-click opens a draggable slider `PopupWindow`. |
| `Sys.qml` / `Stats.qml` | `Sys` runs `lib/sysinfo.sh` (cpu/mem/temp/net/load); `Stats` renders the chips. |
| `IdleToggle.qml` | Idle-inhibitor toggle (named `IdleToggle`, **not** `IdleInhibitor` — see gotchas). |
| `SysTray.qml` | System tray. |
| `lib/` | `sysinfo.sh`, `cal-next` (next-calendar-event chip), `cal-notify` (swaync alerts). |

## Workspace pills (`Workspaces.qml`)

### Sorting — the 2026-08-05 work

Hyprland gives **numbered** workspaces positive ids (`1, 2, …`) and **named**
workspaces *negative* ids that grow more negative with each one created. The
original sort was a plain `a.id - b.id`, which shoved every named workspace
(negative id) **ahead** of the numbers, and made a freshly-created one jump to the
very front — wrecking spatial muscle memory. The trigger was making a workspace
called `test2` and watching it shuffle to position 1.

The sort is now **by label**:

```js
.sort((a, b) => {
    const aNum = /^[0-9]+$/.test(a.name), bNum = /^[0-9]+$/.test(b.name);
    if (aNum !== bNum) return aNum ? -1 : 1;          // numeric labels first
    if (aNum) return Number(a.name) - Number(b.name); // …ascending by value
    return b.id - a.id;                               // word labels: newest last
});
```

Rules, in order:

1. **Numeric-labelled workspaces first**, ascending by value (`1 2 4 6 …`). A
   workspace whose *label* is a number counts here.
2. **Word-labelled workspaces after** — including a **renamed numbered** workspace
   (e.g. workspace `2` renamed to `pinley`). It groups with the named spaces, not
   in slot 2. This was a deliberate choice ("push word labels to the end"); the
   alternative — keep renamed-numbered ones in their numeric slot by testing
   `id < 0` instead of the label — is a one-line change.
3. **Within the word group, descending id.** Named spaces made via the move bind
   get increasingly-negative ids, so descending id keeps existing ones put and
   **appends new ones at the end**.

Result, e.g.:

```
DP-1:  4 · hypr · pinley · bar-nav
DP-2:  6 · 7 · 9 · 10 · slack · telegram · osrs
```

> Word-group order is by id, not alphabetical — so `hypr` precedes `pinley`
> (ids 5 > 2). For alphabetical instead, swap the last line for
> `a.name.localeCompare(b.name)`; the trade-off is that a new early-sorting name
> lands mid-list rather than at the end.

### Click to switch

`onClicked: pill.ws.activate()` → `HyprlandWorkspace.activate()`, which issues the
correct Lua dispatch. This is the whole reason we left waybar.

### App icons

Each pill shows an icon per window on that workspace, resolved from the window
**class**, in this order:

1. `overrideIcon` — an explicit `file://` path matched by class substring, for apps
   whose class isn't a valid icon-theme name: RuneLite, Telegram (per-account-hash
   class), Signal, ZapZap/WhatsApp, Obsidian, VS Code, Cursor, Zoom.
2. else `Quickshell.hasThemeIcon(class)` → the theme icon.
3. else a neutral dot placeholder (never a broken-image icon).

> ⚠️ `DesktopEntries.heuristicLookup` is a **no-op in this Quickshell build** — the
> class must itself equal an icon name or you get the dot. That's why the override
> map exists. Add new entries in the `overrideIcon` block.

## Related: the workspace create/rename/move keybinds

The named workspaces this bar sorts are created by Hyprland binds in
`../hypr/hyprland.lua`, with scripts in `../hypr/scripts/` — ported from the old i3
rofi flow:

- `SUPER+SHIFT+A` → `hypr-rename`: rename the current workspace (rofi prompt).
- `SUPER+SHIFT+S` → `hypr-move`: move the focused window to a picked/typed
  workspace. A **new** target is created and followed; an **existing** one gets a
  silent move (you stay put).
- `SUPER+SHIFT+[0-9]` → move to a numbered workspace.

Key gotcha those scripts encode: on this Lua Hyprland you dispatch via
`hyprctl eval 'hl.dispatch(hl.dsp.…)'` (not `hyprctl dispatch …`), and a **named**
target must be `name:foo` — a bare non-existent name errors `Invalid workspace` and
moves nothing. `hl.dsp.workspace.rename` takes `{ workspace = <id>, name = "…" }`;
`hl.dsp.window.move` takes `{ workspace = <N | "name:x">, follow = <bool> }`.

## Running / reloading

- Autostart: `hl.exec_cmd("qs")` in `../hypr/hyprland.lua`.
- **Hot-reload is flaky** through editor writes + the dir symlink. To apply a change
  reliably, relaunch:

  ```sh
  pkill -x qs
  hyprctl dispatch 'hl.dsp.exec_cmd("qs >/tmp/qs.log 2>&1")'
  ```

  Launch via `hyprctl` (a plain `qs &` from a sandboxed shell gets killed). Log at
  `/tmp/qs.log`.

## Gotchas (don't re-chase)

- **QTBUG-137166** — a `border` on a `color:"transparent"` window blanks the *entire*
  bar. `Bar.qml` deliberately has no border; the visible bar is an inner `Rectangle`.
- **Neighbour-file shadowing** — an `X.qml` shadows Quickshell's own `X` type. This
  bit the idle inhibitor, hence `IdleToggle.qml` (not `IdleInhibitor.qml`).
- **`PopupWindow` anchoring** — align with `anchor.edges` / `anchor.gravity`, not
  `anchor.rect.x` alone (that collapses the rect to bar level). See `Audio.qml`.
- Screenshots of the bar *do* work once it renders (per-output `grim`, or the
  hypr-cua MCP), despite the NVIDIA dmabuf surface.

## Calendar / `gws`

The center calendar chip (`lib/cal-next`) merges timed events across all Google
calendars and needs `gws auth login --services gmail,calendar --readonly`; creds
live in `~/.config/gws` (outside dotfiles). When broken the chip shows `cal ?`.
Full auth chain is in the project memory.
