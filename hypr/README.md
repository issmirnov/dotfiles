# Hyprland config (`~/.dotfiles/hypr`)

Hyprland is configured in **Lua** (not the deprecated `hyprlang` `.conf` format).
`~/.config/hypr` is a symlink to this folder.

| File | Purpose |
|------|---------|
| `hyprland.lua` | Main config: monitors, per-monitor workspaces, keybinds, window rules, look & feel, animations, autostart. |
| `hyprlock.conf` | Lock screen (still hyprlang `.conf` — hyprlock reads its own file). |
| `hypridle.conf` | Idle → lock (5 min) / DPMS off (10 min). Still hyprlang `.conf`. |
| `scripts/` | Helper scripts bound to keys (see below). |
| `hyprsunset.conf` | Blue-light filter profiles (day 4500K / night 3200K). Read by `hyprsunset`. |
| `xdph.conf` | `xdg-desktop-portal-hyprland` config (screencast). |

## 📦 Provisioning a new box — required packages & setup

Everything below is what this setup **actually** touches, verified against
`hyprland.lua` (autostart + keybinds) and `scripts/`. Install these and the config
comes up as expected.

### Official repo — `sudo pacman -S …`

**Compositor & session**

| Package | Why |
|---|---|
| `hyprland` | Compositor. Session file `/usr/share/wayland-sessions/hyprland.desktop`. |
| `hyprlock` | Lock screen — `hyprlock.conf` (SUPER+L, hypridle). |
| `hypridle` | Idle → lock / DPMS — `hypridle.conf`. |
| `hyprsunset` | Blue-light filter — `hyprsunset.conf`. **Replaced wlsunset** (Aug 2026). |
| `xdg-desktop-portal` + `xdg-desktop-portal-hyprland` + `xdg-desktop-portal-gtk` | Screencast (Chrome/Meet) + file pickers. ⚠️ Portals restart **first** at boot — see the env-race note above line 87 in `hyprland.lua`. |

**Shell — bar / wallpaper / launcher / notifications**

| Package | Why |
|---|---|
| `quickshell` | Status bar (default; `qs`). |
| `waybar` | Fallback bar (commented autostart). |
| `swaybg` | Per-monitor wallpapers (hyprpaper's parser was dead → swaybg). |
| `fuzzel` | Wayland-native launcher — `hypr-switch` (SUPER+Space). |
| `rofi` | Text prompts for `hypr-rename` / `hypr-move` (SUPER+SHIFT+A/S). |
| `dunst` | Notifications (grimblast `--notify`, etc.). |

**Clipboard / screenshots / scripting**

| Package | Why |
|---|---|
| `cliphist` + `wl-clipboard` + `fzf` | Clipboard history: `wl-paste --watch cliphist store`; picker = SUPER+SHIFT+P (alacritty + fzf). |
| `jq` | `hyprctl -j` parsing throughout `scripts/`. |

**Terminals**

| Package | Why |
|---|---|
| `foot` | Default terminal (SUPER+Return + boot). |
| `alacritty` | Scratchpad (SUPER+C) + cliphist picker + fallback. |

**Hardware / audio**

| Package | Why |
|---|---|
| `ddcutil` | DDC/CI backlight (`hexane-nightlight` dimming). Needs `i2c-dev` module + user in `i2c` group. |
| `pipewire` + `pipewire-pulse` + `wireplumber` | Audio + screenshare (`WebRTCPipeWireCapturer`). |

**Trays / file manager / fonts**

| Package | Why |
|---|---|
| `network-manager-applet` | `nm-applet --indicator` (network tray). |
| `blueman` | `blueman-applet` (bluetooth tray). |
| `nemo` | File manager (SUPER+X, via `env GDK_DPI_SCALE=1.4 nemo`). ⚠️ `open .`/xdg-open bypass that scale — needs a `nemo.desktop` override (see the **nemo font scaling** gotcha below). |
| `ttf-jetbrains-mono-nerd` | UI + terminal font (JetBrainsMono Nerd Font). |
| `otf-font-awesome` | Font Awesome **7** glyphs (bar, dunst). ⚠️ restart procs after font changes (fontconfig). |

### AUR — `yay -S …`

| Package | Why |
|---|---|
| `google-chrome` | Browser (`google-chrome-stable`, Wayland/ozone flags in `hyprland.lua`). |
| `webcord` | Discord client (Electron; avoids the segfault a plain client hits here). |
| `grimblast-git` | Screenshots (XF86Tools binds). `grimshot` also installed as an alt. |
| `noisetorch` | RNN mic noise suppression. |
| `slack-desktop`, `spotify` | Apps. (Telegram = official `telegram-desktop`.) |

### hyprpm plugin — `hyprbars` (window title bars)

Compiles against Hyprland headers, so it needs sudo and a rebuild on every upgrade
(also documented at `hyprland.lua:368`):

```sh
hyprpm update
hyprpm add https://github.com/hyprwm/hyprland-plugins
hyprpm enable hyprbars
hyprpm reload -n
# after EVERY hyprland upgrade (ABI break → plugin silently vanishes):
hyprpm update && hyprpm reload -n
```

### Custom `systemd --user` units (`~/.dotfiles/systemd/` → symlink + `enable --now`)

| Unit | Purpose |
|---|---|
| `xeneon-edge.service` | Xeneon Edge dashboard (auto-detects HDMI-A-2, fullscreens). |
| `mx-mouse-watchdog.service` | MX Vertical BT auto-reconnect. |
| `hexane-nightlight.service` + `.timer` | Sun-tracked backlight **dimming** (ddcutil) — orthogonal to hyprsunset's **colour**. |
| `xdg-desktop-portal-gtk.service.d/` | Drop-in override for the GTK portal. |

### The Lua config is native — no loader needed

Native Lua config landed in **Hyprland 0.55** (mid-2026): the compositor embeds a
Lua 5.4 runtime and, **if `~/.config/hypr/hyprland.lua` exists, loads it instead of
`hyprland.conf`** (checked once at startup — restart to switch formats). The `hl.*`
API is built in, so there's nothing extra to install: a stock `hyprland` package
(≥ 0.55; this box is 0.56.1) picks up `hyprland.lua` on its own. Legacy
`hyprlang`/`hyprland.conf` is deprecated but still works for a release or two.
Ref: <https://hypr.land/news/26_lua>

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

## ⚠️ nemo font scaling — `open .` vs the keybind

nemo's UI is tiny at 4K / `scale = 1`, so it's launched with **`env GDK_DPI_SCALE=1.4
nemo`** (fonts ~40 % bigger; icons/layout unchanged — tune `1.25` subtler / `1.6`
bigger). That wrapper lives only in the **keybind**: `local fileManager` in
`hyprland.lua` (SUPER+X).

**The trap:** `xdg-open` / `open .` (alias `open`→`xdg-open`) / any app that opens a
folder goes through **`nemo.desktop`**, whose stock `Exec=nemo %U` has *no* scale → it
renders small. And nemo is **single-instance**, so whichever launcher starts the
primary process wins for the entire session — open one folder from the terminal and
everything is small "again", even if you later use the keybind.

**Fix — a user desktop-entry override** (⚠️ *not* tracked in this repo; it's a
`~/.local/share` file, so a freshly-provisioned box will hit the bug until you recreate
it). Shadow the system entry so **every** launch path carries the same scale:

`~/.local/share/applications/nemo.desktop` (wins over `/usr/share/applications/nemo.desktop`):

```ini
[Desktop Entry]
Name=Files
Exec=env GDK_DPI_SCALE=1.4 nemo %U
Icon=system-file-manager
Terminal=false
Type=Application
Categories=GNOME;GTK;Utility;Core;
MimeType=inode/directory;application/x-gnome-saved-search;
Actions=open-home;open-computer;open-trash;
# + each [Desktop Action] (open-home/open-computer/open-trash) Exec also prefixed
#   with `env GDK_DPI_SCALE=1.4`
```

Then `update-desktop-database ~/.local/share/applications`. Verify with
`xdg-open <dir>` → `tr '\0' '\n' </proc/$(pgrep -x nemo)/environ | grep GDK_DPI_SCALE`
(should read `1.4`). Two caveats:

- **Only takes effect when no nemo is already running** — single-instance reuses the
  live process's env, so `nemo --quit` (or close every window) first.
- **Keep the `1.4` here identical to `hyprland.lua`'s `fileManager`** or the two launch
  paths diverge again.

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
offered; type a new name to create-and-move). Always silent — focus stays put.

## Related

- `../fuzzel/` — the switcher's theme (`fuzzel.ini`) + category dot swatches.
- Waybar/Quickshell bars render the same workspaces this switcher navigates.
