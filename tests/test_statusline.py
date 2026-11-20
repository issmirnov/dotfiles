"""Tests for claude/statusline-command.sh, the Claude Code status line.

Claude Code pipes a JSON payload into the script and shows each line it
prints as a row. Line 1 says where the session is (host, launch directory,
worktree, moves, git, session name). Line 2 says what it uses (model, effort,
context bar, cost, cache, duration).

Each test runs the script on a payload with a pinned environment and checks
the output with the colors stripped. Run from the repo root:

    python3 -m unittest tests.test_statusline
    BASH_BIN=/bin/bash python3 -m unittest tests.test_statusline   # another bash
"""
import json
import os
import pathlib
import re
import subprocess
import tempfile
import unittest
import uuid

REPO = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = REPO / "claude" / "statusline-command.sh"
BASH = os.environ.get("BASH_BIN", "bash")
ANSI = re.compile(r"\x1b\[[0-9;]*m")


def ws(current, project=None):
    """A workspace payload. project defaults to current: Claude hasn't moved."""
    return {"workspace": {"current_dir": current, "project_dir": project or current}}


def cleanup(sid):
    """Remove the per-session state the script keeps in /tmp."""
    for f in pathlib.Path("/tmp").glob(f"claude-statusline-*-{sid}*"):
        f.unlink()


def registry(config_dir, *entries):
    """Write session registry files as Claude Code keeps them,
    <config dir>/sessions/<pid>.json. A str entry is written as is."""
    sessions = pathlib.Path(config_dir, "sessions")
    sessions.mkdir(parents=True)
    for pid, entry in enumerate(entries, start=4242):
        text = entry if isinstance(entry, str) else json.dumps({"pid": pid, **entry})
        (sessions / f"{pid}.json").write_text(text)


def render(payload, home="/home/u", columns=200, ssh=None, hostname="testhost", sid=None, extra_env=None):
    """Run the script on payload. Returns (raw_lines, plain_lines).

    With no sid, each call is a fresh session and its /tmp state is removed.
    Pass a sid to run several renders as one session; the caller cleans up.
    """
    fresh = sid is None
    if fresh:
        sid = f"test-{uuid.uuid4().hex}"
    data = {"session_id": sid, "model": {"display_name": "Opus 5.5"}, **payload}
    env = {
        "PATH": os.environ["PATH"],
        "HOME": home,
        "HOSTNAME": hostname,
        "LC_ALL": "C.UTF-8",
        "CLAUDE_CODE_EFFORT_LEVEL": "max",
    }
    if columns is not None:
        env["COLUMNS"] = str(columns)
    if ssh is not None:
        env["SSH_CONNECTION"] = ssh
    if extra_env:
        env.update(extra_env)
    try:
        out = subprocess.run(
            [BASH, str(SCRIPT)], input=json.dumps(data), env=env,
            capture_output=True, encoding="utf-8", check=True,
        ).stdout
    finally:
        if fresh:
            cleanup(sid)
    raw = out.split("\n")
    return raw, [ANSI.sub("", line) for line in raw]


class TwoLines(unittest.TestCase):
    PAYLOAD = {
        **ws("/home/u/proj"),
        "session_name": "Fix it",
        "context_window": {
            "used_percentage": 14,
            "current_usage": {"cache_read_input_tokens": 99, "cache_creation_input_tokens": 1},
        },
        "cost": {"total_cost_usd": 2.17, "total_duration_ms": 16 * 60 * 1000},
    }

    def test_prints_exactly_two_lines(self):
        _, plain = render(self.PAYLOAD)
        self.assertEqual(len(plain), 2, plain)

    def test_line2_is_model_effort_bar_then_usage(self):
        _, plain = render(self.PAYLOAD)
        self.assertEqual(plain[1], "Opus 5.5 ⚡max | █░░░░░░░░░ 14% | ~$2.17 | cache 99% | ⏱ 16m")

    def test_line1_holds_no_line2_segments(self):
        _, plain = render(self.PAYLOAD)
        for segment in ("Opus", "⚡", "%", "$", "⏱"):
            self.assertNotIn(segment, plain[0])


class Effort(unittest.TestCase):
    """Claude Code sends the session's level as effort.level. render() pins
    CLAUDE_CODE_EFFORT_LEVEL=max, so these show the payload wins over it."""

    def test_payload_level_beats_the_env_variable(self):
        _, plain = render({**ws("/home/u/proj"), "effort": {"level": "xhigh"}})
        self.assertIn("⚡xhigh", plain[1])
        self.assertNotIn("max", plain[1])

    def test_level_below_xhigh_is_flagged(self):
        _, plain = render({**ws("/home/u/proj"), "effort": {"level": "high"}})
        self.assertIn("⚠ high", plain[1])


class LineOne(unittest.TestCase):
    WT = "/home/u/proj/.claude/worktrees/feat"
    WT_INFO = {"name": "feat", "path": WT, "original_cwd": "/home/u/proj"}

    def test_not_moved_shows_host_and_launch_dir(self):
        _, plain = render(ws("/home/u/proj"))
        self.assertEqual(plain[0], "testhost ~/proj")

    def test_moved_shows_arrow_and_current_folder(self):
        _, plain = render(ws("/home/u/proj", project="/home/u"))
        self.assertEqual(plain[0], "testhost ~ → proj")

    def test_worktree_root_shows_leaf_not_arrow(self):
        _, plain = render({**ws(self.WT), "worktree": self.WT_INFO})
        self.assertEqual(plain[0], "testhost ~/proj 🌿 feat")

    def test_worktree_subdir_shows_leaf_then_arrow(self):
        _, plain = render({**ws(self.WT + "/charts", project=self.WT), "worktree": self.WT_INFO})
        self.assertEqual(plain[0], "testhost ~/proj 🌿 feat → charts")

    def test_session_name_comes_last(self):
        _, plain = render({**ws("/home/u/proj", project="/home/u"), "session_name": "Fix it"})
        self.assertEqual(plain[0], "testhost ~ → proj [Fix it]")

    def test_git_segment_follows_the_move(self):
        with tempfile.TemporaryDirectory() as home:
            repo = pathlib.Path(home, "proj")
            subprocess.run(["git", "init", "-q", "-b", "main", str(repo)], check=True)
            subprocess.run(
                ["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@t",
                 "-c", "commit.gpgsign=false", "commit", "-q", "--no-verify",
                 "--allow-empty", "-m", "init"],
                check=True,
            )
            _, plain = render(ws(str(repo), project=home), home=home)
        self.assertEqual(plain[0], "testhost ~ → proj git:(main)")

    def test_no_project_dir_falls_back_to_current_dir(self):
        _, plain = render({"workspace": {"current_dir": "/home/u/proj"}})
        self.assertEqual(plain[0], "testhost ~/proj")

    def test_launch_dir_outside_home_stays_absolute(self):
        _, plain = render(ws("/srv/data"))
        self.assertEqual(plain[0], "testhost /srv/data")

    def test_home_prefix_must_be_a_whole_component(self):
        _, plain = render(ws("/home/u2/x"))
        self.assertEqual(plain[0], "testhost /home/u2/x")

    def test_host_is_cut_at_the_first_dot(self):
        _, plain = render(ws("/home/u/proj"), hostname="lorium.local")
        self.assertEqual(plain[0], "lorium ~/proj")

    def test_local_host_is_dim(self):
        raw, _ = render(ws("/home/u/proj"))
        self.assertTrue(raw[0].startswith("\x1b[2mtesthost\x1b[0m "), repr(raw[0]))

    def test_ssh_host_is_bold_yellow(self):
        raw, _ = render(ws("/home/u/proj"), ssh="10.0.0.2 50000 10.0.0.1 22")
        self.assertTrue(raw[0].startswith("\x1b[1;33mtesthost\x1b[0m "), repr(raw[0]))


class SessionName(unittest.TestCase):
    """The bracket on line 1 holds the name other sessions use to message
    this one. Claude Code sends session_name only after /rename. The name a
    session picks for itself is only in its registry entry."""

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.home = tmp.name
        self.sid = f"test-{uuid.uuid4().hex}"
        self.addCleanup(cleanup, self.sid)

    def line1(self, *entries, session_name=None, extra_env=None):
        if entries:
            registry(pathlib.Path(self.home, ".claude"), *entries)
        payload = ws("/srv/proj")
        if session_name is not None:
            payload["session_name"] = session_name
        raw, plain = render(payload, home=self.home, sid=self.sid, extra_env=extra_env)
        return raw[0], plain[0]

    def test_registry_name_is_shown(self):
        _, line = self.line1({"sessionId": self.sid, "name": "proj-3f"})
        self.assertEqual(line, "testhost /srv/proj [proj-3f]")

    def test_registry_name_beats_session_name(self):
        # /rename writes both, so they match unless the registry write failed.
        # Other sessions message the registry name.
        _, line = self.line1({"sessionId": self.sid, "name": "proj-3f"}, session_name="Fix it")
        self.assertEqual(line, "testhost /srv/proj [proj-3f]")

    def test_entry_without_a_name_falls_back_to_session_name(self):
        _, line = self.line1({"sessionId": self.sid, "name": None}, session_name="Fix it")
        self.assertEqual(line, "testhost /srv/proj [Fix it]")

    def test_another_sessions_entry_does_not_match(self):
        _, line = self.line1({"sessionId": "someone-else", "hostSessionId": self.sid, "name": "not-me"})
        self.assertEqual(line, "testhost /srv/proj")

    def test_half_written_entry_falls_back_to_session_name(self):
        half = '{"pid": 4242, "sessionId": "%s", "name": "pro' % self.sid
        _, line = self.line1(half, session_name="Fix it")
        self.assertEqual(line, "testhost /srv/proj [Fix it]")

    def test_backslashes_and_control_characters_are_dropped(self):
        raw, line = self.line1({"sessionId": self.sid, "name": "a\x1b[31mb\\nc"})
        self.assertEqual(line, "testhost /srv/proj [a[31mbnc]")
        self.assertNotIn("\x1b[31mb", raw)

    def test_claude_config_dir_moves_the_registry(self):
        with tempfile.TemporaryDirectory() as cfg:
            registry(cfg, {"sessionId": self.sid, "name": "proj-3f"})
            _, line = self.line1(extra_env={"CLAUDE_CONFIG_DIR": cfg})
        self.assertEqual(line, "testhost /srv/proj [proj-3f]")


class LaunchDirSticks(unittest.TestCase):
    def test_launch_dir_survives_a_cd_then_a_worktree(self):
        # Claude cd's into sub/, then enters a worktree. worktree.original_cwd is
        # then .../sub, but line 1 keeps the directory from the first render.
        sid = f"test-{uuid.uuid4().hex}"
        self.addCleanup(cleanup, sid)
        render(ws("/home/u/proj"), sid=sid)
        render(ws("/home/u/proj/sub", project="/home/u/proj"), sid=sid)
        wt = "/home/u/proj/.claude/worktrees/demo"
        info = {"name": "demo", "path": wt, "original_cwd": "/home/u/proj/sub"}
        _, plain = render({**ws(wt), "worktree": info}, sid=sid)
        self.assertEqual(plain[0], "testhost ~/proj 🌿 demo")


class NarrowWindows(unittest.TestCase):
    LONG = "/home/u/Projects/1.Personal/ai/shotcraft-videos"

    def test_wide_window_keeps_the_full_path(self):
        _, plain = render(ws(self.LONG), columns=200)
        self.assertEqual(plain[0], "testhost ~/Projects/1.Personal/ai/shotcraft-videos")

    def test_narrow_window_shortens_the_launch_path_fish_style(self):
        _, plain = render(ws(self.LONG), columns=40)
        self.assertEqual(plain[0], "testhost ~/P/1/a/shotcraft-videos")

    def test_dot_component_keeps_two_characters(self):
        _, plain = render(ws("/home/u/.dotfiles-worktrees/statusline"), columns=20)
        self.assertEqual(plain[0], "testhost ~/.d/statusline")

    def test_only_the_launch_path_is_shortened(self):
        moved = ws("/home/u/Projects/1.Personal/ops/argo-k8s", project="/home/u/Projects/1.Personal/ops")
        _, plain = render(moved, columns=30)
        self.assertEqual(plain[0], "testhost ~/P/1/ops → argo-k8s")

    def test_no_columns_means_no_shortening(self):
        _, plain = render(ws(self.LONG), columns=None)
        self.assertEqual(plain[0], "testhost ~/Projects/1.Personal/ai/shotcraft-videos")


if __name__ == "__main__":
    unittest.main()
