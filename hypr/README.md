# Hyprland config (`~/.dotfiles/hypr`)

Hyprland is configured in **Lua** (not the deprecated `hyprlang` `.conf` format).
`~/.config/hypr` is a symlink to this folder.

| File | Purpose |
|------|---------|
| `hyprland.lua` | Main config: monitors, per-monitor workspaces, keybinds, window rules, look & feel, animations, autostart. |
| `hyprlock.conf` | Lock screen (still hyprlang `.conf` — hyprlock reads its own file). |
| `hypridle.conf` | Idle → lock (5 min) / DPMS off (10 min). Still hyprlang `.conf`. |
| `scripts/` | Helper scripts bound to keys (see below). |

## ⚠️ The Lua-config runtime gotcha

Because the config is Lua, **`hyprctl dispatch <name> …` and `hyprctl keyword …`
are parsed *as Lua* and fail.** To drive Hyprland from a script or the shell,
go through the Lua wrapper:

```sh
hyprctl eval 'hl.dispatch(hl.dsp.<path>({ ... }))'
```

Handy dispatchers (discovered by enumerating `hl.dsp` — `hyprctl eval` swallows
return values but *surfaces errors*, so `... error(s)` prints a table's keys):

```sh
# focus a window by address (address:0x… as `hyprctl clients` reports)
hyprctl eval 'hl.dispatch(hl.dsp.focus({ window = "address:0x55…" }))'
# focus a workspace — numbered by id, named by "name:<name>" (named ws have negative ids)
hyprctl eval 'hl.dispatch(hl.dsp.focus({ workspace = 7 }))'
hyprctl eval 'hl.dispatch(hl.dsp.focus({ workspace = "name:slack" }))'
# warp the cursor (TABLE form only)
hyprctl eval 'hl.dispatch(hl.dsp.cursor.move({ x = 5760, y = 1128 }))'
```

`hyprctl reload` applies `hyprland.lua` changes. The `scripts/` are re-read on
every invocation, so they need no reload.

## Scripts

### `hypr-switch` — SUPER+Space switcher / launcher  ⭐

One `fuzzel --dmenu` window that **merges everything you'd want to jump to**,
filterable by name, instead of the old plain-drun app dump:

- **open windows** → focus (jumps to its workspace/monitor)
- **workspaces** → focus
- **favourite apps** → launch (Slack · Chrome · Telegram · Bolt · OSRS)
- **`All apps…`** → reopens `fuzzel` in full drun mode (launch anything else)

Type `slack` and you'll see the Slack *window*, the *slack* workspace, and (if
it's not already open) the Slack *app* — pick whichever. Each row carries a
**coloured category dot** (windows = blue, workspaces = green, apps = peach,
more = grey) via fuzzel's dmenu icon protocol.

Wired up by `local menu = ".../scripts/hypr-switch"` in `hyprland.lua`, bound to
`SUPER + Space`.

**Design notes / gotchas (all learned the hard way — don't undo these):**

1. **Why fuzzel, not rofi:** rofi here is the X11 build under XWayland, so its
   built-in `window` modi is blind to native-Wayland windows. Everything is
   driven through `hyprctl` instead; fuzzel is Wayland-native.
2. **`--index`**, not text parsing: fuzzel returns the chosen line's index,
   mapped back to a parallel `actions[]` array. Nothing parses display strings.
3. **`follow_mouse = 1` steals focus** to whatever sits under the cursor. So a
   window pick does `focus(window)` **and** warps the cursor onto the window's
   centre (`hl.dsp.cursor.move`) in the same breath.
4. **fuzzel teardown race** (the "display switched but keyboard focus didn't"
   bug): when fuzzel closes it returns focus to the previously-focused window,
   landing *after* an immediate dispatch and stealing it back. Fix: the focus
   dispatch is run **detached (`setsid`) and re-asserted 3× over ~150 ms**, so
   one always lands after the teardown and wins.
5. **Dedup:** a launch entry is suppressed when that app already has a window
   open — otherwise fuzzel's fuzzy rank floats "launch Slack" above the switch
   targets and Enter re-launches an already-running app (a no-op).

**Customising:**

- **Favourite apps** — edit the `apps=(…)` array near the top of the script:
  `command <TAB> Label <TAB> open-token` (the token is a lowercase substring of
  the window class; if a matching window is open, the launch entry is hidden).
- **Theme** — `~/.dotfiles/fuzzel/fuzzel.ini` (Catppuccin Mocha, symlinked to
  `~/.config/fuzzel`). Colours, font, size, border radius live there.
- **Category dot colours** — `~/.dotfiles/fuzzel/swatches/{window,workspace,app,more}.png`
  (64×64 filled circles; regenerate with ImageMagick).
- **Preview without acting** — `HYPR_SWITCH_DUMP=1 hypr-switch` prints the plain
  label list; `HYPR_SWITCH_DUMP=icons hypr-switch` emits the real fuzzel feed
  (label + per-row icon) for piping into a throwaway `fuzzel`.

### `hypr-rename` — SUPER+SHIFT+A
Rename the **current** workspace via a rofi prompt (`hl.dsp.workspace.rename`).

### `hypr-move` — SUPER+SHIFT+S
Move the **focused window** to a chosen/typed workspace (existing ones are
offered; type a new name to create-and-follow).

## Related

- `../fuzzel/` — the switcher's theme (`fuzzel.ini`) + category dot swatches.
- Waybar/Quickshell bars render the same workspaces this switcher navigates.
