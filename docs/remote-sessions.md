# Remote + local session restore (`sesh`)

`sesh` reopens the terminal sessions you had open, after a reboot or a laptop sleep, without a list you maintain by hand. It covers two kinds of work at once:

- **Local** Claude Code sessions on your Mac, resumed in their own directory.
- **Remote** `tmux` sessions on a box you reach over `mosh`, reattached in place.

The working set is whatever was **live** when you last worked, captured in a snapshot and rebuilt at the next login. You never curate a list.

This guide lets a teammate (or an assistant helping one) stand the same thing up for their own boxes. The worked example is one homelab box named `hexane`, with a Claude launcher named `ccf`. The [Adapt it to your boxes](#adapt-it-to-your-boxes) section marks every part you swap.

## Who this is for

A developer on a MacBook who keeps many sessions open: some local, some on remote boxes reached with `mosh` + `tmux`, often running Claude Code. The pain this removes:

- Plain `ssh box` drops on sleep (`Read from remote host ... timed out`), forcing a manual `tmux attach` on every wake.
- After a reboot you reopen a dozen windows by hand and try to remember which was which.
- A static "sessions to restore" list goes stale the moment your work moves.

## What you get

- One command, `sesh`, to fuzzy-pick any session (local or remote) and open it in the current window.
- `sesh <query>` to jump straight to the first match, no picker.
- Login auto-restore: the set you had open comes back as titled windows.
- `mosh` for the remote legs, so a reattached session survives sleep with no action from you.
- Warm runs in about 0.45s, because the candidate list is cached.

## The idea (portable)

Three ideas carry the whole design. None of them depend on this repo.

1. **The working set is live state, not a list.** A background job snapshots whatever is open every two minutes. Restore replays that snapshot. There is nothing to edit.
2. **One small launcher per session type.** A local session and a remote session open differently, so each has its own launcher script (`cc-connect`, `hx-connect`). Everything else calls those two.
3. **The terminal is the state store.** Session identity, titles, and directory all come from the running session (the Claude transcript on disk, the `tmux` session name), so the snapshot holds only pointers (IDs and paths), never content.

Layered on top: a `mosh` transport that survives sleep, `tmux` for persistence on the remote side, and Ghostty windows that carry real titles.

## Architecture

```
  LIVE SESSIONS                     SNAPSHOT                      AT LOGIN
  -------------                     --------                      --------
  local:  ~/.claude/sessions/*.json   sesh-save (every 120s)      sesh-restore (RunAtLoad)
          with a live PID        -->  writes snapshot.json   -->  reopens each entry as a
  remote: marker files in             {local:[{id,cwd}],           Ghostty window, skipping
          state/sesh/remote/           remote:[{session}]}         anything already live

  ON DEMAND
  ---------
  sesh [query]  -->  candidates = (newest local transcripts) + (`ssh box tmux ls`)
                -->  fzf picks one (or <query> matches the first)
                -->  exec the right launcher in THIS window
```

The three verbs:

| Command | Role | Trigger |
|---------|------|---------|
| `sesh-save` | Snapshot the live set to `snapshot.json` | LaunchAgent, every 120s |
| `sesh-restore` (alias `revive`) | Rebuild the snapshot as windows | LaunchAgent at login, or by hand |
| `sesh [-r] [-n] [query]` | Pick/open a session on demand | You |

State lives in `~/.local/state/sesh/`:

- `snapshot.json` the last live set.
- `remote/<session>` a presence marker (a PID) written by `hx-connect` while a remote session is open.
- `labels.tsv` cached local labels, keyed by transcript path + mtime.
- `remote.list`, `remote.fail` the cached remote session list and a negative-cache marker.
- `restore.log`, `save.err.log` logs.

## The pieces (file map)

| File | What it does |
|------|--------------|
| `bin/sesh` | On-demand picker/opener over local + remote sessions. Sourceable; has a test suite. |
| `bin/sesh-save` | Snapshots live local (PID-checked) + remote (marker) sessions to `snapshot.json`. |
| `bin/sesh-restore` | Rebuilds the snapshot at login as Ghostty windows; skips live ones; caps the count. |
| `bin/cc-connect` | Launcher for a **local** Claude session: `cd`, set title, resume Claude. |
| `bin/hx-connect` | Launcher for a **remote** session: write marker, set title, `mosh box -- tmux new-session -A -s <name>`. |
| `bin/tests/sesh.test.sh` | 18 tests for the cache + window logic; injects `ssh` so no network is touched. |
| `MacOS-LaunchAgents/localhost.sesh-save.plist` | Runs `sesh-save` every 120s. |
| `MacOS-LaunchAgents/localhost.sesh-restore.plist` | Runs `sesh-restore` once at login (`RunAtLoad`). |
| `ghostty/config` | `window-save-state = never` (see gotchas) and the theme. |
| `zsh/aliases/utilities.zsh` | `revive` alias and the `title()` helper. |
| `~/.ssh/config` | The `Host` block for your box, with connection multiplexing. **Local file, not in this repo.** |

## Worked example: Ivan's setup (hexane + ccf)

This is how the example machine is wired. Read it as "one concrete instance," then swap the marked parts.

- **Remote box**: an ssh alias `hexane` on the home LAN, reached over `mosh`. It runs about 16 per-project `tmux` sessions named like `cc-argo`, `cc-pinley`.
- **Local launcher**: `cc-connect` runs Claude through `ccf`, a shell function that adds API-key routing and `--dangerously-skip-permissions`. `ccf` lives in `~/.zshrc.local`, a machine-local file that holds the key. It is **not** in the dotfiles repo. `cc-connect` sources it at runtime and falls back to plain `claude` if it is absent.
- **Terminal**: Ghostty, one window per restored session. Titles come from an OSC escape the launchers emit, then `tmux set-titles` takes over on the remote side.
- **Window switching**: Raycast's "Switch Windows" command, because the windows now carry real titles.

## Adapt it to your boxes

Everything machine-specific is small and in known places. The checklist:

1. **Your remote box** (`~/.ssh/config`, local file): add a `Host` block with an alias, your box's address, user, and key. Add connection multiplexing so repeated calls reuse one connection:

   ```
   Host mybox                       # <- your alias
       Hostname 10.x.x.x            # <- LAN IP, Tailscale name, whatever
       User you
       IdentityFile ~/.ssh/you.key
       # Reuse one connection across calls. mosh is unaffected.
       ControlMaster auto
       ControlPath ~/.ssh/sockets/%C
       ControlPersist 10m
   ```
   Then `mkdir -p ~/.ssh/sockets && chmod 700 ~/.ssh/sockets`.

2. **The box name in the scripts**: the scripts read `HX_HOST` (default `hexane`). Either name your ssh alias `hexane`, or export `HX_HOST=mybox` in your shell, or edit the default in `bin/sesh`, `bin/sesh-restore`, `bin/hx-connect`.

3. **The local launcher** (`bin/cc-connect`): if you do not use a key-routing wrapper, delete the `ccf` branch and run Claude directly:

   ```bash
   cd "$cwd" 2>/dev/null || cd "$HOME"
   exec "$HOME/.local/bin/claude" --resume "$@"
   ```
   Keep the key, if you have one, in `~/.zshrc.local` (or any file outside the repo), never in `cc-connect`.

4. **Remote `tmux` naming**: name one `tmux` session per project on the box (`tmux new -s myproj`). `sesh` lists them with `ssh box tmux ls`. Any names work; a prefix like `cc-` only helps you scan.

5. **Paths and labels**: the plists hardcode `/Users/<you>/.dotfiles/bin/...` and log paths. Fix the user. The `Label` keys (`localhost.sesh-save`, `localhost.sesh-restore`) can stay or be renamed; if you rename, use the new name in every `launchctl` command.

6. **The remote `tmux` title line** (on the box, `~/.tmux.conf`): for self-labelling tabs, add:
   ```
   set -g set-titles on
   set -g set-titles-string "#S · #W"
   ```

## Install

On the Mac:

1. Dependencies: `brew install jq fzf mosh` and a terminal that titles windows (this example uses Ghostty). Claude Code at `~/.local/bin/claude`.
2. On the remote box: `tmux`, a `mosh` server, and a **UTF-8 locale** (see gotchas), plus the `xterm-*` terminfo for your terminal if `tmux` complains.
3. Put `bin/` on your `PATH` (this repo does it in `zsh/config/paths.zsh`), so `sesh` and `sesh-save`/`sesh-restore` resolve as commands.
4. Ghostty config: set `window-save-state = never` (see gotchas).
5. Install the LaunchAgents by symlinking both plists into `~/Library/LaunchAgents/`, then load them:
   ```bash
   launchctl load -w ~/Library/LaunchAgents/localhost.sesh-save.plist
   launchctl load -w ~/Library/LaunchAgents/localhost.sesh-restore.plist
   ```
   `launchd` also auto-loads anything in `~/Library/LaunchAgents/` at the next login.
6. Verify they are loaded:
   ```bash
   launchctl list | grep sesh
   ```
   You want a line for each label. `sesh-save` runs on an interval, so it stays listed. `sesh-restore` is `RunAtLoad`, so it runs once at login and then shows its last exit code.

## Gotchas that cost us hours

Each of these was a real bug. They are the reason the scripts look the way they do.

- **Ghostty phantom windows.** Set `window-save-state = never`. With the default, every `open -na Ghostty --args ...` also **restores** the previous windows on top, so each restore spawns empty duplicates. This, not `--initial-window=false` (a red herring), was the fix.
- **Pass the launcher as clean argv.** Restore opens a window with `open -na Ghostty --args -e <launcher> <args>`. An inline `-e /bin/sh -c "..."` gets its quoting mangled by `open --args` and the window falls back to a bare login shell. A standalone launcher script (`cc-connect`, `hx-connect`) takes clean arguments. Ghostty's `-e prog a b c` does preserve spaced args (verified).
- **`--title=` as a launch flag aborts the launch.** Set the title with an OSC escape inside the launcher instead: `printf '\033]0;%s\007' "$name"`.
- **`mosh` strips OSC 52.** Window-title OSC still passes, so titles work. Copying text from a remote `tmux` to the Mac clipboard over `mosh` can fail. Use a native terminal selection, or switch the transport to Eternal Terminal (TCP, keeps OSC 52) if clipboard matters more than sleep-survival.
- **`mosh` needs a UTF-8 locale on the server.** mosh-server refuses to start unless the remote box has a real UTF-8 locale, because your client forwards `LC_ALL`/`LANG` and the server must honor it. A minimal server image can lack it, or even lack the `locales` package. The failure looks like `mosh: Did not find mosh server startup message` after a wall of `setlocale` warnings. Diagnose with `ssh box 'LC_ALL=en_US.UTF-8 locale charmap'` (you want `UTF-8`, not `US-ASCII` / `ANSI_X3.4-1968`). Fix on the box: `sudo apt-get install -y locales && sudo locale-gen en_US.UTF-8`, matching the locale your client sends.
- **LaunchAgents get a minimal `PATH`.** Each script sets its own `PATH` and calls Claude by absolute path (`~/.local/bin/claude`). A LaunchAgent will not find a tool on your interactive shell `PATH`.
- **The Claude project slug is lossy.** `~/.claude/projects/<slug>/` collapses dotted paths, so the real working directory is read from inside the session's `.jsonl` (`.cwd`), not from the slug.
- **Spawning a window from inside Claude.** `cc-connect` unsets `CLAUDE_CODE_CHILD_SESSION`, or the child session does not save its own transcript and cannot be restored later.
- **Tell "empty" apart from "down".** `sesh` appends `echo __SESH_OK__` after `tmux ls` over ssh. The sentinel means "connected, zero sessions"; its absence means the connect failed. Both return non-zero otherwise, so without it a dead tunnel and an empty server look the same.
- **Do not let a login snapshot erase the pre-shutdown one.** `sesh-save` exits early if system uptime is under 180s. Otherwise the first snapshot after boot (nothing open yet) overwrites the set you had before shutdown, before `sesh-restore` reads it.
- **Same-window `exec` closes the window on exit.** `sesh` replaces its own shell with the launcher by default, so when Claude or `mosh` exits, the window closes. Use `sesh -n` (new window) if you want the window to outlive the session.

## Performance

A cold `sesh` run was about 10s. Roughly 1.6s went to `jq` over the newest 25 transcripts (one was 54 MB). About 9s went to `ssh box tmux ls` over a slow tunnel. Two caches fix it:

- **Local labels** cache to `labels.tsv`, keyed by (transcript path, mtime). An unchanged transcript is never re-parsed. A changed one is re-read, so a label is never stale. A `grep` prefilter keeps even a large changed transcript from a full `jq` parse.
- **The remote list** caches to `remote.list` with a 60s TTL (`SESH_REMOTE_TTL`). When the tunnel is slow or down, the last-known list is served instantly and `sesh` never hangs. A failed connect is remembered for 30s (`SESH_NEG_TTL`). `sesh -r` forces a live refresh.

Warm runs land at about 0.45s.

## Secrets hygiene

- The snapshot holds only session **IDs and directory paths**, never transcript content or credentials.
- Any API key stays in `~/.zshrc.local` (or another file outside the repo). `cc-connect` sources it at runtime, so the key never lands in version control.
- The `~/.ssh/config` block is a local file by design. Keep real internal addresses and key paths out of the public repo.

## Verify and test

Run the test suite (temp `HOME`, fixture transcripts, injected `ssh`, no network):

```bash
bash ~/.dotfiles/bin/tests/sesh.test.sh
# -> # passed 18, failed 0
```

Preview a restore without opening anything:

```bash
SESH_DRYRUN=1 revive        # prints each window it would open
```

Preview an on-demand open:

```bash
SESH_DRYRUN=1 sesh myproj   # prints the action instead of taking it
```

## Flags and environment

| Flag | Env | Effect |
|------|-----|--------|
| `-r` | `SESH_REFRESH=1` | Force a live remote refresh, ignore the TTL |
| `-n` | `SESH_NEWWIN=1` | Open a new window instead of the current one |
| | `SESH_DRYRUN=1` | Print the action instead of taking it |
| | `SESH_REMOTE_TTL` | Remote cache TTL in seconds (default 60) |
| | `SESH_NEG_TTL` | Negative-cache TTL in seconds (default 30) |
| | `SESH_LIST` | Newest-N local transcripts to consider (default 25) |
| | `SESH_CAP` | Max windows `sesh-restore` opens (default 12) |
| | `HX_HOST` | Remote box ssh alias (default `hexane`) |
| | `SESH_SSH` | ssh binary, a test seam |

## Known limitations

Honest edges, so you know what to expect:

- **Login restore must be loaded and verified.** `sesh-restore` is `RunAtLoad`, so it registers at the next login after the symlink exists. Check `launchctl list | grep sesh` and run `revive` by hand if you logged in before installing it.
- **Remote markers go stale on reboot.** A remote session is in the snapshot only while its marker PID is alive. If the box is unreachable at restore (one short probe, no retry), remote entries are skipped; run `revive` once the box is back.
- **Local entries restore first.** With more live local sessions than `SESH_CAP`, remote ones can be cut. Raise `SESH_CAP` if you run many of both.
- **Restore fires at login, not on crash.** After a force-quit or a terminal crash, run `revive` by hand.

## See also

- `docs/superpowers/specs/2026-10-07-sesh-cache-and-same-window-design.md` the design spec for the caching + same-window work.
