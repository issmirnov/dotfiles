"""Tests for git/hooks/post-checkout, which post-merge and post-commit link to.

The hook diffs HEAD@{1}..HEAD and runs a command for each watched path that
changed. A pull or a branch switch that changes hypr/hyprland.lua reloads
Hyprland. Each test runs real git in a scratch repo whose hooks path is this
repo's git/hooks, with a fake hyprctl on PATH that records its arguments.

    python3 -m unittest -v tests.test_git_hooks
"""
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[1]
HOOKS = REPO / "git" / "hooks"


@unittest.skipUnless(sys.platform.startswith("linux"), "the hook checks hyprland.lua only on Linux")
class PostCheckout(unittest.TestCase):
    """main is two commits: one, then two, which changes hypr/hyprland.lua.
    The branch old stays at one."""

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = pathlib.Path(tmp.name)
        self.repo = root / "repo"
        self.calls = root / "hyprctl.log"
        fake_bin = root / "bin"
        fake_bin.mkdir()
        hyprctl = fake_bin / "hyprctl"
        hyprctl.write_text(f'#!/bin/sh\necho "$*" >> "{self.calls}"\n')
        hyprctl.chmod(0o755)
        self.env = {
            "PATH": f"{fake_bin}:{os.environ['PATH']}",
            "HOME": str(root),
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t",
            "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t",
        }
        self.git("init", "-q", "-b", "main", str(self.repo), cwd=root)
        self.git("config", "core.hooksPath", str(HOOKS))
        self.write("hypr/hyprland.lua", "-- one\n")
        self.write("notes.txt", "one\n")
        self.commit("one")
        self.git("branch", "old")
        self.write("hypr/hyprland.lua", "-- two\n")
        self.commit("two")
        self.calls.unlink(missing_ok=True)  # post-commit reloaded for commit two

    def git(self, *args, cwd=None):
        return subprocess.run(
            ["git", *args], cwd=cwd or self.repo, env=self.env,
            capture_output=True, text=True, check=True,
        )

    def write(self, rel, text):
        path = self.repo / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def commit(self, message):
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message)

    def hyprctl_calls(self):
        return self.calls.read_text().splitlines() if self.calls.exists() else []

    def test_file_checkout_runs_nothing(self):
        # HEAD stays on two, so HEAD@{1}..HEAD would still be one..two.
        self.write("notes.txt", "edited\n")
        self.git("checkout", "--", "notes.txt")
        self.assertEqual(self.hyprctl_calls(), [])

    def test_branch_switch_still_reloads(self):
        self.git("checkout", "-q", "old")
        self.assertEqual(self.hyprctl_calls(), ["version", "reload"])

    def test_pull_still_reloads(self):
        self.git("checkout", "-q", "old")
        self.calls.unlink()
        self.git("merge", "-q", "--ff-only", "main")
        self.assertEqual(self.hyprctl_calls(), ["version", "reload"])


if __name__ == "__main__":
    unittest.main()
