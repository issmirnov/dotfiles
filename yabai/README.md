# yabai + skhd — window manager reference

Tiling window manager for macOS: **yabai** (the WM) + **skhd** (hotkeys) + **JankyBorders**
(`borders`, the active-window highlight). Keybindings are defined in
[`../skhd/base`](../skhd/base) and compiled to `skhdrc.generated` by
[`../skhd/generator.sh`](../skhd/generator.sh). yabai settings live in [`yabairc`](yabairc).

> **The `asmvik` name is not a mystery:** `asmvik` == `koekeishiya` == **Åsmund Vikane**,
> the author of yabai (two GitHub handles, same person). Recent yabai rebranded its bundle id
> `com.koekeishiya.yabai` → `com.asmvik.yabai`, so the launchd service and every
> `yabai --start/stop/restart-service` command use **`com.asmvik.yabai`**. This is stock and
> official — not a fork. (skhd is still `com.koekeishiya.skhd`; only yabai was rebranded.)

## Modifier legend

| Symbol | Key |
|:------:|-----|
| ⌥ | Option (`alt`) |
| ⌘ | Command (`cmd`) |
| ⇧ | Shift (`shift`) |
| ⌃ | Control (`ctrl`) |

## Focus

| Keys | Action |
|------|--------|
| ⌥ ← ↓ ↑ → | Focus the window in that direction (← / → fall back to the adjacent display) |
| ⌥⌃ D / F | Focus window west / east (alternative to the arrows) |

## Move & arrange

| Keys | Action |
|------|--------|
| ⌘⇧ ← ↓ ↑ → | Swap window in that direction (or move it to the adjacent display) |
| ⌥ Space | Balance all windows to equal size |
| ⌥ R | Rotate the layout tree 90° |
| ⌥⇧ C | Insertion point **south** — next new window opens *below* (red preview) |
| ⌥⇧ V | Insertion point **east** — next new window opens to the *right* (red preview) |

## Resize mode

Keyboard resizing lives in its own **mode** so it doesn't consume modifier combos. The
active-window border turns **red** while you're in it.

| Keys | Action |
|------|--------|
| ⌥ W | **Enter** resize mode |
| H / L | Resize horizontally (40 px steps) |
| J / K | Resize vertically (40 px steps) |
| Esc / Return | **Exit** resize mode |

*Each key nudges whichever edge the window actually owns in the split, so one key works no
matter where the window sits.*

## Stacks

A **stack** piles several windows into one tile (like browser tabs) — only one is visible at a
time.

| Keys | Action |
|------|--------|
| ⌥⇧ S | **Stack** the last-focused window onto the current one |
| ⌃⌥ ↑ / ↓ | Cycle to the previous / next window in the stack |
| ⌥⇧ U | **Unstack** the focused window — pop it back out into a normal split |

> **Undoing a stack:** yabai has no direct un-stack command, so ⌥⇧U floats the window and
> immediately re-tiles it (`--toggle float` twice). That removes it from the stack and
> re-inserts it as a normal bsp split. Repeat per window to break up a larger stack.

## Fullscreen

| Keys | Action |
|------|--------|
| ⌥ F | **Zoom** — fill the current tile, ignoring gaps (still managed) |
| ⇧⌥ F | **Windowed-fullscreen** — fill the whole display, no native macOS fullscreen space |

## Spaces & displays

| Keys | Action |
|------|--------|
| ⌘⇧ X | Move window to the **next space** and follow it |
| ⌥⇧ R | Move window to the **other display** and keep focus on it |
| ⌃⌥ ← / → | Focus the display to the west / east |

## Windows & apps

| Keys | Action |
|------|--------|
| ⌥ Q | Close the focused window |
| ⌥ S | Toggle **sticky** (show on all spaces) — *needs the scripting addition; inert under full SIP* |
| ⌘ Return | Open Terminal |
| ⌥ Z / ⌥ X | Open Chrome — work / personal profile |

## Mouse (hold **fn**)

| Action | Result |
|--------|--------|
| fn + drag | Move window |
| fn + right-drag | Resize window |

## Managing the services

| Task | Command |
|------|---------|
| Restart yabai (reloads `yabairc`) | `yabai --restart-service` |
| Rebuild + reload skhd after editing `base` | `~/.dotfiles/skhd/generator.sh` |
| Restart skhd (if `--reload` hits the pid-file bug) | `skhd --restart-service` |
| Restart borders | `brew services restart borders` |

After editing `skhd/base`, run `generator.sh` — it rebuilds `skhdrc.generated` (the file skhd
actually reads) and reloads skhd. **Don't edit `skhdrc.generated` directly**; it's overwritten.

`yabairc` is **executed** by yabai at launch, so it must stay executable (`chmod +x`). yabai
opens its socket *before* running the config, so when scripting a restart, wait on a config
value (e.g. `window_gap`) rather than just the socket being up.

## Currently disabled (needs the scripting addition)

SIP is fully enabled on this machine, so yabai's scripting addition (SA) can't load. These are
**commented out** because they'd fail:

- **Create / destroy spaces** (⌘⇧Z, ⌥⇧N, ⌘⇧Q) — need the SA.
- **Window opacity** and **window animations** — need the SA.
- **Sticky** (⌥S) — needs the SA (the bind exists but is inert).

To unlock them, partially disable SIP and load the SA (yabai wiki:
*Installing yabai → Configure scripting addition*). Focus-follows-mouse, resize, stacks, and
windowed-fullscreen all work **without** it.

## Files

| Path | What |
|------|------|
| `yabai/yabairc` | yabai settings — executed at launch; keep it `chmod +x` |
| `skhd/base` | **source** for keybindings — edit here |
| `skhd/generator.sh` | rebuilds `skhdrc.generated` from `base` and reloads skhd |
| `~/.config/borders/bordersrc` | JankyBorders colors (orange active / grey inactive) — *not tracked in dotfiles yet* |
