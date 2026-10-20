"""Regression test for zsh/config/zsh-paste.zsh: a paste must survive pauses.

zsh's own paste reader ends a paste after $KEYTIMEOUT without input, and
bindkeys.zsh sets that to 10 ms. The rest of the paste then ran as keystrokes:
newlines executed lines, and the closing \\e[201~ switched to vicmd and swapped
the case of the last letter.

Each test starts an interactive zsh on a pty that loads only this checkout's
bindkeys.zsh and zsh-paste.zsh, sends paste bytes with timed pauses, and reads
$KEYMAP and $BUFFER back through a probe widget. Run from the repo root:

    python3 -m unittest tests.test_zsh_paste
    ZSH_BIN=/bin/zsh python3 -m unittest tests.test_zsh_paste   # another zsh
"""
import os
import pathlib
import select
import shutil
import subprocess
import tempfile
import time
import unittest

REPO = pathlib.Path(__file__).resolve().parents[1]
ZSH = os.environ.get("ZSH_BIN", "zsh")
START, END = b"\x1b[200~", b"\x1b[201~"
PROBE_KEY = b"\x18\x1a"  # ^X^Z, bound to the probe widget in both keymaps
TWO_LINES = b"print ran:$((40+2))\necho two"  # prints ran:42 only if it runs
INSERT = "main"  # $KEYMAP in vi insert mode after `bindkey -v`

RC = """\
source '{repo}/zsh/config/bindkeys.zsh'
{paste}
_probe() {{ print -rn -- "$KEYMAP"$'\\n'"$BUFFER" >| '{probe}.tmp' && mv -f '{probe}.tmp' '{probe}' }}
zle -N _probe
bindkey -M viins '^X^Z' _probe
bindkey -M vicmd '^X^Z' _probe
"""
REPO_PASTE = "source '{repo}/zsh/config/zsh-paste.zsh'"
STOCK_PASTE = ("autoload -Uz bracketed-paste-url-magic; "
               "zle -N bracketed-paste bracketed-paste-url-magic")


class Zsh:
    """An interactive zsh on a pty with a minimal rc."""

    def __init__(self, paste=REPO_PASTE):
        self.dir = tempfile.mkdtemp(prefix="zsh-paste-test.")
        self.probe = os.path.join(self.dir, "probe")
        with open(os.path.join(self.dir, ".zshrc"), "w") as f:
            f.write(RC.format(repo=REPO, probe=self.probe,
                              paste=paste.format(repo=REPO)))
        env = dict(os.environ, ZDOTDIR=self.dir, TERM="xterm-256color")
        self.pid, self.fd = os.forkpty()
        if self.pid == 0:
            os.execvpe(ZSH, [ZSH, "-d", "-i"], env)
        os.set_blocking(self.fd, False)
        self.out = b""
        deadline = time.monotonic() + 10
        while b"\x1b[?2004h" not in self.out:  # zle is up, bracketed paste on
            if time.monotonic() > deadline:
                raise AssertionError(f"zsh never started zle: {self.out!r}")
            self.read(0.05)

    def read(self, secs):
        """Collect output for `secs` seconds, so the pty never fills up."""
        deadline = time.monotonic() + secs
        while True:
            left = max(0.0, deadline - time.monotonic())
            if not select.select([self.fd], [], [], left)[0]:
                if left == 0:
                    return
                continue
            try:
                chunk = os.read(self.fd, 65536)
            except (BlockingIOError, OSError):
                return
            if not chunk:
                return
            self.out += chunk

    def write(self, data):
        while data:
            if select.select([], [self.fd], [], 1)[1]:
                try:
                    data = data[os.write(self.fd, data[:4096]):]
                except BlockingIOError:
                    pass
            self.read(0)

    def send(self, *pieces):
        """Each piece is bytes, or (bytes, seconds to pause after it)."""
        for piece in pieces:
            data, pause = piece if isinstance(piece, tuple) else (piece, 0)
            self.write(data)
            self.read(pause)

    def state(self):
        """Run the probe widget and return ($KEYMAP, $BUFFER)."""
        self.write(PROBE_KEY)
        deadline = time.monotonic() + 10
        while not os.path.exists(self.probe):
            if time.monotonic() > deadline:
                raise AssertionError(f"probe never ran: {self.out[-400:]!r}")
            self.read(0.02)
        with open(self.probe) as f:
            keymap, _, buffer = f.read().partition("\n")
        os.unlink(self.probe)
        return keymap, buffer

    def open_fds(self):
        fds = f"/proc/{self.pid}/fd"
        return len(os.listdir(fds)) if os.path.isdir(fds) else None

    def close(self):
        os.kill(self.pid, 9)
        os.waitpid(self.pid, 0)
        os.close(self.fd)
        shutil.rmtree(self.dir)


class PatientPaste(unittest.TestCase):
    def setUp(self):
        self.zsh = Zsh()
        self.addCleanup(self.zsh.close)

    def assertPasted(self, buffer):
        self.assertEqual(self.zsh.state(), (INSERT, buffer))
        self.assertNotIn(b"ran:42", self.zsh.out, "a pasted line ran")

    def test_uses_the_patient_reader(self):
        env = dict(os.environ, ZDOTDIR=self.zsh.dir, TERM="xterm-256color")
        widget = subprocess.run(
            [ZSH, "-d", "-i", "-c", "print -r -- $widgets[bracketed-paste]"],
            env=env, capture_output=True, text=True).stdout.strip()
        self.assertEqual(widget, "user:bracketed-paste-patient",
                         "zsh/system or zsh/zselect did not load, so "
                         "zsh-paste.zsh fell back to zsh's own reader")

    def test_paste_in_one_write(self):
        self.zsh.send(START + b"echo hello" + END)
        self.assertPasted("echo hello")

    def test_pause_before_end_marker(self):
        self.zsh.send((START + b"echo hello", 0.2), END)
        self.assertPasted("echo hello")

    def test_pause_after_start_marker(self):
        self.zsh.send((START, 0.02), TWO_LINES + END)
        self.assertPasted(TWO_LINES.decode())

    def test_pause_inside_text(self):
        self.zsh.send((START + b"print ran:$((40", 0.2),
                      b"+2))\necho two" + END)
        self.assertPasted(TWO_LINES.decode())

    def test_stall_over_a_second_waits_and_says_so(self):
        self.zsh.send((START + b"echo hel", 1.5))
        self.assertIn(b"Waiting for the rest of the paste", self.zsh.out)
        self.zsh.send(b"lo" + END)
        self.assertPasted("echo hello")

    def test_ctrl_c_cancels_a_stalled_paste(self):
        fds = self.zsh.open_fds()
        self.zsh.send((START + b"echo hello", 1.2), (b"\x03", 0.5))
        self.assertEqual(self.zsh.state(), (INSERT, ""))
        self.assertEqual(self.zsh.open_fds(), fds, "the tty fd leaked")

    def test_url_is_quoted(self):
        self.zsh.send(START + b"https://example.com/a?b=1&c=2" + END)
        self.assertPasted("'https://example.com/a?b=1&c=2'")

    def test_keys_typed_right_behind_the_paste(self):
        self.zsh.send(START + b"echo hello" + END + b"-v")
        self.assertPasted("echo hello-v")

    def test_empty_paste(self):
        self.zsh.send(START + END)
        self.assertPasted("")

    def test_carriage_returns_become_newlines(self):
        self.zsh.send(START + b"echo a\recho b" + END)
        self.assertPasted("echo a\necho b")

    def test_large_paste_is_fast(self):
        payload = b"word " * 13107  # 64 KB
        t0 = time.monotonic()
        self.zsh.send(START + payload + END)
        self.assertPasted(payload.decode())
        self.assertLess(time.monotonic() - t0, 1.0)


class StockReader(unittest.TestCase):
    """Control: zsh's own reader breaks on the same pause. If this starts
    failing, zsh may have fixed its reader, or the harness no longer
    reproduces the bug."""

    def test_stock_reader_breaks_on_a_pause(self):
        zsh = Zsh(paste=STOCK_PASTE)
        self.addCleanup(zsh.close)
        zsh.send((START + b"echo hello", 0.2), END)
        self.assertEqual(zsh.state(), ("vicmd", "echo hellO"))


if __name__ == "__main__":
    unittest.main()
