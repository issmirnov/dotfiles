# Hyprland Keybinds — quick reference

`SUPER` = Super / Windows key. Snapshot of `hyprland.lua` as of **2026-08-18** — not auto-generated, so update it if you rebind something (or ask Claude to regenerate from the config).

## Apps & launchers
| Keys | Action |
|---|---|
| `SUPER + Return` | Terminal (foot) |
| `SUPER + Space` | Launcher — windows + workspaces + fav apps (hypr-switch) |
| `SUPER + X` | File manager (nemo) |
| `SUPER + Z` | Browser — new Chrome window |
| `SUPER + C` | Claude drop-down scratchpad (see **Scratch overlays**) |

## Windows
| Keys | Action |
|---|---|
| `SUPER + Q` | Close window |
| `SUPER + F` | Fullscreen (maximize) toggle |
| `SUPER + SHIFT + F` | Toggle floating |
| `SUPER + Tab` | Cycle to next window |
| `SUPER + ← ↑ ↓ →` | Move focus (direction) |
| `SUPER + SHIFT + ← ↑ ↓ →` | Move window (direction) |
| `SUPER + left-drag` | Move window (mouse) |
| `SUPER + right-drag` | Resize window (mouse) |
| double-click title bar | Maximize toggle (hyprbars) |

## Layout (dwindle)
| Keys | Action |
|---|---|
| `SUPER + J` | Toggle split direction (horizontal / vertical) |
| `SUPER + T` | Swap focused pane with its split sibling |
| `SUPER + R` | Promote focused window to a top-level half |

## Workspaces
| Keys | Action |
|---|---|
| `SUPER + 1`…`0` | Switch to workspace 1–10 (1–5 → left / DP-1, 6–10 → right / DP-2) |
| `SUPER + SHIFT + 1`…`0` | Move focused window to workspace 1–10 |
| `SUPER + scroll` | Previous / next workspace |
| `SUPER + SHIFT + ,` (`<`) | Move current workspace to left monitor (DP-1) |
| `SUPER + SHIFT + .` (`>`) | Move current workspace to right monitor (DP-2) |
| `SUPER + SHIFT + A` | Rename current workspace (rofi) |
| `SUPER + SHIFT + S` | Move focused window to a workspace — typed or picked (rofi); the list includes `special:stash` |

## Jump to an app workspace (`SUPER + ALT`)
| Keys | Action |
|---|---|
| `SUPER + ALT + S` | Slack |
| `SUPER + ALT + T` | Telegram |
| `SUPER + ALT + R` | RuneLite / OSRS |
| `SUPER + ALT + O` | Obsidian |

## Scratch overlays
| Keys | Action |
|---|---|
| `SUPER + C` | **Claude scratch** (drop-down terminal, `special:scratch`) — bar turns 🔴 **red** while it's up |
| `SUPER + S` | **Stash** — a tiling scratch overlay (`special:stash`) — bar turns 🟠 **orange** while it's up |
| `SUPER + SHIFT + S` → pick `special:stash` | Move the focused window **into** the stash |
| click the `◆` badge in the bar | Hide the overlay that's currently up |

**Stash notes:** windows moved in **tile/split** like a normal workspace, inset to ~75% so it floats. To pull a window back **out**: focus it, `SUPER + SHIFT + S`, then pick a normal workspace.

## Screenshots & clipboard
| Keys | Action |
|---|---|
| `XF86Tools` | Screenshot a **region** (freeze + copy + save) |
| `SHIFT + XF86Tools` | Screenshot the **whole monitor** |
| `SUPER + XF86Tools` | Screenshot the **active window** |
| `SUPER + SHIFT + P` | Clipboard history picker (cliphist + fzf) |

Screenshots save to `~/Pictures/YYYY-MM-DD-HHMMSS.png` and copy to the clipboard.

## System
| Keys | Action |
|---|---|
| `SUPER + L` | Lock screen (hyprlock) |
| `SUPER + U` | Focus the urgent / last window |

---
_Source of truth: `~/.dotfiles/hypr/hyprland.lua` (KEYBINDINGS section). Runtime dispatch on this Lua-configured Hyprland goes through `hyprctl eval 'hl.dispatch(hl.dsp.…)'`, not the legacy `hyprctl dispatch`._
