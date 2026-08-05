import importlib.util, importlib.machinery, pathlib, unittest
from datetime import datetime, date, timedelta

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
        # Denver, 2026-08-04: sunrise ~06:00, sunset ~20:10 local (tolerant bounds).
        sr, ss = nl.sun_times(date(2026, 8, 4), nl.LAT, nl.LON)
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


if __name__ == "__main__":
    unittest.main()
