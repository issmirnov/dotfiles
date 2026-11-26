"""Tests for the SessionStart hook in claude/settings.json that raises the
agent's OOM score.

Claude Code runs a hook command with /bin/sh -c, so the hook's $PPID is the
claude process. Each test starts a small Python parent that runs the hook the
same way and then reports its own oom_score_adj. Raising a score needs no
privileges, so the tests run as a normal user.

    python3 -m unittest -v tests.test_claude_oom_hook
"""
import json
import pathlib
import subprocess
import sys
import textwrap
import unittest

REPO = pathlib.Path(__file__).resolve().parents[1]
MARKER = "oom_score_adj"


def hook_command():
    settings = json.loads((REPO / "claude" / "settings.json").read_text())
    found = [
        hook["command"]
        for group in settings["hooks"]["SessionStart"]
        for hook in group.get("hooks", [])
        if MARKER in hook.get("command", "")
    ]
    assert len(found) == 1, f"expected one SessionStart hook mentioning {MARKER}, found {len(found)}"
    return found[0]


# The parent optionally sets its own score first, runs the hook under /bin/sh
# with JSON on stdin, then prints the hook's exit code, output and its score.
PARENT = textwrap.dedent(
    """
    import json, subprocess, sys
    command, start, payload_size = sys.argv[1], sys.argv[2], int(sys.argv[3])
    if start:
        with open("/proc/self/oom_score_adj", "w") as fh:
            fh.write(start)
    proc = subprocess.Popen(["/bin/sh", "-c", command], stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    broken_pipe = False
    try:
        proc.stdin.write(b'{"hook_event_name": "SessionStart", "pad": "' + b"x" * payload_size + b'"}')
        proc.stdin.close()
    except BrokenPipeError:
        broken_pipe = True
    out, err = proc.stdout.read(), proc.stderr.read()
    code = proc.wait()
    with open("/proc/self/oom_score_adj") as fh:
        score = int(fh.read())
    print(json.dumps({"code": code, "out": out.decode(), "err": err.decode(),
                      "broken_pipe": broken_pipe, "score": score}))
    """
)


def run_parent(command, start="", payload_size=64):
    result = subprocess.run(
        [sys.executable, "-I", "-c", PARENT, command, start, str(payload_size)],
        capture_output=True, text=True, timeout=30, check=True,
    )
    return json.loads(result.stdout)


def own_score():
    return int(pathlib.Path("/proc/self/oom_score_adj").read_text())


@unittest.skipUnless(sys.platform.startswith("linux"), "oom_score_adj exists only on Linux")
class OomHook(unittest.TestCase):
    def setUp(self):
        self.command = hook_command()

    def test_raises_the_parent_to_700_silently(self):
        if own_score() >= 700:
            self.skipTest("this process already scores 700 or more, so nothing can be raised")
        got = run_parent(self.command)
        self.assertEqual(got["score"], 700)
        self.assertEqual((got["code"], got["out"], got["err"]), (0, "", ""))

    def test_never_lowers_a_higher_score(self):
        if own_score() > 900:
            self.skipTest("this process scores above 900 and cannot lower itself to 900")
        got = run_parent(self.command, start="900")
        self.assertEqual(got["score"], 900)
        self.assertEqual((got["code"], got["out"], got["err"]), (0, "", ""))

    def test_reads_all_of_stdin(self):
        # 1 MiB is far more than a pipe buffer, so the write would fail with
        # EPIPE if the hook exited without reading its input.
        got = run_parent(self.command, payload_size=1 << 20)
        self.assertFalse(got["broken_pipe"])
        self.assertEqual((got["code"], got["out"], got["err"]), (0, "", ""))

    def test_silent_no_op_without_the_proc_file(self):
        # Stands in for macOS, where /proc does not exist.
        before = own_score()
        command = self.command.replace("/proc/", "/nonexistent-proc/")
        self.assertNotEqual(command, self.command)
        got = run_parent(command)
        self.assertEqual(got["score"], before)
        self.assertEqual((got["code"], got["out"], got["err"]), (0, "", ""))


if __name__ == "__main__":
    unittest.main()
