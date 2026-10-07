# sesh: caching + same-window opening — design

**Date:** 2026-10-07
**Status:** approved (design); pending implementation
**Files:** `~/.dotfiles/bin/sesh`, `Host hexane` block in `~/.ssh/config` (local, not dotfiles-managed)
**Unchanged:** `sesh-restore`, `sesh-save`, `cc-connect`, `hx-connect` — restore legitimately needs one window per session.

## Problem

Every `sesh` invocation re-derives the whole candidate list from scratch:

- **Local labels: ~1.6s** — `jq` re-parses the newest 25 transcripts (~130 MB; one is 54 MB) on every run. CPU-bound; slow whether at home or on a plane.
- **Remote list: ~9s** — `ssh hexane tmux ls`. Measured `nc -z 10.3.33.1:22` ≈ 9s on its own, so the cost is the *network path* (airplane wifi → tunnel → homelab LAN), not ssh auth or the server. It is paid even for `sesh <query>`, where the target is already known, and it hangs when the tunnel is down.

Also: `sesh` always spawns a **new** Ghostty window (`open -na`). That is inherited from multi-session restore, not required by titling — titles come from an OSC escape (`\033]0;…\007`) that applies to whatever terminal runs it.

## Goals

1. Avoid the full re-derivation on every run, without ever showing a wrong label.
2. Keep `sesh` usable at high latency / fully offline (never hang on a dead tunnel).
3. Open the picked session in the **current** window by default; keep a new-window escape hatch.
4. Amortize the ssh connection cost across calls.

Non-goals: changing restore/snapshot behavior; changing `cc-connect`/`hx-connect` internals; fixing anything server-side on hexane.

## Design

### A. Same-window by default
`do_open` stops using `open -na "$GHOSTTY" --args -e "$@"` and instead `exec "$@"` in the current window.

- Titling is unaffected — the OSC escape titles the current terminal.
- `hx-connect`'s presence-marker/trap still work: `exec` replaces `sesh`'s shell with `hx-connect`'s own `bash`, which writes its marker, sets the trap, and runs `mosh` as a **child** (not `exec`'d), so the trap fires on return as before.
- `cc-connect` likewise runs as the replacement process; `ccf`/`claude` run as its child.

Behavioral change: `sesh` now **replaces the shell it was launched from**. Escape hatch: `sesh -n <q>` / `SESH_NEWWIN=1` forces the old new-window (`open -na`) path. `SESH_DRYRUN=1` keeps printing instead of acting, and prints which path (`exec here` vs `new window`) it would take.

### B. Local label cache (mtime-keyed) — kills the 1.6s
Cache file `~/.local/state/sesh/labels.tsv`, one row per transcript:

```
<jsonl_path>\t<mtime_epoch>\t<cwd>\t<name>
```

Per run, in the local branch of `candidates()`:
1. `ls -t` the newest `N` (`SESH_LIST`, default 25) `*.jsonl` — cheap stat only.
2. For each file, `stat -f %m` its mtime. If a prior row exists for that exact `path` **and** mtime matches → reuse cached `cwd` + `name`. Otherwise recompute (`cwd` + `name_of`) and record the new row.
3. Write the rebuilt table atomically (`tmp` + `mv`). Rebuilding from the current `N` naturally prunes vanished files.
4. Emit the candidate row as today: `local\t<id>\t<path>\t[local] <name> — <basename cwd>` (`id` = `basename path .jsonl`, cheap).

Correctness: a transcript that grew (mtime bumped) is re-parsed → label always current; idle transcripts are served from cache. Typical run ~1.6s → ~0.1s.

**`grep`-prefilter in `name_of`** (add-on, approved): avoid full-file `jq` parses on the files that *do* need recompute (e.g. the active 54 MB transcript):
- ai-title: `grep -a '"type":"ai-title"' "$f" | tail -1 | jq -rc 'select(.type=="ai-title")|.aiTitle'`
- first user msg (fallback): `grep -a -m1 '"type":"user"' "$f" | jq …` (`-m1` stops at first match)
- cwd: `grep -a -m1 '"cwd"' "$f" | jq -rc 'select(.cwd!=null)|.cwd'`

Empty grep → empty jq input → falls through to the short-id default, same as today.

### C. Remote TTL cache + offline fallback — tames the 9s
Cache file `~/.local/state/sesh/remote.list` (one session name per line); freshness = its mtime. Negative-cache marker `~/.local/state/sesh/remote.fail`.

Tunables: `SESH_REMOTE_TTL` (default 60s), negative-cache TTL 30s (`SESH_NEG_TTL`).

Remote branch of `candidates()`:
1. Decide whether to attempt ssh:
   - `-r`/`SESH_REFRESH` → always attempt;
   - else remote cache age < TTL → use cache, **skip** ssh;
   - else `remote.fail` age < NEG_TTL → recent failure, **skip** ssh, use stale cache;
   - else → attempt ssh.
2. Attempt = distinguish *connect failure* from *connected, zero sessions* using a sentinel:
   ```
   raw=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "$HOST" \
         'tmux ls -F "#{session_name}" 2>/dev/null; echo __SESH_OK__')
   ```
   - `raw` contains `__SESH_OK__` → connected: write the lines before the marker (possibly empty) to `remote.list` atomically; `rm -f remote.fail`.
   - otherwise → connect failed: `touch remote.fail`; keep the existing (stale) `remote.list`.
3. Emit a row per non-empty cached line: `remote\t<s>\t\t[hexane] <s>`.

Result: on a plane with a slow/down tunnel, `sesh` serves the last-known hexane list **instantly** and never hangs beyond one 5s timeout per NEG_TTL window; `sesh -r` forces truth when wanted. First run ever with no cache + no connectivity shows no remote rows (correct).

### D. SSH multiplexing
Append to the existing `Host hexane` block in `~/.ssh/config`:

```
    ControlMaster auto
    ControlPath ~/.ssh/sockets/%C
    ControlPersist 10m
```

Plus `mkdir -p ~/.ssh/sockets && chmod 700 ~/.ssh/sockets`. First connect still pays the ~9s TCP setup; subsequent `tmux ls` refreshes and plain `ssh hexane` within 10 min reuse one connection. `mosh` does not use the control socket (unaffected). Edit is idempotent (guard on `ControlMaster` already present in the block).

## Flags / env summary

| Flag | Env | Effect |
|------|-----|--------|
| `-r` | `SESH_REFRESH=1` | Force a live remote refresh (ignore TTL) |
| `-n` | `SESH_NEWWIN=1` | Force a new Ghostty window (old behavior) |
| — | `SESH_DRYRUN=1` | Print the action instead of taking it |
| — | `SESH_REMOTE_TTL` | Remote cache TTL, seconds (default 60) |
| — | `SESH_NEG_TTL` | Negative-cache TTL, seconds (default 30) |
| — | `SESH_LIST` | Newest-N local transcripts (default 25) |

State dir: `~/.local/state/sesh/` (`labels.tsv`, `remote.list`, `remote.fail`) — created with `mkdir -p`.

## Edge cases

- **SIGPIPE on early match** (`sesh <query>` via `awk … exit`): each section fully computes and atomically writes its cache *before* printing its rows, so an early exit can only skip refreshing the remote cache, never corrupt a cache. The fzf path reads all rows (no early exit).
- **Atomic writes**: all cache writes are `tmp`+`mv`; an interrupted write leaves the previous cache intact.
- **mtime granularity** (1s): acceptable; a second write within the same second to an unchanged-size file is the only theoretical miss and is harmless (just a recompute).
- **Empty tmux / no server**: sentinel distinguishes it from a dead tunnel; cache is written empty, so stale sessions don't linger.

## Verification

- Before/after: `time SESH_DRYRUN=1 sesh <query>` (expect ~10s cold → ~0.1s warm).
- Scripted (temp `HOME`/state + fixture `*.jsonl`, no network needed):
  1. Local cache hit — second run reuses labels (no recompute) and matches first.
  2. Changed transcript — appending bumps mtime → label recomputed.
  3. Remote stale fallback — point `HX_HOST` at an unreachable host with a pre-seeded `remote.list` → stale rows still emitted, `remote.fail` created.
  4. `-n` dry-run shows the `open -na` path; bare dry-run shows the `exec` path.
- Manual (scratch window): `sesh <local>` opens in-place (shell replaced by claude), window titled.

## Rollout note

`~/.dotfiles/bin/sesh` is currently **untracked** and the repo has an unresolved `claude/settings.json` conflict (`UU`). Implementation edits join that pending set; committing the scripts (and this spec) waits on the user resolving that conflict. The `~/.ssh/config` edit is a plain local file — independent of the dotfiles repo.
