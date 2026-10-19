# sesh: Linux auto-save and login restore for foot windows, increment B2 (design)

- **Date:** 2026-10-19.
- **Status:** approved (design); pending implementation plan.
- **Increment:** B2 of the hexane-native work. B1 (`sesh` runs on hexane) shipped in #58. B2 adds auto-save and login restore on hexane.
- **Depends on:** `master` at `0a723c8`, which includes #58 (the self-contained `sesh/` folder). The suite passes there on hexane: 66 tests, 0 failed.
- **Files (repo):** new `sesh/lib/os.sh`, `sesh/systemd/sesh-save.service` and `sesh/systemd/sesh-save.timer`. Changed `sesh/sesh`, `sesh/sesh-save`, `sesh/sesh-restore`, `sesh/sesh-local`, `sesh/tests/sesh.test.sh`, `sesh/README.md`, `hypr/hyprland.lua` and `ubuntu.conf.yaml`.
- **Unchanged:** `sesh/sesh-remote`, `sesh/launchagents/*`, and every Mac behavior.

## Problem

hexane froze from RAM exhaustion on 2026-10-19 and rebooted. Nothing brought back the Claude Code sessions that were open. The user reopened six of them by hand, one at a time, from the `sesh` picker.

On hexane, each session runs in its own foot window with no tmux: `foot → zsh → [sesh-local] → claude`. The windows live on named per-project workspaces (argo, erp, …) that `hypr-rename` creates ad hoc.

`sesh-save` and `sesh-restore` only run on macOS. They read `sysctl kern.boottime`, open windows with `open -na Ghostty.app`, probe hosts with BSD `nc -G`, and run from LaunchAgents. hexane has no snapshot and no restore trigger. The B1 design deferred this work to B2.

## Goals

1. hexane saves the open Claude sessions every 60 s, with each window's workspace and monitor.
2. When Hyprland starts, each saved session reopens in foot, resumed by ID, on its saved workspace and monitor. Focus stays where it is. This covers a reboot, a logout and a compositor crash.
3. One notification reports what came back and what was skipped.
4. A save never replaces a good snapshot with the empty set seen right after login or a crash.
5. The Mac behaves exactly as today.
6. The test suite drives both OS branches on one machine and passes on hexane and on the Mac.

Non-goals:

- exact tiling splits, floating geometry or focus;
- restoring remote (mosh) windows on Linux;
- non-Claude windows;
- claude inside tmux, which is tmux-resurrect's job (its `tmux.service` and per-pane resume fixes are a separate PR);
- Ghostty on Linux (`SESH_TERMINAL=ghostty` probably works, but no test covers it);
- any change to the Mac's save guard.

## Design

### A. Shared OS layer: `sesh/lib/os.sh`

B1 planned this file under the name `sesh-os.sh`. It holds every OS-specific primitive. `sesh`, `sesh-save` and `sesh-restore` source it. `SESH_UNAME` picks the branch, as in B1.

| Function | macOS | Linux (Hyprland) |
|---|---|---|
| `_mtime <file>` | `stat -f %m` | `stat -c %Y` |
| `_spawn_window <argv…>` | `open -na Ghostty --args -e <argv…>` | `setsid -f ${SESH_TERMINAL:-foot} -e <argv…>` |
| `_alive <pid> <procStart>` | `kill -0` | `kill -0`, and field 22 of `/proc/<pid>/stat` equals `procStart` |
| `_save_gate` | today's 180 s uptime check | section C, step 1 |
| `_capture_windows` | prints `{}` | section B |
| `_spawn_placed <id> [ws]` | not used: the Mac keeps today's restore loop | section D, step 5 |

Rules for the file:

- Each script finds it through its own resolved path: `readlink -f "${BASH_SOURCE[0]}"`, then `<dir>/lib/os.sh`. GNU and macOS both support `readlink -f` (lorium runs macOS 27.0.1). So a worktree run loads that worktree's copy.
- It must parse under bash 3.2, the Mac's `/bin/bash`. So it uses no associative arrays, no `mapfile` and no `${x,,}`.
- `sesh` drops its inline OS block. Its Linux new-window default changes from alacritty to foot, the `terminal` in hyprland.lua. foot ignores `-e`, so the spawn form stays the same.

B1 kept these functions inline for two reasons. A `dirname`-based sibling source breaks when `sesh` is a file symlink, and bash 3.2 has no `realpath`. `readlink -f` is a separate binary on both systems, so it removes that problem.

### B. Capture: Linux `_capture_windows`

1. Read `hyprctl -j clients` and `hyprctl -j monitors`. Build a map from window PID to address, workspace name, monitor name, `at` and class.
2. For each live session, walk parent PIDs from the claude PID. Field 4 of `/proc/<pid>/stat` gives each parent.
   - If an ancestor's `comm` starts with `tmux`, the walk ends and capture skips the session.
   - The first ancestor PID in the window map is the session's window.
   - If the walk reaches PID 1, the session has no window, and capture skips it.
3. Drop windows with class `scratchpad`. That class is the SUPER+C dropdown, which `hypr-scratch` spawns fresh. Keep windows on `special:stash`.
4. If two windows share one PID (foot server mode), sessions in them get no placement.
5. Print one JSON object keyed by session ID: `{"<id>": {"ws": …, "monitor": …, "at": [x, y]}}`.

### C. Save: `sesh-save`

1. **Gate.** On macOS, run today's uptime check. On Linux, find the live instance with `hyprctl instances -j`. Exit without writing unless there is exactly one instance. Then pass if `snapshot.json` is absent, if its `instance` field is this instance, or if the `restored` file holds this instance's signature. The `instance` rule keeps saves going after a first deploy, before any restore has run. `SESH_SKIP_BOOTGUARD=1` skips the gate on both systems.
2. **Sessions.** Take the registry entries in `~/.claude/sessions/*.json` that have `kind == "interactive"` and pass `_alive`.
3. **Placement.** Merge in the `_capture_windows` output. Add `updated`, which is the registry `updatedAt` in seconds. If `updatedAt` is missing, use the transcript's mtime. Sort `local` by monitor name, then workspace name, then `at` (x first, then y).
4. **Remote markers.** This code is unchanged.
5. **Fail closed.** If any `hyprctl` or `jq` call fails, exit without writing.
6. **Write.** Write atomically: a temp file, then `mv`. If anything except `saved_at` and `updated` changed, also write `history/<UTC timestamp>.json`. Keep the newest 20 history files.

Snapshot format. The Mac neither writes nor reads the new fields.

```json
{"saved_at": "2026-10-19T18:01:08Z", "instance": "<hyprland signature>",
 "local": [{"id": "b8191241-…", "cwd": "/home/vania/Projects/1.Personal/ops/argo-k8s",
            "ws": "argo", "monitor": "DP-1", "at": [0, 52], "updated": 1792432705}],
 "remote": []}
```

State in `~/.local/state/sesh/`: `snapshot.json`, `history/`, `restored`, `restore.log` and the `restore.lock` directory.

### D. Restore: `sesh-restore`

Trigger: `hl.on("hyprland.start")` in hyprland.lua runs `~/.dotfiles/sesh/sesh-restore` after the environment import. `revive` runs it by hand.

1. **Preconditions.** On Linux, exit if `HYPRLAND_INSTANCE_SIGNATURE` is unset. Take the lock: `mkdir restore.lock`, and exit if a live restore holds it. The lock records its owner's PID and start time, so a lock left by a killed restore is taken over. Wait up to 10 s until `hyprctl -j monitors` lists every monitor in the snapshot. Then continue with the monitors that are present.
2. **Cap.** Choose the newest `SESH_CAP` local entries by `updated`. The default is 20 on Linux and stays 12 on the Mac.
3. **Skips.** Skip and log any entry that is already running (`_alive` on a registry match), has no transcript or has a missing cwd. Linux also skips remote entries.
4. **Order.** Spawn the chosen entries in snapshot order. That order groups them by monitor and workspace and sorts each workspace by `at`, so dwindle roughly rebuilds the old split order.
5. **Spawn.** Spawn each entry with one call:
   `hyprctl eval 'hl.dispatch(hl.dsp.exec_cmd("[workspace <target> silent] foot <sesh-dir>/sesh-local --sid <uuid>"))'`
   - The rules never include `monitor`. On Hyprland 0.56.2 that rule moves focus to the monitor and warps the cursor.
   - `<target>` is `name:<ws>` for a named workspace, the bare number for a numbered one, and `special:stash` for the stash.
   - The workspace name gets the Lua escaping that `hypr-rename` uses: `\` becomes `\\`, and `"` becomes `\"`.
   - Only the UUID and fixed paths enter the command string. AI-written titles never pass through Lua or the shell.
   - Spawns are `SESH_STAGGER` seconds apart. The default is 1.5.
6. **Monitor fix.** If a workspace that restore created sits on the wrong monitor, and the saved monitor is present, move the workspace there with `hl.dsp.workspace.move`.
7. **Verify.** Poll the registry for up to 15 s until each spawned ID is running. If a running session's window is on the wrong workspace, move it by address with `hl.dsp.window.move`, as `hypr-rename` does. This step also covers drift in the exec-rule syntax.
8. **Marker.** An `EXIT` trap writes `$HYPRLAND_INSTANCE_SIGNATURE` to `restored` and removes the lock. The trap runs even if nothing opened or a step failed. A dry run writes no marker. Saving resumes from this point.
9. **Notify.** Send one notification through `SESH_NOTIFY`, whose default is `notify-send`. An example: "sesh: restored 12 of 14 (cwd gone 1, didn't start 1)". Ignore notification failures. Write the details to `restore.log`.

On the Mac, today's loop runs unchanged. There is no marker, and the windows open exactly as today.

### E. `sesh-local --sid <uuid>`

This is a new first-argument form for Linux restore.

1. Find `~/.claude/projects/*/<uuid>.jsonl` and read its first `cwd`, as the picker's `_cwd_of` does.
2. Set the title to `claude · <first 8 characters of the uuid>`. Claude replaces the title as soon as it starts.
3. Run the existing path: `cd` to the cwd, falling back to `$HOME` as today, then `ccf --resume <uuid>`.
4. After claude exits, run `exec "${SHELL:-/bin/zsh}" -i`. The window stays open with a shell, like a normal foot window.

The existing `<cwd> <name> <args…>` form stays for the picker and the Mac.

### F. Units and wiring

- `sesh/systemd/sesh-save.service`: `Type=oneshot` and `ExecStart=%h/.dotfiles/sesh/sesh-save`.
- `sesh/systemd/sesh-save.timer`: `OnBootSec=1min`, `OnUnitActiveSec=60s` and `AccuracySec=15s`. This is the pattern of chrome-ws's timer, which already runs on hexane. The unit has no `Condition`. A condition that skips the service leaves `OnUnitActiveSec` with no activation to count from. The script's gate handles the no-Hyprland case.
- `ubuntu.conf.yaml`: link both units into `~/.config/systemd/user/`. Enable the timer only where `Hyprland` is installed, so headless dev boxes skip it.
- `hypr/hyprland.lua`: one `hl.exec_cmd` line in `hyprland.start`.

The unit name matters. tmux-continuum runs `systemctl --user disable tmux.service` on each config load, and that deletes a symlinked `tmux.service`. Nothing on these boxes manages `sesh-save.*`.

### G. Probe results (2026-10-19, Hyprland 0.56.2)

- `hl.dispatch(hl.dsp.exec_cmd("[workspace name:x silent] foot …"))` puts the window on workspace `x` and leaves focus and the cursor alone. A new `x` appears on the focused monitor.
- Adding `monitor DP-1` to those rules creates `x` on DP-1, but it also moves focus to DP-1 and warps the cursor. So restore never uses it.
- `hl.dispatch(hl.dsp.workspace.move({ workspace = "name:x", monitor = "DP-1" }))` moves an inactive workspace without changing focus or the cursor.
- Hyprland ignores unknown keys in dispatcher tables (`bogus_key = 1` returns `ok`), so a misspelled key fails silently. Restore's verify step catches misplaced windows.

## Testing

New seams:

- `SESH_HYPRCTL`: a fake `hyprctl` that serves fixture JSON and logs `eval` calls;
- `SESH_PROC`: a fake `/proc` root;
- `SESH_NOTIFY`: a fake `notify-send`;
- `SESH_STAGGER`: set to 0 in tests.

Existing seams: `SESH_UNAME`, `SESH_DRYRUN` and `SESH_SNAPSHOT`.

1. **Capture.** Fixture clients and monitors, plus a fake `/proc` tree, map claude to its window. Cases: through `sesh-local`, through zsh only, a tmux ancestor (skipped), headless (skipped), class `scratchpad` (skipped), `special:stash` (kept) and a shared window PID (no placement).
2. **Liveness.** A live PID with the wrong `procStart` counts as dead.
3. **Gate.** No instance, two instances or a `restored` mismatch means no write. A missing snapshot or a matching marker means a write.
4. **Fail closed.** If the fake `hyprctl` exits 1 or prints junk, the old snapshot stays intact.
5. **History.** If only `saved_at` or `updated` changed, no history file is added. A changed set adds one. History is pruned to 20.
6. **Order and cap.** Save sorts `local` by monitor, workspace and `at`. Restore picks the newest `SESH_CAP` entries by `updated` and spawns them in snapshot order.
7. **Exec strings** (dry-run): `name:argo silent`, `3 silent`, `special:stash silent`, and a name whose `"` and `\` are escaped. Only the UUID appears in the argv.
8. **Skips.** Already running, no transcript, missing cwd and remote on Linux. Each one is logged.
9. **Marker and lock.** The marker is written when nothing opened and after a failed spawn. It is not written without `HYPRLAND_INSTANCE_SIGNATURE`. A second run exits while the lock exists, and the trap removes the lock.
10. **Fixes.** When the fake `hyprctl` reports the wrong monitor or workspace, restore issues the matching move `eval`.
11. **Notification.** The text includes the skip counts.
12. **`sesh-local --sid`.** It resolves the cwd from the transcript and falls back to `$HOME`. After claude exits, it runs the shell.
13. **Regression.** The 66 existing tests stay green. Four change on purpose. Two Linux spawn tests now expect foot instead of alacritty. The two remote-restore tests pin `SESH_UNAME=Darwin`, because Linux restore skips remote entries.

## Edge cases

- **Stale registry after a reboot.** Leftover files can name PIDs that early-boot processes reuse. The `procStart` check in `_alive` rejects them.
- **Compositor crash without a reboot.** The new instance differs from `restored`, so saves wait until restore runs.
- **Restore dies midway.** The trap still writes the marker. The pre-crash snapshot is already in `history/`.
- **Two restores at once,** for example `revive` during the login restore. The lock makes the second one exit.
- **Saved monitor unplugged.** The workspace stays where Hyprland created it.
- **earlyoom kills some sessions.** `SESH_SNAPSHOT=~/.local/state/sesh/history/<ts>.json revive` reopens only the missing ones, because restore skips sessions that are running.
- **Window rules.** Restored windows keep the app ID `foot`, so existing foot rules still apply.

## Verification

1. `bash sesh/tests/sesh.test.sh` reports `failed 0` on hexane and on the Mac.
2. On hexane, `systemctl --user list-timers sesh-save.timer` shows the timer. Within a minute, `snapshot.json` lists the open foot sessions. Their workspaces and monitors match `hyprctl clients`.
3. `SESH_DRYRUN=1 revive` prints one spawn per session, with the right targets.
4. Log out of Hyprland and back in. Each window returns to its workspace and monitor. There are no duplicates, and the notification is correct. `restored` holds the new instance, and saves resume.
5. A real reboot gives the same result.
6. On the Mac, `launchctl list | grep sesh` is unchanged, and `SESH_DRYRUN=1 revive` matches the pre-B2 output.
7. The de-slop lint shows 0 hard findings on this spec and on the PR text.

## Rollout

- The work happens on branch `feat/sesh-linux-b2` in the worktree `~/.dotfiles/.claude/worktrees/sesh-linux-b2`, because other sessions share the main checkout. One PR goes to `master`, and the review bots check it through `prbots`.
- After the merge, hexane pulls. A full `./install` on hexane runs `sudo pacman`, and this box has no passwordless sudo. So the rollout links and enables the units directly, and it hands any sudo step to the user.
- The first save on hexane passes the gate, because no snapshot exists yet. The restore hook first runs at the next Hyprland start.
- `sesh/README.md` gains a Linux section. Its known-limitations list notes that Linux restore also runs after a compositor crash.
