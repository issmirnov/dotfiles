"""bin/claude-peak: the exit code and the printed time at the window's edges.

Each case pins "now" with CLAUDE_PEAK_NOW. Python works out that epoch from a
Pacific wall-clock time, so the test does not reuse the script's date(1) math.
"""
import os, pathlib, re, subprocess, unittest
from datetime import datetime
from zoneinfo import ZoneInfo

CMD = pathlib.Path(__file__).resolve().parents[1] / "bin" / "claude-peak"
PACIFIC = ZoneInfo("America/Los_Angeles")


def run(now=None, tz="UTC", args=()):
    env = dict(os.environ, TZ=tz)
    env.pop("CLAUDE_PEAK_NOW", None)
    if now is not None:
        env["CLAUDE_PEAK_NOW"] = str(now)
    p = subprocess.run([str(CMD), *args], env=env, capture_output=True, text=True)
    return p.returncode, p.stdout


def at(*pacific_wall_clock):
    return int(datetime(*pacific_wall_clock, tzinfo=PACIFIC).timestamp())


class Edges(unittest.TestCase):
    def check(self, when, code, line):
        self.assertEqual(run(at(*when)), (code, line + "\n"))

    # Monday 2026-11-30, PST.
    def test_monday_last_second_before_peak(self):
        self.check((2026, 11, 30, 4, 59, 59), 1, "off-peak, next peak 2026-11-30T05:00:00-08:00")

    def test_monday_start_is_inclusive(self):
        self.check((2026, 11, 30, 5, 0, 0), 0, "peak until 2026-11-30T11:00:00-08:00")

    def test_monday_last_second_of_peak(self):
        self.check((2026, 11, 30, 10, 59, 59), 0, "peak until 2026-11-30T11:00:00-08:00")

    def test_monday_end_is_exclusive(self):
        self.check((2026, 11, 30, 11, 0, 0), 1, "off-peak, next peak 2026-12-01T05:00:00-08:00")

    def test_saturday_waits_for_monday(self):
        self.check((2026, 11, 28, 6, 0, 0), 1, "off-peak, next peak 2026-11-30T05:00:00-08:00")

    def test_friday_end_waits_for_monday(self):
        self.check((2026, 11, 27, 11, 0, 0), 1, "off-peak, next peak 2026-11-30T05:00:00-08:00")


class DaylightSaving(unittest.TestCase):
    # DST starts Sunday 2026-03-08 and ends Sunday 2026-11-01.
    def check(self, when, code, line):
        self.assertEqual(run(at(*when)), (code, line + "\n"))

    def test_friday_before_dst_starts_points_at_pdt_monday(self):
        self.check((2026, 3, 6, 11, 0, 0), 1, "off-peak, next peak 2026-03-09T05:00:00-07:00")

    def test_monday_after_dst_starts(self):
        self.check((2026, 3, 9, 5, 0, 0), 0, "peak until 2026-03-09T11:00:00-07:00")

    def test_friday_before_dst_ends_points_at_pst_monday(self):
        self.check((2026, 10, 30, 11, 0, 0), 1, "off-peak, next peak 2026-11-02T05:00:00-08:00")

    def test_monday_after_dst_ends(self):
        self.check((2026, 11, 2, 5, 0, 0), 0, "peak until 2026-11-02T11:00:00-08:00")


class Contract(unittest.TestCase):
    def test_host_time_zone_does_not_leak(self):
        now = at(2026, 11, 30, 10, 0, 0)   # already Tuesday 03:00 in Tokyo
        self.assertEqual(run(now, tz="Asia/Tokyo"), run(now))

    def test_live_clock_answers_peak_or_off_peak(self):
        code, out = run()
        iso = r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d\d:\d\d"
        expected = rf"peak until {iso}\n" if code == 0 else rf"off-peak, next peak {iso}\n"
        self.assertIn(code, (0, 1))
        self.assertRegex(out, rf"\A{expected}\Z")

    def test_bad_now_is_an_error_not_off_peak(self):
        code, out = run("not-a-time")
        self.assertEqual((code, out), (2, ""))

    def test_unknown_argument_is_an_error(self):
        code, out = run(at(2026, 11, 30, 6, 0, 0), args=("--nope",))
        self.assertEqual((code, out), (2, ""))


if __name__ == "__main__":
    unittest.main()
