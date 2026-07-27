# borders — JankyBorders

Draws the colored outline around windows — the **active-window highlight** for the
[yabai](../yabai/README.md) tiling setup. Without it, there's no visual cue for which
window is focused.

## Why this exists

yabai used to draw window borders itself, but that was **removed in yabai v6.0.0**
(along with every `window_border*` / `*_border_color` config option). The author split
it out into a standalone tool, **[JankyBorders](https://github.com/FelixKratz/JankyBorders)**
(`borders`), which this folder configures.

Unlike yabai's scripting addition, borders needs **no SIP changes and no scripting
addition** — it uses public macOS APIs, so it works even with SIP fully enabled (which is
the case on this machine — see the SIP notes in [`../yabai/README.md`](../yabai/README.md)).

## Install

```sh
brew install FelixKratz/formulae/borders   # the borders binary (its own Homebrew tap)
brew services start borders                # run it as a login service
```

Manage it with `brew services restart|stop borders`.

## How it's wired

- **`bordersrc`** — the config (colors, width, style). dotbot symlinks it to
  `~/.config/borders/bordersrc` (see the link in [`../osx.conf.yaml`](../osx.conf.yaml)),
  which is where the `borders` daemon looks for it. It must stay executable — the daemon
  runs it as a script on startup.
- Colors mirror the old built-in yabai borders: **orange active** (`0xffffa500`),
  **grey inactive** (`0xff505050`), width `6`, `round` style.
- The skhd **resize mode** flips the active color to **red** (`0xffff3b30`) as a mode
  indicator — see the `:: resize` mode block in [`../skhd/base`](../skhd/base). That's why
  editing colors here should stay in sync with those two lines.

## Files

| Path | What |
|------|------|
| `bordersrc` | borders config — executable; run by the `borders` daemon on start |
| `~/.config/borders/bordersrc` | dotbot symlink → this folder (created by `osx.conf.yaml`) |
