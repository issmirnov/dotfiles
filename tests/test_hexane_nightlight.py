import importlib.util, importlib.machinery, os, pathlib, shutil, tempfile, unittest
from datetime import datetime, date, timedelta
from unittest import mock
from zoneinfo import ZoneInfo

_p = pathlib.Path(__file__).resolve().parents[1] / "bin" / "hexane-nightlight"
# bin/hexane-nightlight has no .py extension, so give importlib an explicit loader.
_loader = importlib.machinery.SourceFileLoader("hexane_nightlight", str(_p))
_spec = importlib.util.spec_from_loader("hexane_nightlight", _loader)
nl = importlib.util.module_from_spec(_spec)
_loader.exec_module(nl)


class SunTimes(unittest.TestCase):
    def test_equator_equinox_is_symmetric_around_noon(self):
        # At the equator on an equinox, day ~12h.
        sr, ss = nl.sun_times(date(2026, 3, 20), 0.0, 0.0)
        day_len = (ss - sr).total_seconds() / 3600
        self.assertAlmostEqual(day_len, 12.0, delta=0.3)

    def test_denver_early_august_plausible(self):
        # Denver, 2026-08-04: sunrise ~06:02, sunset ~20:11 MDT. Convert to Denver
        # explicitly so this holds regardless of the test runner's local tz.
        denver = ZoneInfo("America/Denver")
        sr, ss = nl.sun_times(date(2026, 8, 4), nl.LAT, nl.LON)
        sr, ss = sr.astimezone(denver), ss.astimezone(denver)
        self.assertLess(sr, ss)
        self.assertTrue(5.5 <= sr.hour + sr.minute / 60 <= 6.5, f"sunrise {sr}")
        self.assertTrue(19.5 <= ss.hour + ss.minute / 60 <= 20.75, f"sunset {ss}")


class Target(unittest.TestCase):
    def setUp(self):
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
        # 22 min into the 45-min ramp -> ~90, rounded to STEP.
        self.assertEqual(nl.target(self.at(20, 22), self.sr, self.ss), 90)

    def test_end_of_evening_ramp_is_floor(self):
        self.assertEqual(nl.target(self.at(20, 45), self.sr, self.ss), 80)

    def test_target_is_multiple_of_step(self):
        for m in range(0, 46):
            v = nl.target(self.at(20, 0) + timedelta(minutes=m), self.sr, self.ss)
            self.assertEqual(v % nl.STEP, 0)

    def test_pre_dawn_is_floor(self):
        self.assertEqual(nl.target(self.at(2, 0), self.sr, self.ss), 80)

    def test_morning_ramp_midpoint(self):
        self.assertEqual(nl.target(self.at(6, 22), self.sr, self.ss), 90)


class Apply(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.mkdtemp()
        self._orig = nl.STATE
        nl.STATE = os.path.join(self._tmp, "last")

    def tearDown(self):
        nl.STATE = self._orig
        shutil.rmtree(self._tmp, ignore_errors=True)

    def test_partial_failure_retries_failed_monitor_next_tick(self):
        # 6P7HGJ4 is "asleep" (setvcp raises); DP7HGJ4 succeeds.
        calls = []

        def fake_set(sn, val):
            calls.append((sn, val))
            if sn == "6P7HGJ4":
                raise RuntimeError("asleep")

        with mock.patch.object(nl, "_set_monitor", side_effect=fake_set):
            nl.apply(80)
            self.assertIn(("DP7HGJ4", 80), calls)   # both attempted on the first tick
            self.assertIn(("6P7HGJ4", 80), calls)
            calls.clear()
            nl.apply(80)                             # next tick, same target
        self.assertNotIn(("DP7HGJ4", 80), calls)     # succeeded panel is not re-written
        self.assertIn(("6P7HGJ4", 80), calls)        # failed panel IS retried

    def test_success_not_rewritten_when_unchanged(self):
        with mock.patch.object(nl, "_set_monitor") as m:
            nl.apply(80)
            self.assertEqual(m.call_count, 2)        # both set once
            m.reset_mock()
            nl.apply(80)                             # unchanged target
            self.assertEqual(m.call_count, 0)        # neither re-written


if __name__ == "__main__":
    unittest.main()
