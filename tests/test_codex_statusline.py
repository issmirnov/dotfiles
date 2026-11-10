import contextlib
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "codex/install-statusline.py"
SPEC = importlib.util.spec_from_file_location("codex_statusline", SCRIPT)
installer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(installer)
SETTINGS = tomllib.loads(installer.SETTINGS.read_text())["tui"]


class CodexStatuslineTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.directory = Path(self.scratch.name)
        self.target = self.directory / "config.toml"

    def install(self):
        with contextlib.redirect_stdout(io.StringIO()):
            installer.install(self.target)

    def test_new_config_and_idempotence(self):
        self.install()
        self.assertEqual(tomllib.loads(self.target.read_text()), {"tui": SETTINGS})
        before = self.target.stat().st_mtime_ns
        self.install()
        self.assertEqual(self.target.stat().st_mtime_ns, before)
        self.assertFalse(list(self.directory.glob("*.bak-*")))
        self.assertEqual(self.target.stat().st_mode & 0o777, 0o600)

    def test_preserves_local_settings_and_comments(self):
        original = '''# local preferences
model = "example-model"
[tui] # display preferences
theme = "example-theme" # keep this comment
status_line = [
  "model", # old layout
  "current-dir",
]
status_line_use_colors = false
[tui.model_availability_nux]
example = 4
[projects."/example/project"]
trust_level = "trusted"
'''
        self.target.write_text(original)
        self.install()
        actual = self.target.read_text()
        expected = tomllib.loads(original)
        expected["tui"].update(SETTINGS)
        self.assertEqual(tomllib.loads(actual), expected)
        self.assertIn('# local preferences', actual)
        self.assertIn('theme = "example-theme" # keep this comment', actual)
        backups = list(self.directory.glob("*.bak-*"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), original)
        self.assertEqual(backups[0].stat().st_mode & 0o777, 0o600)
        self.install()
        self.assertEqual(list(self.directory.glob("*.bak-*")), backups)

    def test_missing_table_and_no_final_newline(self):
        original = '[tui.model_availability_nux]\nexample = 4'
        self.target.write_text(original)
        self.install()
        actual = tomllib.loads(self.target.read_text())
        self.assertEqual(actual["tui"]["model_availability_nux"], {"example": 4})
        self.assertEqual(actual["tui"]["status_line"], SETTINGS["status_line"])

    def test_unusual_layouts_fail_without_writing(self):
        for original in ('tui = {status_line = ["model"]}\n',
                         '[tui]\n"status_line" = ["model"]\n',
                         '[tui]\nstatus_line = [\n'):
            with self.subTest(original=original):
                self.target.write_text(original)
                with self.assertRaises(ValueError):
                    self.install()
                self.assertEqual(self.target.read_text(), original)
                self.assertFalse(list(self.directory.glob("*.bak-*")))

    def test_symlink_preserved(self):
        destination = self.directory / "local.toml"
        destination.write_text('model = "example-model"\n')
        self.target.symlink_to(destination)
        self.install()
        self.assertTrue(self.target.is_symlink())
        self.assertEqual(tomllib.loads(destination.read_text())["tui"], SETTINGS)

    def test_custom_codex_home(self):
        custom = self.directory / "custom"
        result = subprocess.run([sys.executable, str(SCRIPT)],
                                env={**os.environ, "CODEX_HOME": str(custom)},
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(tomllib.loads((custom / "config.toml").read_text())["tui"], SETTINGS)

    def test_dotbot_command_skips_without_codex(self):
        command = next(line.split("command: ", 1)[1] for line in
                       (ROOT / "default.conf.yaml").read_text().splitlines()
                       if "command:" in line and "codex/install-statusline.py" in line)
        binaries = self.directory / "bin"
        binaries.mkdir()
        (binaries / "python3").symlink_to(sys.executable)
        custom = self.directory / "custom"
        environment = {**os.environ, "PATH": str(binaries), "CODEX_HOME": str(custom)}
        skipped = subprocess.run(command, shell=True, cwd=ROOT, env=environment,
                                 capture_output=True, text=True)
        self.assertEqual(skipped.returncode, 0, skipped.stderr)
        self.assertFalse(custom.exists())
        (binaries / "codex").symlink_to("/bin/true")
        installed = subprocess.run(command, shell=True, cwd=ROOT, env=environment,
                                   capture_output=True, text=True)
        self.assertEqual(installed.returncode, 0, installed.stderr)
        self.assertEqual(tomllib.loads((custom / "config.toml").read_text())["tui"], SETTINGS)


if __name__ == "__main__":
    unittest.main()
