#!/usr/bin/env python3
"""Merge shared status-line settings into a local Codex config (Python 3.11+)."""

import copy
import os
from pathlib import Path
import re
import sys
import tempfile

try:
    import tomllib
except ImportError:
    sys.exit("Codex status line requires Python 3.11+; run this installer with a newer Python.")


SETTINGS = Path(__file__).with_name("statusline.toml")


def merge(original, settings):
    """Edit conventional [tui] assignments; reject other layouts without writing."""
    before = tomllib.loads(original)
    expected = copy.deepcopy(before)
    expected.setdefault("tui", {}).update(settings)
    if expected == before:
        return original

    lines = original.splitlines(keepends=True)
    headers = [i for i, line in enumerate(lines) if line.lstrip().startswith("[")]
    tui = [i for i in headers if re.fullmatch(r"\s*\[tui\]\s*(?:#.*)?", lines[i].rstrip())]
    if len(tui) > 1:
        raise ValueError("Multiple [tui] headers")
    start = tui[0] + 1 if tui else len(lines)
    end = next((i for i in headers if i >= start), len(lines))
    body = lines[start:end]
    for key in settings:
        matches = [i for i, line in enumerate(body)
                   if re.match(r"\s*" + re.escape(key) + r"\s*=", line)]
        for index in reversed(matches):
            # Parsing the assignment locates the end of multiline arrays safely.
            for stop in range(index + 1, len(body) + 1):
                try:
                    value = tomllib.loads("".join(body[index:stop]))
                except tomllib.TOMLDecodeError:
                    continue
                if set(value) != {key}:
                    raise ValueError("Cannot isolate status-line assignment")
                del body[index:stop]
                break
            else:
                raise ValueError("Cannot parse status-line assignment")
    # Use the reviewed TOML fragment as the source of values and ordering.
    fragment = SETTINGS.read_text().split("[tui]\n", 1)[1]
    prefix = "".join(lines[:start])
    if prefix and not prefix.endswith("\n"):
        prefix += "\n"
    if not tui:
        prefix += "\n[tui]\n"
    result = prefix + fragment + "".join(body) + "".join(lines[end:])
    if tomllib.loads(result) != expected:
        raise ValueError("Unsupported TOML layout; update the two [tui] keys manually")
    return result


def install(target):
    target = target.expanduser().resolve()
    original = target.read_text() if target.exists() else ""
    settings = tomllib.loads(SETTINGS.read_text())["tui"]
    result = merge(original, settings)
    if result == original:
        print("Codex status line already configured")
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        # mkstemp creates private backups, including when config contains secrets.
        fd, backup = tempfile.mkstemp(prefix="config.toml.bak-statusline-", dir=target.parent)
        with os.fdopen(fd, "w") as stream:
            stream.write(original)
        print("Backup:", backup)
    fd, temporary = tempfile.mkstemp(prefix=".config.toml-", dir=target.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(result)
        current = target.read_text() if target.exists() else ""
        if current != original:
            raise ValueError("Config changed during installation; retry")
        os.replace(temporary, target)
    finally:
        Path(temporary).unlink(missing_ok=True)
    print("Configured Codex status line; restart Codex to load it")


if __name__ == "__main__":
    config_home = Path(os.environ.get("CODEX_HOME") or Path.home() / ".codex")
    try:
        install(config_home / "config.toml")
    except (OSError, ValueError, TypeError) as error:
        # TOML errors can contain config contents; keep diagnostics generic.
        sys.exit("Could not update Codex config (" + type(error).__name__ + "). File left unchanged; check its TOML layout and permissions.")
