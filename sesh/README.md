# Remote + local session restore (`sesh`)

`sesh` reopens the terminal sessions you had open, after a reboot or a laptop sleep, without a list you maintain by hand. It covers three kinds of work at once:

- **Local** Claude Code sessions on your Mac, resumed in their own directory.
- **Remote** `tmux` sessions on a box you reach over `mosh`, reattached in place.
- **Linux desktop** Claude sessions in foot windows on Hyprland, reopened on their own workspaces. See [Linux (Hyprland)](#linux-hyprland-auto-save-and-restore).

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

1. **The working set is live state, not a list.** A background job snapshots whatever is open every two minutes (every minute on Linux). Restore replays that snapshot. There is nothing to edit.
2. **One small launcher per session type.** A local session and a remote session open differently, so each has its own launcher script (`sesh-local`, `sesh-remote`). Everything else calls those two.
3. **The terminal is the state store.** Session identity, titles, and directory all come from the running session (the Claude transcript on disk, the `tmux` session name), so the snapshot holds only pointers (IDs and paths, plus window placement on Linux), never content.

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

The diagram shows the macOS flow. On Linux a systemd timer runs `sesh-save` every 60 s, and Hyprland runs `sesh-restore` at start, with foot windows. See [Linux (Hyprland)](#linux-hyprland-auto-save-and-restore).

The three verbs:

| Command | Role | Trigger |
|---------|------|---------|
| `sesh-save` | Snapshot the live set to `snapshot.json` | LaunchAgent every 120 s (macOS), systemd timer every 60 s (Linux) |
| `sesh-restore` (alias `revive`) | Rebuild the snapshot as windows | LaunchAgent at login (macOS), Hyprland start (Linux), or by hand |
| `sesh [-r] [-n] [query]` | Pick/open a session on demand | You |

State lives in `~/.local/state/sesh/`:

- `snapshot.json` the last live set.
- `remote/<session>` a presence marker (a PID) written by `sesh-remote` while a remote session is open.
- `labels.tsv` cached local labels, keyed by transcript path + mtime.
- `remote.list`, `remote.fail` the cached remote session list and a negative-cache marker.
- `restore.log`, `save.err.log` logs.
- `history/` (Linux) the last 20 distinct snapshots.
- `restored` (Linux) the Hyprland instance whose restore finished. The save gate reads it.
- `restore.lock/` (Linux) exists while a restore runs.
- `spawn.err` (Linux) errors from windows the picker opens.

## The pieces (file map)

| File | What it does |
|------|--------------|
| `sesh/sesh` | On-demand picker/opener over local + remote sessions. Sourceable; has a test suite. |
| `sesh/lib/os.sh` | OS-specific primitives the three scripts share: window spawn, liveness, Hyprland capture and placement, the save gate. |
| `sesh/systemd/sesh-save.{service,timer}` | Linux: runs `sesh-save` every 60 s. |
| `hypr/hyprland.lua` | Linux: runs `sesh-restore` at Hyprland start. |
| `sesh/sesh-save` | Snapshots live local (PID-checked) + remote (marker) sessions to `snapshot.json`. On Linux it also records each window's workspace and monitor. |
| `sesh/sesh-restore` | Rebuilds the snapshot as windows: Ghostty at login on macOS, placed foot windows at Hyprland start on Linux. Skips live ones; caps the count. |
| `sesh/sesh-local` | Launcher for a **local** Claude session: `cd`, set title, resume Claude. `--sid <uuid>` is the Linux restore form. |
| `sesh/sesh-remote` | Launcher for a **remote** session: write marker, set title, `mosh box -- tmux new-session -A -s <name>`. |
| `sesh/tests/sesh.test.sh` | 192 tests (cache, multi-host, self-detection, Linux save and restore). Fakes `ssh`, `hyprctl` and `/proc`, so nothing live is touched. |
| `sesh/launchagents/localhost.sesh-save.plist` | Runs `sesh-save` every 120s. |
| `sesh/launchagents/localhost.sesh-restore.plist` | Runs `sesh-restore` once at login (`RunAtLoad`). |
| `ghostty/config` | `window-save-state = never` (see gotchas) and the theme. |
| `zsh/aliases/utilities.zsh` | `revive` alias and the `title()` helper. |
| `~/.ssh/config` | The `Host` block for your box, with connection multiplexing. **Local file, not in this repo.** |

## Worked example: Ivan's setup (hexane + ccf)

This is how the example machine is wired. Read it as "one concrete instance," then swap the marked parts.

- **Remote box**: an ssh alias `hexane` on the home LAN, reached over `mosh`. It runs about 16 per-project `tmux` sessions named like `cc-argo`, `cc-pinley`.
- **Local launcher**: `sesh-local` runs Claude through `ccf`, a shell function that adds API-key routing and `--dangerously-skip-permissions`. `ccf` lives in `~/.zshrc.local`, a machine-local file that holds the key. It is **not** in the dotfiles repo. `sesh-local` sources it at runtime and falls back to plain `claude` if it is absent.
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

2. **The box name(s) in the scripts**: for a single remote box the scripts read `SESH_HOST` (default `hexane`) — name your ssh alias `hexane`, or export `SESH_HOST=mybox` in your shell, or edit the default in `sesh/sesh`, `sesh/sesh-restore`, `sesh/sesh-remote`. For **several** boxes, set `SESH_HOSTS="box1 box2 box3"` (or list them one per line in `~/.config/sesh/hosts`) and the picker queries every one; `SESH_HOST` is the single-box fallback when neither is set.

3. **The local launcher** (`sesh/sesh-local`): if you do not use a key-routing wrapper, delete the `ccf` branch and run Claude directly:

   ```bash
   cd "$cwd" 2>/dev/null || cd "$HOME"
   exec "$HOME/.local/bin/claude" --resume "$@"
   ```
   Keep the key, if you have one, in `~/.zshrc.local` (or any file outside the repo), never in `sesh-local`.

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

## Linux (Hyprland): auto-save and restore

On a Hyprland desktop, `sesh` saves the Claude sessions open in terminal windows and reopens them when Hyprland starts. That covers a reboot, a logout and a compositor crash. Each session comes back in a foot window, resumed by ID, on the workspace and monitor it had. Focus does not move.

How it works:

1. `sesh-save.timer` runs `sesh-save` every 60 s. For each live interactive Claude session, `sesh-save` walks parent PIDs up to a PID that `hyprctl clients` lists. That window gives the workspace, monitor and position.
2. At Hyprland start, `hyprland.lua` runs `sesh-restore`. It sets aside the sessions that are running, then opens the newest `SESH_CAP` of the rest (default 20), 1.5 s apart, through `[workspace <ws> silent]` exec rules. Then it moves any workspace it created to the saved monitor and sends one notification. A workspace name with a space, [, ] or ; cannot sit in an exec rule, so that window opens on the hidden special:sesh-stage and restore moves it into place by address. If a window is still on the stage after that, because its session started late or not at all, restore finds the session from the `--sid` in the window's command line and moves the window to its saved workspace. A window it cannot match moves to the active workspace.
3. A gate protects the snapshot. `sesh-save` writes only when exactly one Hyprland instance is live and one of these holds: there is no snapshot yet, that instance wrote the snapshot, or that instance finished its restore. So a save right after login or a crash cannot replace your sessions with an empty set.

Not restored: the SUPER+C scratchpad, claude inside tmux (tmux-resurrect's job), headless sessions and remote (mosh) windows.

Install on a Hyprland box:

1. `./install` links `sesh/systemd/sesh-save.{service,timer}` into `~/.config/systemd/user/`, and it enables the timer when `Hyprland` is installed. To do it by hand, link the two files, then run `systemctl --user daemon-reload && systemctl --user enable --now sesh-save.timer`.
2. `hypr/hyprland.lua` already runs `sesh-restore` inside `hl.on("hyprland.start", …)`.

Check it:

- `systemctl --user list-timers sesh-save.timer` shows the timer.
- `jq '.local[] | {id, ws, monitor}' ~/.local/state/sesh/snapshot.json` lists the saved sessions and their workspaces.
- `SESH_DRYRUN=1 revive` prints the windows a restore would open, then a summary line with the skip counts.
- `~/.local/state/sesh/restore.log` records each restore.

Recover sessions that died without a reboot, for example after earlyoom killed a few:

1. Pick a file in `~/.local/state/sesh/history/`, which keeps the last 20 distinct snapshots.
2. Run `SESH_SNAPSHOT=<that file> revive`. Restore skips sessions that are running, so only the missing ones open.

If saves stop after a Hyprland restart, the restore for that instance never ran. Run `revive` once.

If the notification says `still staged N`, a window could not be moved off the hidden stage. Show the stage with `hyprctl eval 'hl.dispatch(hl.dsp.workspace.toggle_special("sesh-stage"))'` and move the window by hand.

## Gotchas that cost us hours

Each of these was a real bug. They are the reason the scripts look the way they do.

- **Ghostty phantom windows.** Set `window-save-state = never`. With the default, every `open -na Ghostty --args ...` also **restores** the previous windows on top, so each restore spawns empty duplicates. This, not `--initial-window=false` (a red herring), was the fix.
- **Pass the launcher as clean argv.** Restore opens a window with `open -na Ghostty --args -e <launcher> <args>`. An inline `-e /bin/sh -c "..."` gets its quoting mangled by `open --args` and the window falls back to a bare login shell. A standalone launcher script (`sesh-local`, `sesh-remote`) takes clean arguments. Ghostty's `-e prog a b c` does preserve spaced args (verified).
- **`--title=` as a launch flag aborts the launch.** Set the title with an OSC escape inside the launcher instead: `printf '\033]0;%s\007' "$name"`.
- **`mosh` strips OSC 52.** Window-title OSC still passes, so titles work. Copying text from a remote `tmux` to the Mac clipboard over `mosh` can fail. Use a native terminal selection, or switch the transport to Eternal Terminal (TCP, keeps OSC 52) if clipboard matters more than sleep-survival.
- **`mosh` needs a UTF-8 locale on the server.** mosh-server refuses to start unless the remote box has a real UTF-8 locale, because your client forwards `LC_ALL`/`LANG` and the server must honor it. A minimal server image can lack it, or even lack the `locales` package. The failure looks like `mosh: Did not find mosh server startup message` after a wall of `setlocale` warnings. Diagnose with `ssh box 'LC_ALL=en_US.UTF-8 locale charmap'` (you want `UTF-8`, not `US-ASCII` / `ANSI_X3.4-1968`). Fix on the box: `sudo apt-get install -y locales && sudo locale-gen en_US.UTF-8`, matching the locale your client sends.
- **LaunchAgents get a minimal `PATH`.** Each script sets its own `PATH` and calls Claude by absolute path (`~/.local/bin/claude`). A LaunchAgent will not find a tool on your interactive shell `PATH`.
- **The Claude project slug is lossy.** `~/.claude/projects/<slug>/` collapses dotted paths, so the real working directory is read from inside the session's `.jsonl` (`.cwd`), not from the slug.
- **Spawning a window from inside Claude.** `sesh-local` unsets `CLAUDE_CODE_CHILD_SESSION`, or the child session does not save its own transcript and cannot be restored later.
- **Tell "empty" apart from "down".** `sesh` appends `echo __SESH_OK__` after `tmux ls` over ssh. The sentinel means "connected, zero sessions"; its absence means the connect failed. Both return non-zero otherwise, so without it a dead tunnel and an empty server look the same.
- **Do not let a login snapshot erase the pre-shutdown one.** On macOS, `sesh-save` exits early if system uptime is under 180s. Otherwise the first snapshot after boot (nothing open yet) overwrites the set you had before shutdown, before `sesh-restore` reads it. On Linux the save gate does this job (see the Linux section).
- **Same-window `exec` closes the window on exit.** `sesh` replaces its own shell with the launcher by default, so when Claude or `mosh` exits, the window closes. Use `sesh -n` (new window) if you want the window to outlive the session.

## Performance

A cold `sesh` run was about 10s. Roughly 1.6s went to `jq` over the newest 25 transcripts (one was 54 MB). About 9s went to `ssh box tmux ls` over a slow tunnel. Two caches fix it:

- **Local labels** cache to `labels.tsv`, keyed by (transcript path, mtime). An unchanged transcript is never re-parsed. A changed one is re-read, so a label is never stale. A `grep` prefilter keeps even a large changed transcript from a full `jq` parse.
- **The remote list** caches to `remote.list` with a 60s TTL (`SESH_REMOTE_TTL`). When the tunnel is slow or down, the last-known list is served instantly and `sesh` never hangs. A failed connect is remembered for 30s (`SESH_NEG_TTL`). `sesh -r` forces a live refresh.

Warm runs land at about 0.45s.

## Secrets hygiene

- The snapshot holds only session **IDs and directory paths**, plus workspace names, monitor names and window positions on Linux. It never holds transcript content or credentials.
- Any API key stays in `~/.zshrc.local` (or another file outside the repo). `sesh-local` sources it at runtime, so the key never lands in version control.
- The `~/.ssh/config` block is a local file by design. Keep real internal addresses and key paths out of the public repo.

## Verify and test

Run the test suite (temp `HOME`, fixture transcripts, injected `ssh`, no network):

```bash
bash ~/.dotfiles/sesh/tests/sesh.test.sh
# -> # passed 192, failed 0
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
| | `SESH_CAP` | Max windows `sesh-restore` opens (default 12 on macOS, 20 on Linux) |
| | `SESH_HOSTS` | Space-separated boxes the picker queries (else `~/.config/sesh/hosts`, else `SESH_HOST`) |
| | `SESH_HOST` | Single remote box: picker fallback & `sesh-remote` default (default `hexane`) |
| | `SESH_SSH` | ssh binary, a test seam |
| | `SESH_TERMINAL` | Linux terminal for a new window (default foot) |
| | `SESH_STAGGER` | Linux: seconds between restored windows (default 1.5) |
| | `SESH_VERIFY_WAIT` | Linux: whole seconds restore waits for windows to start (default 15) |
| | `SESH_MON_WAIT` | Linux: 0.2 s polls restore waits for the saved monitors (default 50) |
| | `SESH_SNAPSHOT` | Restore from this file instead of `snapshot.json` |
| | `SESH_SKIP_BOOTGUARD` | Skip the save gate (manual runs and tests) |
| | `SESH_HYPRCTL`, `SESH_PROC`, `SESH_NOTIFY`, `SESH_UNAME` | Test seams: `hyprctl` binary, `/proc` root, notifier, OS |
| | `SESH_TEST_ONLY` | Run only the named tests in the suite |

## Known limitations

Honest edges, so you know what to expect:

- **Login restore must be loaded and verified.** `sesh-restore` is `RunAtLoad`, so it registers at the next login after the symlink exists. Check `launchctl list | grep sesh` and run `revive` by hand if you logged in before installing it.
- **Remote markers go stale on reboot.** A remote session is in the snapshot only while its marker PID is alive. If the box is unreachable at restore (one short probe, no retry), remote entries are skipped; run `revive` once the box is back.
- **Local entries restore first.** With more live local sessions than `SESH_CAP`, remote ones can be cut. Raise `SESH_CAP` if you run many of both.
- **macOS restore fires at login, not on crash.** After a force-quit or a terminal crash, run `revive` by hand. On Linux, restore runs at every Hyprland start, so a compositor crash is covered. A single foot window that dies is not reopened, and a plain `revive` cannot bring it back, because the next save (within 60 s) drops it from `snapshot.json`. Reopen it with the `sesh` picker, or from `history/` as the Linux section describes.
- **A fast re-login on Linux.** A login restore runs for up to about a minute. If you log out and back in while it still runs, the new restore can find its lock and exit. Saves then stay off until you run `revive` once.
- **Sessions saved without a workspace open where you are.** A session from a shared foot server window, or one saved while it sat on the stage, has no saved workspace. It reopens on the active workspace and takes focus.

## See also

- the full design history lives in `sesh/docs/`: caching + same-window, multi-host, the hexane-native (B1) work, and the Linux auto-save and restore (B2) design and plan (`2026-10-19-sesh-linux-b2-design.md`, `2026-10-19-sesh-linux-b2.md`).
