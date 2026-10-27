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
import unittest
import uuid

REPO = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = REPO / "claude" / "statusline-command.sh"
BASH = os.environ.get("BASH_BIN", "bash")
ANSI = re.compile(r"\x1b\[[0-9;]*m")


def ws(current, project=None):
    """A workspace payload. project defaults to current: Claude hasn't moved."""
    return {"workspace": {"current_dir": current, "project_dir": project or current}}


def render(payload, home="/home/u", columns=200, ssh=None, hostname="testhost"):
    """Run the script on payload. Returns (raw_lines, plain_lines)."""
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
    try:
        out = subprocess.run(
            [BASH, str(SCRIPT)], input=json.dumps(data), env=env,
            capture_output=True, encoding="utf-8", check=True,
        ).stdout
    finally:
        # The script keeps per-session git and tokens/min state in /tmp.
        for f in pathlib.Path("/tmp").glob(f"claude-statusline-*-{sid}*"):
            f.unlink()
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


if __name__ == "__main__":
    unittest.main()
