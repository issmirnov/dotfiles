# sesh: multi-host remote sessions (design)

- **Date:** 2026-10-13.
- **Status:** approved design, pending implementation.
- **Increment:** A of 3 (A: Mac sesh multi-host; B: hexane native sesh; C: dev reboot parity).
- **Files (repo):** `bin/sesh`, `bin/sesh-save`, `bin/sesh-restore`, `bin/hx-connect`, `bin/tests/sesh.test.sh`.
- **Files (local, not repo):** `~/.ssh/config` (dev-1/2/3 blocks), `~/.config/sesh/hosts` (optional).
- **One-time, on the boxes:** `mosh` installed on dev-1/2/3.
- **Unchanged:** `cc-connect`, the local-Claude candidate path, the caching model, the same-window `exec` default.

## Problem

The Mac's `sesh` reaches exactly one remote box. `HX_HOST` (default `hexane`) is the only host the picker queries, the only host `hx-connect` reaches, and the only host the snapshot and restore understand. The user runs tmux sessions on four boxes: `hexane` and `dev-1`/`dev-2`/`dev-3`. Three of them (the dev boxes) are headless Ubuntu servers, so the Mac is the only place their sessions can be picked or restored.

Two facts from a live survey (2026-10-13) shape the design:

- The dev boxes are headless (`XDG_SESSION_TYPE=tty`, no GUI terminal). They already carry tmux-resurrect + continuum + systemd units, so their sessions survive a box reboot on their own.
- The dev boxes do **not** have `mosh-server` installed; `hexane` does. `tmux`, `fzf`, and `jq` are present on all four.

## Goals

1. The Mac picker lists local Claude sessions plus tmux sessions from every configured box.
2. Opening a remote pick reaches the right box over mosh.
3. Mac-login restore reopens the remote sessions you had open on any box, over mosh, surviving laptop sleep.
4. A slow or unreachable box never blocks the picker.
5. The 18 existing tests keep passing; new behavior gets new tests.

Non-goals: running `sesh` on the boxes (increment B); changing the local-Claude path; changing dev-box reboot persistence (increment C); any server-side change beyond installing mosh.

## Design

The whole increment threads one new dimension, the **host**, through the rows, the markers, and the snapshot. Only the picker needs the host list; the other scripts carry a host they already hold.

### A. Host list (picker only)

`bin/sesh` gains a `_hosts()` helper. Resolution order:

1. `SESH_HOSTS` env (space- or newline-separated), if set.
2. `~/.config/sesh/hosts`, if present: one host per line, `#` comments, blank lines ignored.
3. Built-in default: `hexane dev-1 dev-2 dev-3`.

`sesh-save` and `sesh-restore` do **not** read this list. A marker already names its host; a snapshot entry already names its host.

### B. Picker: per-host candidates, queried in parallel

Replace the single-host remote branch of `candidates()` with two phases:

1. **Refresh (network, parallel).** For each host, a `_refresh_remote <host>` runs in the background and writes only cache files. It keeps today's decision logic per host: force on `SESH_REFRESH`; else skip when `remote.<host>.list` is within its `SESH_REMOTE_TTL` window; else skip when `remote.<host>.fail` is within `SESH_NEG_TTL`; else query the box. A query runs:

   ```
   "${SESH_SSH:-ssh}" -o ConnectTimeout=5 -o BatchMode=yes "$host" \
     'tmux ls -F "#{session_name}" 2>/dev/null; echo __SESH_OK__'
   ```
   On a reply containing `__SESH_OK__`: write the lines before the sentinel to `remote.<host>.list` atomically (`tmp`+`mv`), remove `remote.<host>.fail`. Otherwise: `touch remote.<host>.fail` and keep the stale list. After launching all hosts, `wait`.

2. **Emit (cheap, ordered).** For each host in list order, read `remote.<host>.list` and print one row per session:

   ```
   remote <TAB> <session> <TAB> <host> <TAB> [<host>] <session>
   ```

Field 3 (empty for remote today) now carries the host. Local rows are unchanged; their field 3 stays the transcript path. The parallel network and serial emission keep the output order stable. They also keep the slowest box off the critical path, bounded by one 5s `ConnectTimeout`.

### C. Open and transport (`hx-connect`)

New contract: `hx-connect <host> <session>`. One-argument calls still work (`hx-connect <session>` treats the arg as the session and the host as `${HX_HOST:-hexane}`), so nothing that calls the old form breaks.

- Presence marker moves under a per-host directory, so two boxes with the same session name cannot collide:
  ```
  ~/.local/state/sesh/remote/<host>/<session>      (was: remote/<session>)
  ```
  Write this process's PID, `trap 'rm -f "$MARK"' EXIT INT TERM HUP` as today.
- Title with `printf '\033]0;%s:%s\007' "$host" "$sess"` until tmux set-titles takes over.
- Transport unchanged in form: `mosh "$host" -- tmux new-session -A -s "$sess"`.

`sesh`'s opener calls `do_open "$HX_CONNECT" "$host" "$session"` for a remote pick; `sesh-restore` calls `hx-connect "$host" "$session"`.

### D. Snapshot and restore

Snapshot schema gains the host:

```
snapshot.json   remote: [ { "host": "<host>", "session": "<session>" }, ... ]
                                                  (was: [ { "session": "<session>" } ])
```

`sesh-save`: walk `remote/<host>/<session>` (host directory, then marker). Prune a marker whose PID is dead. Emit `{host, session}` for the survivors. Legacy flat files directly under `remote/` are ignored and removed (they predate host-namespacing and are stale PIDs anyway).

`sesh-restore`: read each entry as `[(.host // "hexane"), .session]`, so an old bare-session snapshot still restores (host defaults to `hexane`). Per entry: check `reachable <host>` (resolve `ssh -G <host>` to IP+port, `nc -z`), skip with a log line if the box is down, skip if `remote_open <host> <session>` finds a live marker, else `openwin "$HX_CONNECT" "$host" "$session"`. The `SESH_CAP` limit is unchanged.

### E. One-time setup (outside the repo)

- Install mosh on the dev boxes: `sudo apt install -y mosh` on dev-1, dev-2, dev-3. (Confirm before running sudo on the boxes.)
- Add connection multiplexing to the dev-1/2/3 blocks in `~/.ssh/config` (hexane already has it):
  ```
  ControlMaster auto
  ControlPath ~/.ssh/sockets/%C
  ControlPersist 10m
  ```
  `~/.ssh/sockets` already exists from the hexane setup.

## Decided points

- `sesh <query>` keeps first-match semantics. A session name present on more than one box is disambiguated by including the host in the query (`sesh dev-1`), since the label carries `[<host>]`. It does not force a box name.
- The host list is the one curated list in the system. It is small and stable (your boxes), unlike the per-session lists retired on 2026-10-06.

## Flags / env (additions)

| Env | Effect |
|-----|--------|
| `SESH_HOSTS` | Space/newline host list; overrides the file and the default |

Unchanged and now applied per host: `SESH_REFRESH` (`-r`), `SESH_REMOTE_TTL` (default 60), `SESH_NEG_TTL` (default 30). Cache files become per-host: `remote.<host>.list`, `remote.<host>.fail`. State dir unchanged: `~/.local/state/sesh/`.

## Edge cases

- **Session-name collision across boxes.** Handled: host-namespaced markers, host in the row, `[<host>]` label.
- **One box down at picker time.** Its `_refresh_remote` fails, `remote.<host>.fail` is touched, its last-known list is served, other hosts are unaffected.
- **One box down at restore time.** `reachable` fails for that host only; its sessions are logged and skipped; `revive` later reopens them.
- **Old snapshot format.** `.host // "hexane"` default restores a pre-change snapshot through the one straddling cycle.
- **Legacy flat markers.** Ignored and pruned by `sesh-save`.
- **Atomic writes.** All per-host cache writes stay `tmp`+`mv`; an interrupted refresh leaves the previous list intact.

## Testing (extend `bin/tests/sesh.test.sh`)

The suite already sources `sesh` as a library and injects `ssh` via `SESH_SSH`. Add a fake `ssh` that branches on the host argument (it receives `<host>` in its argv), plus `SESH_HOSTS` set to two fake hosts:

1. **Multi-host emission.** Both hosts' sessions appear, each row with the correct `[<host>]` label and host field 3.
2. **Per-host offline fallback.** Host A stale list is served while host B refreshes; A's `remote.A.fail` is created, B's list updates.
3. **Marker round-trip.** A host-namespaced marker is read by the save shape into `{host, session}`.
4. **Back-compat restore.** A snapshot with bare `{session}` yields host `hexane`.

Keep the existing 18 green; target the new ones at the per-host functions.

## Verification

- `bash bin/tests/sesh.test.sh` reports `passed N, failed 0` (N = 18 + new).
- `SESH_DRYRUN=1 sesh <dev-1-session>` prints the `hx-connect dev-1 <session>` action.
- `SESH_DRYRUN=1 revive` lists remote windows across hosts after a snapshot that spans boxes.
- `time sesh` warm run stays near the current ~0.45s (per-host caches hit); a down box does not add more than one 5s timeout.
- de-slop lint clean (0 hard) on this spec and the commit/PR text.

## Rollout

Single branch and PR on `issmirnov/dotfiles`. The script changes and tests land together. The `~/.ssh/config` edit and the mosh installs are local/box-side and independent of the repo. Increments B and C get their own specs.
