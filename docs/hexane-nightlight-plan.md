# hexane-nightlight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A sun-tracked script that gently dims both Dell backlights to 80% at night and restores 100% by day, in 2% steps, driven by a systemd user timer.

**Architecture:** Stateless "desired-state" — a script computes the correct brightness for *now* from today's sun times and writes it via `ddcutil` only when it changes; a user timer runs it every 2 min. No daemon. See `docs/hexane-nightlight-design.md`.

**Tech Stack:** Python 3 stdlib only (no pip deps), `ddcutil`, systemd user units, dotbot.

## Global Constraints

- Python 3 stdlib ONLY — no pip dependencies.
- User space only — no sudo. `ddcutil` works via the existing i2c ACL.
- Coords: `LAT=39.7392`, `LON=-104.9903` (Denver, east-positive; west is negative).
- `DAY=100`, `NIGHT=80`, `RAMP_MIN=45`, `STEP=2`.
- Monitors by serial: `DP7HGJ4` (DP-1), `6P7HGJ4` (DP-2).
- Brightness = DDC VCP `0x10`. Write only on change.
- Script has NO side effects on import — all effects under `if __name__ == "__main__"`.

---

### Task 1: Pure core — `sun_times` + `target`

**Files:**
- Create: `bin/hexane-nightlight` (config + pure functions; `#!/usr/bin/env python3`)
- Test: `tests/test_hexane_nightlight.py` (stdlib `unittest`, loads the script via importlib)

**Interfaces:**
- Produces:
  - `sun_times(day: date, lat: float, lon: float) -> tuple[datetime, datetime]` — (sunrise, sunset), local-tz-aware.
  - `target(now: datetime, sunrise: datetime, sunset: datetime) -> int` — brightness %, multiple of `STEP`.
  - Constants: `LAT, LON, DAY, NIGHT, RAMP_MIN, STEP, MONITORS`.

- [ ] **Step 1: Write failing tests**

```python
# tests/test_hexane_nightlight.py
import importlib.util, pathlib, unittest
from datetime import datetime, date, timedelta

_p = pathlib.Path(__file__).resolve().parents[1] / "bin" / "hexane-nightlight"
_spec = importlib.util.spec_from_file_location("hexane_nightlight", _p)
nl = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(nl)


class SunTimes(unittest.TestCase):
    def test_equator_equinox_is_symmetric_around_noon(self):
        # At the equator on an equinox, day ~12h; sunrise/sunset straddle solar noon.
        sr, ss = nl.sun_times(date(2026, 3, 20), 0.0, 0.0)
        day_len = (ss - sr).total_seconds() / 3600
        self.assertAlmostEqual(day_len, 12.0, delta=0.3)

    def test_denver_early_august_plausible(self):
        # Denver, 2026-08-04: sunrise ~06:00, sunset ~20:10 local (±15 min tolerance).
        sr, ss = nl.sun_times(date(2026, 8, 4), nl.LAT, nl.LON)
        self.assertLess(sr, ss)
        self.assertTrue(5.5 <= sr.hour + sr.minute/60 <= 6.5, f"sunrise {sr}")
        self.assertTrue(19.5 <= ss.hour + ss.minute/60 <= 20.75, f"sunset {ss}")


class Target(unittest.TestCase):
    def setUp(self):
        # Fixed sun times for deterministic curve tests.
        self.sr = datetime(2026, 8, 4, 6, 0).astimezone()
        self.ss = datetime(2026, 8, 4, 20, 0).astimezone()

    def at(self, h, m):
        return datetime(2026, 8, 4, h, m).astimezone()

    def test_midday_is_full(self):
        self.assertEqual(nl.target(self.at(13, 0), self.sr, self.ss), 100)

    def test_deep_night_is_floor(self):
        self.assertEqual(nl.target(self.at(23, 30), self.sr, self.ss), 80)

    def test_start_of_evening_ramp_is_full(self):
        self.assertEqual(nl.target(self.ss, self.sr, self.ss), 100)

    def test_mid_evening_ramp_halfway(self):
        # 22.5 min into the 45-min ramp -> ~90, rounded to STEP.
        self.assertEqual(nl.target(self.at(20, 22), self.sr, self.ss), 90)

    def test_end_of_evening_ramp_is_floor(self):
        self.assertEqual(nl.target(self.at(20, 45), self.sr, self.ss), 80)

    def test_target_is_multiple_of_step(self):
        for m in range(0, 46, 1):
            v = nl.target(self.at(20, 0) + timedelta(minutes=m), self.sr, self.ss)
            self.assertEqual(v % nl.STEP, 0)

    def test_pre_dawn_is_floor(self):
        self.assertEqual(nl.target(self.at(2, 0), self.sr, self.ss), 80)

    def test_morning_ramp_midpoint(self):
        self.assertEqual(nl.target(self.at(6, 22), self.sr, self.ss), 90)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `python3 tests/test_hexane_nightlight.py -v`
Expected: FAIL (module has no `sun_times`/`target`).

- [ ] **Step 3: Implement pure core**

```python
#!/usr/bin/env python3
"""hexane-nightlight — sun-tracked gentle backlight dimming for the Dell U3225QEs.

Stateless: computes the brightness for *now* and applies it only on change.
Design: docs/hexane-nightlight-design.md
"""
import math
import os
import subprocess
import sys
from datetime import datetime, date as date_cls, timezone

# ---- config ----
LAT, LON = 39.7392, -104.9903        # Denver (east-positive; west negative)
DAY, NIGHT = 100, 80
RAMP_MIN = 45
STEP = 2
MONITORS = ["DP7HGJ4", "6P7HGJ4"]    # DP-1, DP-2 (by DDC serial)
STATE = os.path.expanduser("~/.cache/hexane-nightlight/last")


def _julian(ts):        # unix seconds -> julian day
    return ts / 86400.0 + 2440587.5


def _unix(j):           # julian day -> unix seconds
    return (j - 2440587.5) * 86400.0


def sun_times(day, lat, lon):
    """(sunrise, sunset) as local tz-aware datetimes for a local date, via the
    NOAA sunrise equation. Longitude east-positive."""
    noon_utc = datetime(day.year, day.month, day.day, 12, tzinfo=timezone.utc)
    n = _julian(noon_utc.timestamp()) - 2451545.0 + 0.0008
    Jstar = n + lon / 360.0                       # east-positive longitude
    M = (357.5291 + 0.98560028 * Jstar) % 360.0
    Mr = math.radians(M)
    C = 1.9148*math.sin(Mr) + 0.0200*math.sin(2*Mr) + 0.0003*math.sin(3*Mr)
    lam = (M + C + 180.0 + 102.9372) % 360.0
    lamr = math.radians(lam)
    Jtransit = 2451545.0 + Jstar + 0.0053*math.sin(Mr) - 0.0069*math.sin(2*lamr)
    sin_decl = math.sin(lamr) * math.sin(math.radians(23.44))
    decl = math.asin(sin_decl)
    latr = math.radians(lat)
    cos_w = ((math.sin(math.radians(-0.833)) - math.sin(latr)*sin_decl)
             / (math.cos(latr)*math.cos(decl)))
    cos_w = max(-1.0, min(1.0, cos_w))            # clamp: polar day/night
    w = math.degrees(math.acos(cos_w))
    sunrise = datetime.fromtimestamp(_unix(Jtransit - w/360.0)).astimezone()
    sunset = datetime.fromtimestamp(_unix(Jtransit + w/360.0)).astimezone()
    return sunrise, sunset


def _round_step(x):
    return int(round(x / STEP) * STEP)


def target(now, sunrise, sunset):
    """Brightness % for `now`, rounded to STEP. Ramps DAY<->NIGHT over RAMP_MIN,
    evening ramp starting at sunset, morning ramp starting at sunrise."""
    ramp = RAMP_MIN * 60
    if sunrise <= now < sunrise + _td(ramp):            # morning ramp up
        frac = (now - sunrise).total_seconds() / ramp
        return _round_step(NIGHT + (DAY - NIGHT) * frac)
    if sunrise + _td(ramp) <= now < sunset:             # day
        return DAY
    if sunset <= now < sunset + _td(ramp):              # evening ramp down
        frac = (now - sunset).total_seconds() / ramp
        return _round_step(DAY + (NIGHT - DAY) * frac)
    return NIGHT                                         # night (incl. pre-dawn)


def _td(seconds):
    from datetime import timedelta
    return timedelta(seconds=seconds)
```

- [ ] **Step 4: Run tests, verify they pass**

Run: `python3 tests/test_hexane_nightlight.py -v`
Expected: PASS (8 tests). If `test_denver_early_august_plausible` fails on the hour bounds, the longitude sign is wrong — flip `Jstar = n - lon/360.0` and re-run.

- [ ] **Step 5: Commit**

```bash
cd ~/.dotfiles
git add bin/hexane-nightlight tests/test_hexane_nightlight.py
git -c core.hooksPath=/dev/null commit -m "feat(nightlight): pure sun_times + target core with tests"
```

---

### Task 2: Effects + CLI

**Files:**
- Modify: `bin/hexane-nightlight` (append `apply`, `_read/_write_state`, `main`, dispatch)

**Interfaces:**
- Consumes: `sun_times`, `target`, constants from Task 1.
- Produces: CLI — no args (apply), `--check`, `--simulate "<ISO>"`, `--dry-run`.

- [ ] **Step 1: Add effects + CLI (append to `bin/hexane-nightlight`)**

```python
def _read_state():
    try:
        return int(open(STATE).read().strip())
    except (OSError, ValueError):
        return None


def _write_state(v):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    with open(STATE, "w") as f:
        f.write(str(v))


def _set_monitor(sn, value):
    subprocess.run(["ddcutil", "--sn", sn, "setvcp", "0x10", str(value)],
                   check=True, capture_output=True, timeout=20)


def _get_monitor(sn):
    out = subprocess.run(["ddcutil", "--sn", sn, "getvcp", "0x10"],
                         check=True, capture_output=True, timeout=20, text=True).stdout
    # "...current value =   84, max value =  100"
    for tok in out.replace(",", " ").split():
        if tok.isdigit():
            return int(tok)
    return None


def apply(t, dry=False):
    if _read_state() == t:
        return False
    changed = False
    for sn in MONITORS:
        try:
            if dry:
                print(f"[dry-run] would set {sn} -> {t}%")
            else:
                _set_monitor(sn, t)
            changed = True
        except Exception as e:                      # noqa: BLE001 - one flaky panel must not break the other
            print(f"warn: {sn}: {e}", file=sys.stderr)
    if changed and not dry:
        _write_state(t)
    return changed


def main(argv):
    now = datetime.now().astimezone()
    sr, ss = sun_times(now.date(), LAT, LON)
    if argv and argv[0] == "--check":
        print(f"now     {now:%Y-%m-%d %H:%M %Z}")
        print(f"sunrise {sr:%H:%M}   sunset {ss:%H:%M}")
        print(f"target  {target(now, sr, ss)}%")
        for sn in MONITORS:
            try:
                print(f"  {sn}: actual {_get_monitor(sn)}%")
            except Exception as e:                  # noqa: BLE001
                print(f"  {sn}: ERR {e}")
        return 0
    if argv and argv[0] == "--simulate":
        when = datetime.fromisoformat(argv[1]).astimezone()
        s_sr, s_ss = sun_times(when.date(), LAT, LON)
        print(f"{when:%Y-%m-%d %H:%M}  sunrise {s_sr:%H:%M} sunset {s_ss:%H:%M}"
              f"  -> target {target(when, s_sr, s_ss)}%")
        return 0
    apply(target(now, sr, ss), dry=(argv and argv[0] == "--dry-run"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```

- [ ] **Step 2: Make executable + smoke-test (no writes)**

```bash
chmod +x ~/.dotfiles/bin/hexane-nightlight
python3 ~/.dotfiles/bin/hexane-nightlight --check
# ramp ladder: every step should drop ~2%
for m in 00 09 18 27 36 45; do python3 ~/.dotfiles/bin/hexane-nightlight --simulate "2026-08-04 20:$m"; done
```
Expected: `--check` prints plausible sun times + both panels' actual %; the simulate ladder descends 100→~80 in even (2%) steps.

- [ ] **Step 3: Re-run unit tests (import still clean, no side effects)**

Run: `python3 tests/test_hexane_nightlight.py -v`
Expected: PASS (import must not trigger `apply`).

- [ ] **Step 4: Commit**

```bash
cd ~/.dotfiles
git add bin/hexane-nightlight
git -c core.hooksPath=/dev/null commit -m "feat(nightlight): apply + CLI (--check/--simulate/--dry-run)"
```

---

### Task 3: systemd user timer + dotbot links + enable

**Files:**
- Create: `systemd/hexane-nightlight.service`, `systemd/hexane-nightlight.timer`
- Modify: `default.conf.yaml` (3 link lines)

- [ ] **Step 1: Write the units**

```ini
# systemd/hexane-nightlight.service
[Unit]
Description=Sun-tracked gentle backlight dim for the Dell U3225QEs

[Service]
Type=oneshot
ExecStart=%h/.local/bin/hexane-nightlight
```

```ini
# systemd/hexane-nightlight.timer
[Unit]
Description=Run hexane-nightlight every 2 minutes

[Timer]
OnCalendar=*:0/2
Persistent=true

[Install]
WantedBy=timers.target
```

- [ ] **Step 2: Add dotbot links** under the `link:` section of `default.conf.yaml`:

```yaml
    ~/.local/bin/hexane-nightlight: bin/hexane-nightlight # sun-tracked night backlight dim (ddcutil)
    ~/.config/systemd/user/hexane-nightlight.service: systemd/hexane-nightlight.service
    ~/.config/systemd/user/hexane-nightlight.timer: systemd/hexane-nightlight.timer
```

- [ ] **Step 3: Link + enable**

```bash
cd ~/.dotfiles && ./install 2>&1 | tail -20   # dotbot creates the symlinks
systemctl --user daemon-reload
systemctl --user enable --now hexane-nightlight.timer
systemctl --user list-timers hexane-nightlight.timer --no-pager
```
Expected: timer listed with a NEXT time ≤2 min out; `~/.local/bin/hexane-nightlight` and both unit symlinks exist.

- [ ] **Step 4: Verify one real cycle**

```bash
systemctl --user start hexane-nightlight.service
journalctl --user -u hexane-nightlight.service -n 20 --no-pager
~/.local/bin/hexane-nightlight --check
```
Expected: service succeeds; `--check` shows both panels at the current target; state file `~/.cache/hexane-nightlight/last` matches.

- [ ] **Step 5: Commit**

```bash
cd ~/.dotfiles
git add systemd/hexane-nightlight.service systemd/hexane-nightlight.timer default.conf.yaml
git -c core.hooksPath=/dev/null commit -m "feat(nightlight): systemd user timer + dotbot links"
```

---

## Self-Review

- **Spec coverage:** levels/curve (Task 1 `target`), sun tracking (Task 1 `sun_times`), 2% steps (Task 1 rounding + test), both monitors by serial (Task 2 `MONITORS`), write-on-change/state (Task 2 `apply`), CLI verify surface (Task 2), user timer + no-sudo + links (Task 3), Auto-Brightness prerequisite (already confirmed off). Covered.
- **Placeholders:** none — every step has real code/commands.
- **Type consistency:** `sun_times`/`target`/`apply` signatures identical across tasks; `STEP`, `MONITORS`, `STATE`, `target()` referenced consistently.
- **Note:** `_td` is referenced in `target()` and defined in Task 1; if a linter reorders, keep it module-level.
```

**One risk flagged for execution:** the NOAA longitude sign — the Denver plausibility test (Task 1 Step 4) is the guard; if sunrise/sunset land at wrong hours, flip the `Jstar` longitude sign and re-run before proceeding.
