# hexane-nightlight — sun-tracked gentle backlight dimming

**Date:** 2026-08-04
**Status:** design approved; spec pending review
**Host:** hexane (Hyprland/Wayland, 2× Dell U3225QE on DP-1/DP-2)

## Purpose

Gently dim both Dell backlights in the evening and restore them by morning,
tracking the sun, so nights aren't harsh on the eyes. This replaces the
monitor's own ambient auto-brightness (which over-dimmed) with deterministic,
gradual software control. It is independent of `wlsunset`: brightness (backlight,
via DDC/CI) and color temperature (gamma LUT, via wlsunset) are orthogonal
layers and do not interact.

## Locked decisions

- **Levels:** day 100%, night 80%.
- **Ramp:** 100 → 80 over ~45 min, **starting at sunset**; symmetric 80 → 100
  over ~45 min **starting at sunrise**.
- **Step:** 2% (via rounding; ~one 2% step every ~4.5 min during a ramp).
- **Sun tracking:** Denver coords `39.7392, -104.9903` (same as wlsunset).
- **Targets:** both Dells, same level, addressed by serial —
  `DP7HGJ4` (DP-1) and `6P7HGJ4` (DP-2).
- **User space only:** systemd *user* timer + `ddcutil` over the i2c ACL. No sudo.
- **Prerequisite:** monitor Auto Brightness OFF in OSD (confirmed off 2026-08-04).

## Architecture — stateless desired-state on a timer

A script computes the correct brightness **for right now** from today's sun
times and applies it only if it differs from what it last set. A systemd user
timer runs it every ~2 min. During the 45-min ramp each tick nudges ~2%; the
rest of the day it's a no-op.

Self-healing: reboot, suspend, or starting mid-ramp all resolve to "the correct
value for now" — there is no stateful daemon to fall out of sync.

**Rejected alternative — long-running daemon** (sleep → step 2% every 4.5 min →
sleep). More precise, but stateful: needs daily recompute and catch-up logic for
reboot/suspend/missed wake-ups. Not worth the fragility for a ±20% ramp.

## Components

### 1. `bin/hexane-nightlight` (Python 3, no pip deps)

Config constants at top: `LAT`, `LON`, `DAY=100`, `NIGHT=80`, `RAMP_MIN=45`,
`STEP=2`, `MONITORS=["DP7HGJ4","6P7HGJ4"]`, `STATE=~/.cache/hexane-nightlight/last`.

**Pure functions (unit-tested):**
- `sun_times(date, lat, lon) -> (sunrise, sunset)` — dep-free NOAA solar
  algorithm; returns local-tz-aware datetimes.
- `target(now, sunrise, sunset) -> int` — piecewise, rounded to nearest `STEP`:
  - `sunrise ≤ t < sunrise+RAMP` → lerp `NIGHT→DAY`
  - `sunrise+RAMP ≤ t < sunset` → `DAY`
  - `sunset ≤ t < sunset+RAMP` → lerp `DAY→NIGHT`
  - otherwise (night, incl. past midnight) → `NIGHT`

**Effectful:**
- `apply(t)` — read `STATE` (last applied int); if `t` changed, run
  `ddcutil --sn <sn> setvcp 10 t` per monitor (per-monitor try/except so a
  flaky panel logs and doesn't abort the other), then write `STATE=t`.
  Writes only on change (~10 writes/evening). Logs to stderr (journald).

**CLI:**
- *(no args)* — compute + apply (the timer path)
- `--check` — print today's sunrise/sunset, current target, and each panel's
  actual `getvcp 10`
- `--simulate "YYYY-MM-DD HH:MM"` — print target at that instant, no write
- `--dry-run` — compute + print intended action, no write

### 2. systemd user units (new `systemd/` dir in dotfiles)

- `systemd/hexane-nightlight.service` — `Type=oneshot`,
  `ExecStart=%h/.local/bin/hexane-nightlight`
- `systemd/hexane-nightlight.timer` — `OnCalendar=*:0/2` (every 2 min wall-clock,
  robust for a oneshot), `Persistent=true` (catches missed runs after suspend),
  `WantedBy=timers.target`

Enabled once with `systemctl --user enable --now hexane-nightlight.timer`.

### 3. dotbot links (`default.conf.yaml`)

Following existing conventions:
- `~/.local/bin/hexane-nightlight: bin/hexane-nightlight` (like `xeneon-lock`)
- `~/.config/systemd/user/hexane-nightlight.service: systemd/hexane-nightlight.service`
- `~/.config/systemd/user/hexane-nightlight.timer: systemd/hexane-nightlight.timer`

## Curve (Denver, chosen params)

```
sunrise ─▶ +45m : 80 → 100   (gentle wake-up)
+45m    ─▶ sunset : 100       (day)
sunset  ─▶ +45m : 100 → 80   (evening ramp, starts at sunset)
+45m    ─▶ sunrise : 80        (night)
```

## Edge cases

- Boot/resume mid-ramp → sets the correct interpolated value (one small jump).
  Deep-night boot → 80 directly. Expected.
- Cross-midnight spans (sunset+45m, or the night span crossing 00:00) handled by
  tz-aware datetimes.
- `ddcutil` transient failure → logged; next tick (≤2 min) retries. Self-heals.
- Manual brightness change (e.g. a hotkey) is **not** fought during a plateau
  (target unchanged → no write); the next scheduled step re-asserts. Acceptable
  for v1.
- DST handled via system local timezone.

## Testing

- Unit tests: `sun_times` (a known Denver date vs reference, ±~2 min) and
  `target` (each boundary + a mid-ramp point rounds to the expected 2%).
- Live: `--simulate` across a synthetic evening prints the descending 2% ladder;
  `--check` confirms both panels are driven.

## Out of scope (v1, YAGNI)

- No pause/override toggle (movies) — the plateau no-fight behavior partly covers it.
- No per-monitor levels.
- No external config file — constants live in the script.

## Interactions

- Monitor Auto Brightness / ambient sensor must stay OFF in OSD (else it fights
  `ddcutil`). Confirmed off 2026-08-04.
- `wlsunset` untouched (separate gamma layer); no daemon swap.
