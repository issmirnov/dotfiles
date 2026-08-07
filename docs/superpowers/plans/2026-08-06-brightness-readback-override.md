# Brightness read-back + manual-override coordination — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Quickshell bar's brightness slider follow `hexane-nightlight`'s ramps live, and make a manual bar change pause auto-dim (re-arming at the next sunrise) with a visible toggle — all event-driven, no polling.

**Architecture:** Two small files in `~/.cache/hexane-nightlight/` are the contract: `last` (nightlight's applied values, the bar watches it) and a new `override` marker (the bar writes it, nightlight honors it). The bar gains an `AutoDim` singleton (owns the marker) and an `AutoDimToggle` chip; `Brightness.qml` follows `last` via a `FileView` and writes the marker on any manual change. `hexane-nightlight` skips its schedule while a valid marker is present and deletes it after the next sunrise.

**Tech Stack:** Python 3 (dep-free, stdlib) for `hexane-nightlight` + `unittest`; Quickshell 0.3.0 (Qt6/QML) flat config in `~/.dotfiles/quickshell/`.

## Global Constraints

- **Dotfiles git hygiene:** `~/.dotfiles` is `master` with concurrent agent sessions. **Stage only the explicit files each step names** — never `git add -A`/`-am`. The KB lives in the separate `~/docs` repo.
- **`rm -f`** for any removal (house rule; bare `rm` prompts).
- **qs minimal PATH** is `/usr/local/bin:/usr/bin` — `~/…/dotbin` and `~/.local/bin` are absent. Any script qs spawns must use **absolute paths** (nightlight → `/home/vania/.dotfiles/bin/hexane-nightlight`).
- **QML flat auto-import:** uppercase-named sibling `.qml` files auto-import; **no `qmldir`, no per-file sibling imports**. Singletons need `pragma Singleton` + a `Singleton {}` root (see `Theme.qml`).
- **No Rectangle `border`** on the transparent bar window (QTBUG-137166 blanks the whole bar).
- **QML dev loop (every QML change):** relaunch `pkill -x qs; hyprctl dispatch 'hl.dsp.exec_cmd("qs >/tmp/qs.log 2>&1")'`, then `grep -iE 'error|warning|invalid|not a type' /tmp/qs.log` (expect `Configuration Loaded`), then screenshot. Hot-reload is NOT trustworthy.
- **Monitor serials:** `DP7HGJ4` = DP-1 (the panel the bar reads), `6P7HGJ4` = DP-2. VCP `0x10` = brightness.
- **Marker `value` is informational** — nightlight ignores it and keys off `since` only.

---

## File Structure

- `bin/hexane-nightlight` (modify) — add override read/classify/clear + `run_tick`; skip-when-held, re-arm-when-expired; single-`write()` `_write_state`.
- `tests/test_hexane_nightlight.py` (modify) — add `OverrideState` + `RunTick` test classes.
- `quickshell/AutoDim.qml` (create) — singleton; owns the `override` marker (FileView watch + Process write/delete + nightlight kick); exposes `active`, `pause(v)`, `arm()`.
- `quickshell/Brightness.qml` (modify) — FileView on `last` → follow when armed; `set()` marks override; reconcile `getvcp` on re-arm.
- `quickshell/AutoDimToggle.qml` (create) — chip mirroring `IdleToggle`; `auto`/`held` from `AutoDim.active`; click pause/arm.
- `quickshell/Bar.qml` (modify) — insert `AutoDimToggle {}` after `Brightness {}`.
- `~/docs/docs/systems/hexane/ddc-brightness-nightlight.md` + `hyprland-bars.md` (modify) — document the protocol.

---

## Task 1: nightlight override honor / daily re-arm (TDD)

**Files:**
- Modify: `~/.dotfiles/bin/hexane-nightlight`
- Test: `~/.dotfiles/tests/test_hexane_nightlight.py`

**Interfaces:**
- Consumes: existing `sun_times(date, lat, lon)`, `target(now, sr, ss)`, `apply(t, dry)`, `_read_state()`, `_write_state(state)`, module consts `LAT`, `LON`, `STATE`.
- Produces:
  - `OVERRIDE` (str path) `= ~/.cache/hexane-nightlight/override`
  - `_read_override() -> dict|None`
  - `_clear_override() -> None`
  - `override_state(ovr, now, lat=LAT, lon=LON) -> str` in `{"absent","held","expired"}`
  - `run_tick(now, sr, ss) -> str` in `{"held","rearm","apply"}` (the timer-path decision + side effects)

- [ ] **Step 1: Write failing tests for `override_state`**

Add to `tests/test_hexane_nightlight.py` (after the `Target` class):

```python
class OverrideState(unittest.TestCase):
    denver = ZoneInfo("America/Denver")

    def _at(self, y, mo, d, h, mi):
        return datetime(y, mo, d, h, mi, tzinfo=self.denver)

    def test_absent_when_none(self):
        self.assertEqual(nl.override_state(None, self._at(2026, 8, 6, 22, 0)), "absent")

    def test_unparseable_since_is_absent(self):
        self.assertEqual(nl.override_state({"since": "nonsense"}, self._at(2026, 8, 6, 22, 0)), "absent")

    def test_evening_override_is_held_same_night(self):
        ovr = {"since": self._at(2026, 8, 6, 20, 14).isoformat()}
        self.assertEqual(nl.override_state(ovr, self._at(2026, 8, 6, 22, 0)), "held")

    def test_evening_override_held_through_pre_dawn(self):
        ovr = {"since": self._at(2026, 8, 6, 20, 14).isoformat()}
        self.assertEqual(nl.override_state(ovr, self._at(2026, 8, 7, 3, 0)), "held")

    def test_expires_after_next_sunrise(self):
        ovr = {"since": self._at(2026, 8, 6, 20, 14).isoformat()}
        self.assertEqual(nl.override_state(ovr, self._at(2026, 8, 7, 8, 0)), "expired")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `python ~/.dotfiles/tests/test_hexane_nightlight.py OverrideState -v`
Expected: FAIL with `AttributeError: module 'hexane_nightlight' has no attribute 'override_state'`.

- [ ] **Step 3: Implement the override helpers**

In `bin/hexane-nightlight`, add `timedelta` is already imported (`from datetime import datetime, timezone, timedelta`). Add the `OVERRIDE` const next to `STATE`:

```python
STATE = os.path.expanduser("~/.cache/hexane-nightlight/last")
OVERRIDE = os.path.expanduser("~/.cache/hexane-nightlight/override")
```

Add these functions after `_write_state`:

```python
def _read_override():
    """The manual-override marker dict, or None if absent/corrupt."""
    try:
        with open(OVERRIDE) as f:
            d = json.load(f)
        return d if isinstance(d, dict) and "since" in d else None
    except (OSError, ValueError):
        return None


def _clear_override():
    try:
        os.remove(OVERRIDE)
    except OSError:
        pass


def _most_recent_sunrise(now, lat, lon):
    """Sunrise bounding the current 'day': today's if now is past it, else yesterday's."""
    sr_today, _ = sun_times(now.date(), lat, lon)
    if now >= sr_today:
        return sr_today
    sr_yest, _ = sun_times(now.date() - timedelta(days=1), lat, lon)
    return sr_yest


def override_state(ovr, now, lat=LAT, lon=LON):
    """'absent' | 'held' | 'expired'. A manual override is honored until the
    first sunrise after it was set (daily re-arm)."""
    if not ovr:
        return "absent"
    try:
        since = datetime.fromisoformat(ovr["since"])
    except (KeyError, TypeError, ValueError):
        return "absent"
    if since.tzinfo is None:
        since = since.astimezone()
    return "expired" if since < _most_recent_sunrise(now, lat, lon) else "held"
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `python ~/.dotfiles/tests/test_hexane_nightlight.py OverrideState -v`
Expected: PASS (5 tests).

- [ ] **Step 5: Write failing tests for `run_tick`**

Add this class (it reuses the `Apply` pattern: temp `STATE` + `OVERRIDE`, mocked `_set_monitor`):

```python
class RunTick(unittest.TestCase):
    denver = ZoneInfo("America/Denver")

    def setUp(self):
        self._tmp = tempfile.mkdtemp()
        self._st, self._ov = nl.STATE, nl.OVERRIDE
        nl.STATE = os.path.join(self._tmp, "last")
        nl.OVERRIDE = os.path.join(self._tmp, "override")
        self.sr = datetime(2026, 8, 6, 6, 2, tzinfo=self.denver)
        self.ss = datetime(2026, 8, 6, 20, 9, tzinfo=self.denver)

    def tearDown(self):
        nl.STATE, nl.OVERRIDE = self._st, self._ov
        shutil.rmtree(self._tmp, ignore_errors=True)

    def _write_override(self, since_dt):
        with open(nl.OVERRIDE, "w") as f:
            f.write('{"since": "%s", "value": 79}' % since_dt.isoformat())

    def test_absent_applies_schedule(self):
        now = datetime(2026, 8, 6, 20, 30, tzinfo=self.denver)
        with mock.patch.object(nl, "_set_monitor") as m:
            self.assertEqual(nl.run_tick(now, self.sr, self.ss), "apply")
            self.assertEqual(m.call_count, 2)          # both panels written

    def test_held_skips_and_blanks_cache(self):
        nl._write_state({"DP7HGJ4": 98, "6P7HGJ4": 98})
        self._write_override(datetime(2026, 8, 6, 20, 14, tzinfo=self.denver))
        now = datetime(2026, 8, 6, 22, 0, tzinfo=self.denver)
        with mock.patch.object(nl, "_set_monitor") as m:
            self.assertEqual(nl.run_tick(now, self.sr, self.ss), "held")
            self.assertEqual(m.call_count, 0)          # panels untouched
        self.assertEqual(nl._read_state(), {})         # cache blanked → re-arm force-applies

    def test_expired_clears_marker_and_applies(self):
        self._write_override(datetime(2026, 8, 6, 20, 14, tzinfo=self.denver))
        now = datetime(2026, 8, 7, 8, 0, tzinfo=self.denver)
        sr2 = datetime(2026, 8, 7, 6, 3, tzinfo=self.denver)
        ss2 = datetime(2026, 8, 7, 20, 8, tzinfo=self.denver)
        with mock.patch.object(nl, "_set_monitor") as m:
            self.assertEqual(nl.run_tick(now, sr2, ss2), "rearm")
            self.assertTrue(m.call_count >= 1)         # schedule applied
        self.assertIsNone(nl._read_override())         # marker deleted
```

- [ ] **Step 6: Run to verify they fail**

Run: `python ~/.dotfiles/tests/test_hexane_nightlight.py RunTick -v`
Expected: FAIL with `AttributeError: ... has no attribute 'run_tick'`.

- [ ] **Step 7: Implement `run_tick` + single-`write()` `_write_state`, and wire `main`**

Replace `_write_state` body so the bar never reads a chunked/torn file (single `write()`):

```python
def _write_state(state):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    with open(STATE, "w") as f:
        f.write(json.dumps(state))
```

Add `run_tick` after `apply`:

```python
def run_tick(now, sr, ss):
    """Timer-path decision. Honor a manual override (skip + blank the cache so a
    later re-arm force-applies); re-arm an expired one; otherwise apply schedule.
    Returns 'held' | 'rearm' | 'apply'."""
    st = override_state(_read_override(), now)
    if st == "held":
        if _read_state():
            _write_state({})
        return "held"
    if st == "expired":
        _clear_override()
    apply(target(now, sr, ss))
    return "rearm" if st == "expired" else "apply"
```

In `main`, replace the no-arg timer path:

```python
    if not argv:                                    # the timer path
        run_tick(now, sr, ss)
        return 0
```

And extend `--check` to report the override (insert after the `target` line, before the per-monitor loop):

```python
        ovr = _read_override()
        print(f"override {override_state(ovr, now)}"
              + (f"  since {ovr['since']}" if ovr else ""))
```

- [ ] **Step 8: Run the full nightlight suite**

Run: `python ~/.dotfiles/tests/test_hexane_nightlight.py -v`
Expected: PASS — all classes (`SunTimes`, `Target`, `Apply`, `OverrideState`, `RunTick`). The existing `Apply`/`Target` tests must stay green (no-override path unchanged).

- [ ] **Step 9: Smoke-test the CLI (no hardware writes)**

Run: `~/.dotfiles/bin/hexane-nightlight --check`
Expected: prints `override absent` (no marker yet) plus the usual now/sunrise/target/actual lines.

- [ ] **Step 10: Commit**

```bash
cd /home/vania/.dotfiles && git add bin/hexane-nightlight tests/test_hexane_nightlight.py && git commit -m "feat(nightlight): honor manual brightness override, re-arm at sunrise

Adds an override marker (~/.cache/hexane-nightlight/override) the bar can drop to
pause auto-dim; nightlight skips its schedule while held, blanks its cache so a
later re-arm force-applies, and clears the marker after the next sunrise. State
file now written in a single write() so the bar never reads a torn file.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `AutoDim` singleton (the bar's override owner)

**Files:**
- Create: `~/.dotfiles/quickshell/AutoDim.qml`

**Interfaces:**
- Produces (used by Tasks 3 & 4): singleton `AutoDim` with `property bool active`, `function pause(v)`, `function arm()`, `readonly property string path`.
- Consumes: Task 1's `override` marker file + nightlight absolute path.

- [ ] **Step 1: Create `AutoDim.qml`**

```qml
pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Single source of truth for the manual brightness-override marker shared with
// hexane-nightlight (~/.cache/hexane-nightlight/override). A present marker means
// the user is in control (HELD); absent means auto-dim is armed. nightlight owns
// expiry (it deletes the marker after the next sunrise), so the bar keys purely
// off the marker's PRESENCE.
Singleton {
    id: root

    readonly property string path: "/home/vania/.cache/hexane-nightlight/override"
    readonly property string nightlight: "/home/vania/.dotfiles/bin/hexane-nightlight"
    property bool active: false      // a valid override marker is present (HELD)

    // Pause auto-dim: write the marker. `v` is informational (nightlight ignores it).
    function pause(v) {
        root.active = true;          // optimistic; the FileView confirms/corrects
        markProc.command = ["sh", "-c",
            'd=$(dirname "$1"); mkdir -p "$d"; ' +
            'printf \'{"since":"%s","value":%s}\' "$(date -Iseconds)" "$2" > "$1"',
            "sh", root.path, String(Math.round(v))];
        markProc.running = true;
    }

    // Re-arm auto-dim: drop the marker, then kick nightlight once (absolute path —
    // qs's PATH excludes dotbin) so it takes over immediately instead of ≤2 min later.
    function arm() {
        root.active = false;         // optimistic
        armProc.running = true;
    }

    Process { id: markProc }
    Process {
        id: armProc
        command: ["sh", "-c", "rm -f '" + root.path + "'; '" + root.nightlight + "' >/dev/null 2>&1"]
    }

    // Watch the marker so external changes (nightlight's daily re-arm delete) flip `active`.
    FileView {
        id: view
        path: root.path
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.active = (("" + view.text()).indexOf("since") !== -1)
        onLoadFailed: root.active = false
    }
}
```

> NOTE (verify in the dev loop): confirm `view.text()` is the correct accessor and that `onLoadFailed` fires on a missing file in Quickshell 0.3.0. If the log shows `text is not a function`, switch to the property form `view.text`. If deletion doesn't flip `active`, add the directory to the watch or re-derive in `onFileChanged`.

- [ ] **Step 2: Relaunch qs and check the log**

```bash
pkill -x qs; hyprctl dispatch 'hl.dsp.exec_cmd("qs >/tmp/qs.log 2>&1")'
sleep 1; grep -iE 'error|warning|invalid|not a type|autodim' /tmp/qs.log | head
```
Expected: `Configuration Loaded`, no `AutoDim`/QML errors. (The singleton isn't visible yet — this only proves it parses.)

- [ ] **Step 3: Commit**

```bash
cd /home/vania/.dotfiles && git add quickshell/AutoDim.qml && git commit -m "feat(quickshell): AutoDim singleton owning the nightlight override marker

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: `Brightness.qml` — follow `last` live + mark override

**Files:**
- Modify: `~/.dotfiles/quickshell/Brightness.qml`

**Interfaces:**
- Consumes: `AutoDim.active`, `AutoDim.pause(v)` (Task 2); nightlight's `last` file.
- Produces: nothing new for later tasks.

- [ ] **Step 1: Add `_follow` and the `last` FileView**

Add a `_lastSeeded` property beside the other properties (after `property bool dragging: false`):

```qml
    property bool _lastSeeded: false   // ignore the FileView's initial load; startup getvcp is the seed
```

Add `_follow` next to `set` (after the `set` function):

```qml
    // adopt an external (nightlight) value without writing DDC or marking an override
    function _follow(v) {
        bri.value = Math.max(0, Math.min(100, v));
        bri.applied = bri.value;
    }
```

Add a FileView watching `last` (place it after the `readProc` Process block, before `Component.onCompleted`):

```qml
    // follow nightlight's ramps live: when ARMED and not dragging, adopt the value it
    // wrote to DP-1. Event-driven (inotify) — no polling. HELD → ignore (user's value wins).
    FileView {
        id: lastFile
        path: "/home/vania/.cache/hexane-nightlight/last"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            if (!bri._lastSeeded) { bri._lastSeeded = true; return; }
            if (AutoDim.active || bri.dragging) return;
            const m = ("" + lastFile.text()).match(/"DP7HGJ4"\s*:\s*(\d+)/);
            if (m) bri._follow(parseInt(m[1]));
        }
    }
```

- [ ] **Step 2: Mark an override on every manual change**

Edit the `set` function to pause auto-dim (the only manual entry point — scroll + slider drag both route through `set`):

```qml
    function set(v) {
        bri.value = Math.max(0, Math.min(100, Math.round(v)));
        AutoDim.pause(bri.value);      // manual change → hold auto-dim off
        bri._kick();
    }
```

- [ ] **Step 3: Reconcile to hardware truth on re-arm**

Add a `Connections` block (anywhere inside the root `Rectangle`, e.g. right after `Component.onCompleted`):

```qml
    // when auto-dim re-arms (marker cleared by the toggle or nightlight), re-read the
    // panel so the slider snaps to whatever nightlight just applied — race-free.
    Connections {
        target: AutoDim
        function onActiveChanged() {
            if (!AutoDim.active) readProc.running = true;
        }
    }
```

- [ ] **Step 4: Relaunch and verify clean parse**

```bash
pkill -x qs; hyprctl dispatch 'hl.dsp.exec_cmd("qs >/tmp/qs.log 2>&1")'
sleep 1; grep -iE 'error|warning|invalid|not a type' /tmp/qs.log | head
```
Expected: `Configuration Loaded`, no errors. The `BRI n%` chip renders (screenshot the right cluster to confirm).

- [ ] **Step 5: Commit**

```bash
cd /home/vania/.dotfiles && git add quickshell/Brightness.qml && git commit -m "feat(quickshell): brightness follows nightlight live + marks manual overrides

FileView on the nightlight last-state file drives the slider on its ramps (armed,
not dragging); any manual set writes the override marker via AutoDim; re-arm
triggers a getvcp reconcile. No polling.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: `AutoDimToggle` chip + wire into the bar

**Files:**
- Create: `~/.dotfiles/quickshell/AutoDimToggle.qml`
- Modify: `~/.dotfiles/quickshell/Bar.qml`

**Interfaces:**
- Consumes: `AutoDim.active`, `AutoDim.arm()`, `AutoDim.pause(v)` (Task 2); `Theme.*`.

- [ ] **Step 1: Create `AutoDimToggle.qml`** (mirrors `IdleToggle.qml`)

```qml
import QtQuick

// Click to pause / re-arm hexane-nightlight's auto-dim. State is the shared
// AutoDim singleton (the override marker). Mirrors IdleToggle's shape.
Rectangle {
    id: root

    height: Theme.chipHeight
    width: label.width + 18
    radius: Theme.chipRadius
    color: AutoDim.active ? Theme.briCol : Theme.surface
    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
        id: label
        anchors.centerIn: parent
        text: AutoDim.active ? "held" : "auto"
        color: AutoDim.active ? Theme.chipText : Theme.subtext
        font.pixelSize: Theme.fontSize
        font.bold: AutoDim.active
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: AutoDim.active ? AutoDim.arm() : AutoDim.pause(-1)
    }
}
```

- [ ] **Step 2: Insert the chip into `Bar.qml`**

In the right `Row`, add `AutoDimToggle {}` immediately after `Brightness {}`:

```qml
            Brightness {}
            AutoDimToggle {}
            Audio {}
```

- [ ] **Step 3: Relaunch, check log, screenshot**

```bash
pkill -x qs; hyprctl dispatch 'hl.dsp.exec_cmd("qs >/tmp/qs.log 2>&1")'
sleep 1; grep -iE 'error|warning|invalid|not a type' /tmp/qs.log | head
grim -o DP-1 -t png /tmp/b.png && magick /tmp/b.png -crop 1400x60+2440+2 +repage /tmp/c.png
```
Then view `/tmp/c.png`. Expected: an `auto` chip (subtext-on-surface) sits between `BRI` and the audio chip. (Marker absent → armed → `auto`.)

- [ ] **Step 4: Commit**

```bash
cd /home/vania/.dotfiles && git add quickshell/AutoDimToggle.qml quickshell/Bar.qml && git commit -m "feat(quickshell): auto-dim toggle chip beside Brightness

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: End-to-end live verification

**Files:** none (observation only; fix-and-recommit into the relevant task's file if a defect surfaces).

- [ ] **Step 1: Manual override via the slider writes the marker + flips the chip**

Open the Brightness popup and drag the slider (hypr-cua): `screenshot(output="DP-1")` → `click` the `BRI` chip → `drag` the slider handle. Then:
```bash
cat ~/.cache/hexane-nightlight/override; echo
~/.dotfiles/bin/hexane-nightlight --check | grep override
```
Expected: marker JSON with a `since`; `--check` prints `override held`. Screenshot: the toggle now reads `held` (highlighted `briCol`).

- [ ] **Step 2: nightlight honors the override (no fight)**

```bash
before=$(ddcutil --sn DP7HGJ4 getvcp 0x10 | grep -o 'current value = *[0-9]*')
~/.dotfiles/bin/hexane-nightlight          # timer path; should NOT touch panels
after=$(ddcutil --sn DP7HGJ4 getvcp 0x10 | grep -o 'current value = *[0-9]*')
echo "before:$before after:$after"; cat ~/.cache/hexane-nightlight/last; echo
```
Expected: `before == after` (brightness unchanged), and `last` is `{}` (cache blanked while held).

- [ ] **Step 3: Toggle re-arm clears the marker, chip returns to `auto`, nightlight takes over**

Click the toggle (hypr-cua). Then:
```bash
ls ~/.cache/hexane-nightlight/override 2>&1        # expect: No such file
~/.dotfiles/bin/hexane-nightlight --check | grep override   # expect: override absent
```
Expected: marker gone; chip reads `auto`; brightness moves to the current schedule target (arm() kicked nightlight), and the slider snaps to it (reconcile read + `last` follow).

- [ ] **Step 4: Live-follow a nightlight change while armed**

With the popup open and armed, force a nightlight write and confirm the slider follows:
```bash
rm -f ~/.cache/hexane-nightlight/last          # force a fresh write next run
~/.dotfiles/bin/hexane-nightlight              # applies target, writes last
ddcutil --sn DP7HGJ4 getvcp 0x10 | grep -o 'current value = *[0-9]*'
```
Expected: the `BRI n%` chip/slider update to the new value within a moment (FileView on `last`), with no popup interaction.

- [ ] **Step 5: Expiry boundary (simulate, no waiting for dawn)**

Confirm the schedule/expiry math end-to-end without hardware side effects:
```bash
~/.dotfiles/bin/hexane-nightlight --simulate "2026-08-07 06:30"   # target near morning ramp
python ~/.dotfiles/tests/test_hexane_nightlight.py -v             # full suite green
```
Expected: `--simulate` prints a plausible target; unit suite passes (the expiry/`run_tick` cases already assert the sunrise boundary and clear-on-expire behavior).

- [ ] **Step 6: Leave the system in a clean state**

```bash
rm -f ~/.cache/hexane-nightlight/override      # ensure armed
~/.dotfiles/bin/hexane-nightlight              # apply the real current schedule
~/.dotfiles/bin/hexane-nightlight --check
```
Expected: `override absent`, actuals match target.

---

## Task 6: Update the knowledge base

**Files:**
- Modify: `~/docs/docs/systems/hexane/ddc-brightness-nightlight.md`
- Modify: `~/docs/docs/systems/hexane/hyprland-bars.md`

- [ ] **Step 1: Document the coordination protocol in the nightlight doc**

Append a section to `ddc-brightness-nightlight.md`:

```markdown
## Bar ↔ nightlight coordination (shipped 2026-08-06)

The Quickshell **Brightness** module and nightlight now coordinate through two
files in `~/.cache/hexane-nightlight/`:

- `last` — nightlight's last-applied `{serial: pct}` (written in a single
  `write()` so the bar never reads a torn file). The bar **FileView-watches** it
  and the slider follows nightlight's ramps live (event-driven, no polling).
- `override` — a manual-override marker `{"since": ISO, "value": pct}` the bar
  drops whenever you change brightness from the bar (drag/scroll) or click the
  **auto-dim toggle** to pause. While a valid marker is present nightlight **skips
  its schedule** (no fight) and blanks its `last` cache so a later re-arm
  force-applies. nightlight **deletes** the marker after the **next sunrise**
  (daily re-arm); the toggle can also clear it on demand (which kicks nightlight
  once for instant takeover). `value` is informational — nightlight keys off
  `since`. `hexane-nightlight --check` prints `override held|expired|absent`.
```

- [ ] **Step 2: Note the module behavior in the bars doc**

Add to the Brightness/module notes in `hyprland-bars.md` (near the existing bar module descriptions):

```markdown
- **Brightness** follows `hexane-nightlight` live via a `FileView` on
  `~/.cache/hexane-nightlight/last` (no polling); a manual slider/scroll change
  writes an `override` marker (via the **AutoDim** singleton) that pauses auto-dim
  until the next sunrise. The **AutoDimToggle** chip (beside Brightness) shows
  `auto`/`held` and pauses/re-arms on click. See `ddc-brightness-nightlight.md`.
```

- [ ] **Step 3: Commit the KB (separate repo)**

```bash
cd /home/vania/docs && git add docs/systems/hexane/ddc-brightness-nightlight.md docs/systems/hexane/hyprland-bars.md && git commit -m "docs(hexane): bar <-> nightlight brightness coordination protocol

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- Event-driven read-back (no poll) → Task 3 (FileView on `last`). ✓
- Manual override wins / stops the fight → Task 1 (`run_tick` held-skip) + Task 3 (`set`→`pause`). ✓
- Daily re-arm at sunrise → Task 1 (`override_state` expiry + `run_tick` clear+apply). ✓
- Visible bar toggle → Task 4 (`AutoDimToggle`). ✓
- Blank-cache-so-re-arm-force-applies → Task 1 (`run_tick` held branch) + `RunTick.test_held_skips_and_blanks_cache`. ✓
- Re-arm race-free catch-up → Task 3 (`Connections onActiveChanged` reconcile). ✓
- Ignore initial `last` load → Task 3 (`_lastSeeded`). ✓
- Torn-read tolerance → single-`write()` `_write_state` (Task 1) + regex parse that simply no-ops on no match (Tasks 2/3). ✓
- Corrupt/absent marker → absent/armed → Task 1 (`_read_override`/`override_state` guards). ✓

**Placeholder scan:** none — every code step carries full source; the two `NOTE`s are explicit dev-loop verifications, not deferred work.

**Type consistency:** `AutoDim.active`/`pause(v)`/`arm()`/`path` defined in Task 2 and consumed with those exact names in Tasks 3–4. `run_tick`/`override_state`/`_read_override`/`_clear_override` defined and called consistently in Task 1. `_follow`/`_lastSeeded` local to Task 3. Marker shape `{"since","value"}` identical across Task 1 (reader), Task 2 (writer), Task 5 (inspection).

**Deviation from spec (intentional):** the spec said "atomic tmp+rename"; the plan uses single-`write()` in-place instead, because an atomic rename swaps the inode and can drop a `FileView` inotify watch. Same torn-read protection for these tiny files, without risking the watch. Bar treats marker **presence** as HELD (nightlight owns expiry), so the bar needs no sun math.
