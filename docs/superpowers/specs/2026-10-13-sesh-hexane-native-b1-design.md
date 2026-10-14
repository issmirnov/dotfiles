# sesh: native on hexane, increment B1 (design)

- **Date:** 2026-10-13 (revised 2026-10-14 after a second review).
- **Status:** approved (design); pending implementation.
- **Increment:** B1 of the hexane-native work (B1: `sesh` runs correctly on hexane; B2: hexane login auto-restore).
- **Depends on:** the multi-host work on `feat/sesh-multihost` (PR #56). This branch (`feat/sesh-hexane-b1`) is stacked on it.
- **Files (repo):** `bin/sesh`, `bin/tests/sesh.test.sh`.
- **Unchanged:** `bin/sesh-save`, `bin/sesh-restore`, `bin/cc-connect`, `bin/hx-connect`.

## Problem

`sesh` was written for macOS and fails on hexane (Arch, bash 5.3). A live run on hexane (`master`, the single-host `a0270b0` build) shows the shape of it. The picker lists only `[local]` Claude rows and no `[hexane]`/`[dev]` tmux rows. `set -u` aborts the `candidates` subshell, and a degraded `_age` throws `[: : integer expected`. Three root causes, confirmed by deploying the multi-host build to hexane this session:

1. **BSD-only `stat -f %m`** (`_mtime`) returns nothing on GNU `stat`, so the label cache silently defeats itself.
2. **No self-awareness.** On hexane, its own tmux is reached via `ssh hexane` loopback, which finds nothing, so hexane's sessions are invisible.
3. **macOS-only window spawn** (`open -na Ghostty`) does not exist on a Hyprland desktop, which uses alacritty.

hexane runs a Hyprland desktop and the user works there in alacritty. So the picker must open in alacritty and behave correctly when run on the box.

## Goals

1. `sesh` run on hexane lists this box's Claude sessions (local), this box's own tmux (local, direct), and the other boxes' tmux (remote, ssh), and opens any of them.
2. The OS-specific calls work on both macOS and Linux from one codebase.
3. The Mac's **real** behavior is unchanged. The only Mac-visible change is cosmetic and an improvement: the new-window dry-run now prints the concrete spawn command instead of a generic `newwin` line.
4. Both OS branches are exercised by the suite on one machine, and the suite runs green on hexane as an acceptance gate.

Non-goals, all deferred to B2:
- login-time auto-restore and snapshotting hexane's live set,
- the Hyprland/systemd login hook,
- Linux support in `sesh-save`/`sesh-restore`,
- a shared `sesh-os.sh` library,
- presence markers for self tmux.

## Design

Revised after two adversarial reviews. The load-bearing correction from the second concerns dry-run. A preview is a real test seam only if the live dispatch flows through it. So each path has exactly **one** dry-run owner.

### A. OS-family primitives, inlined in `sesh`

A single `case` near the top of `sesh`, switchable via `SESH_UNAME` so the suite can drive both branches on one machine:

```sh
case "${SESH_UNAME:-$(uname)}" in
  Darwin) _mtime(){ stat -f %m "$1" 2>/dev/null; }
          _spawn_window(){ [ -n "${SESH_DRYRUN:-}" ] && { printf 'spawn[darwin]: open -na %s --args -e %s\n' "${SESH_TERMINAL_APP:-/Applications/Ghostty.app}" "$*"; return; }
                           open -na "${SESH_TERMINAL_APP:-/Applications/Ghostty.app}" --args -e "$@"; } ;;
  Linux)  _mtime(){ stat -c %Y "$1" 2>/dev/null; }
          _spawn_window(){ [ -n "${SESH_DRYRUN:-}" ] && { printf 'spawn[linux]: setsid -f %s -e %s\n' "${SESH_TERMINAL:-alacritty}" "$*"; return; }
                           setsid -f "${SESH_TERMINAL:-alacritty}" -e "$@" 2>>"$STATE/spawn.err"; } ;;
  *)      _mtime(){ stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }
          _spawn_window(){ [ -n "${SESH_DRYRUN:-}" ] && { printf 'spawn[other]: %s -e %s\n' "${SESH_TERMINAL:-xterm}" "$*"; return; }
                           "${SESH_TERMINAL:-xterm}" -e "$@" & } ;;
esac
```

- `sesh` drops its standalone `_mtime` and the `GHOSTTY=` var.
- **One dry-run owner per path.** `do_open`'s new-window branch delegates **entirely** to `_spawn_window "$@"` (no `do_open`-level `would open newwin` line), so `_spawn_window`'s `spawn[os]:` echo is what the live `-n` path actually prints under dry-run. `do_open` keeps its own dry-run only for the same-window `exec` path (`would open here: …`):

  ```sh
  do_open(){
    if [ -n "${SESH_NEWWIN:-}" ]; then _spawn_window "$@"
    elif [ -n "${SESH_DRYRUN:-}" ]; then printf 'would open here: %s\n' "$*"
    else exec "$@"; fi
  }
  ```
- The Linux spawn uses `setsid -f` (clean detach) and **does not silence stderr**; a missing-`WAYLAND_DISPLAY` failure lands in `$STATE/spawn.err`.
- The `*` branch keeps both functions defined, so neither is ever undefined mid-open.

**Why inline, not a `sesh-os.sh` file:** a sibling `source "$(dirname "${BASH_SOURCE[0]}")/sesh-os.sh"` works today only because `sesh` resolves through a whole-directory symlink (`~/bin/dotbin` → `~/.dotfiles/bin`). The repo also symlinks individual `bin/` scripts into `~/.local/bin` (`default.conf.yaml`). The day `sesh` is linked that way, the sibling source breaks, and bash 3.2 has no `realpath` to recover. B1 has no second consumer, so inlining removes the fragility and keeps the functions reachable when the suite sources `sesh`. The shared file is extracted in B2.

### B. Self-session detection

```sh
_self(){
  if [ -n "${SESH_SELF:-}" ]; then printf '%s' "$SESH_SELF"; return; fi
  local h; h="${SESH_HOSTNAME:-$(hostname -s 2>/dev/null)}"
  [ -n "$h" ] && _hosts | grep -Fqx "$h" && printf '%s' "$h"
}
```

- `SESH_SELF` forces the answer; otherwise the self host is the host-list entry **exactly** equal to `hostname -s` (`grep -Fqx`: fixed-string, so a hostname with a `.` is not treated as a regex, and `dev-1` never matches a list containing `dev-10`).
- `SESH_HOSTNAME` is a test seam for the hostname lookup.
- On `lorium` (not in the list) `_self` is empty, so nothing below changes the Mac's behavior.
- Self-detection is fail-silent by design: an unknown box is simply all-remote. Everything downstream depends on it, so the Verification step asserts directly that `_self` resolves to `hexane` on hexane.

### C. Candidate model: two types, `host == self` special-cased

The row schema from increment A is kept (`type \t key \t host \t label`); there is no new row type. A tmux session is the same object on any host, differing only in transport. So `host == self` is special-cased at exactly two points. In `candidates()`, with `self="$(_self)"`:

- **refresh loop:** skip self (`[ "$h" = "$self" ] && continue`) so there is no loopback ssh and no `remote.<self>.list` write.
- **emit loop (one pass over the host list, order preserved):** for each host, if it is self, list via a direct local `"${SESH_TMUX:-tmux}" ls -F '#{session_name}' 2>/dev/null` (tolerating a "no server" empty result); otherwise read its `remote.<h>.list` cache. Either way emit a normal `remote` row with `host = h`.

Because self is listed from live tmux and never read from a cache file, a stale `remote.<self>.list` (e.g. one left by this session's deploy test) can never double-list it. `SESH_TMUX` is a new seam (mirror of `SESH_SSH`) so the local tmux list is mockable.

### D. Open paths (`main()`)

The `remote)` arm was an unconditional `do_open "$HX_CONNECT" "$f" "$key"`; it gains a self branch (`$f` is the host, `$key` the session):

```sh
remote) if [ "$f" = "$(_self)" ]; then _open_self "$key"
        else do_open "$HX_CONNECT" "$f" "$key"; fi ;;
```

On `lorium` `_self` is empty and `[ "$f" = "" ]` is false, so the hx-connect path runs exactly as today. `_self` is evaluated in both `candidates()` and `main()`; they share process env and must agree. `_open_self <session>` attaches a **local** tmux session. It owns the `$TMUX` guard and its dry-run, and reuses `do_open` for the two cases that can be `exec`'d or spawned:

```sh
_open_self(){ local s="$1" tm="${SESH_TMUX:-tmux}"
  if [ -z "${SESH_NEWWIN:-}" ] && [ -n "${TMUX:-}" ]; then
    # inside tmux, same window: switch WITHOUT exec, or the pane dies
    [ -n "${SESH_DRYRUN:-}" ] && { printf 'would switch-client: %s\n' "$s"; return; }
    "$tm" new-session -dA -s "$s" \; switch-client -t "$s"
  else
    do_open "$tm" new-session -A -s "$s"   # -n -> _spawn_window (alacritty); else exec in place
  fi
}
```

The two non-switch sub-cases inherit `do_open`'s dry-run (`spawn[os]:` for `-n`, `would open here:` for a plain shell). Only the inside-tmux case is special, because `switch-client` must not be `exec`'d. (A sibling launcher like `hx-connect` was considered and declined for exactly that reason: a `do_open`-invoked launcher would force the `exec`.)

### E. Terminal overrides

Two clearly-scoped vars, documented in the header: `SESH_TERMINAL_APP` (macOS, an `.app` bundle for `open -na`) and `SESH_TERMINAL` (Linux, a terminal binary for `-e`). They differ because the launch mechanisms differ.

## Testing

Seams: `SESH_UNAME`, `SESH_HOSTNAME`, `SESH_TMUX` (new); `SESH_SELF`, `SESH_SSH`, `SESH_DRYRUN` (existing).

1. **De-BSD the harness.** `sesh.test.sh:72` uses `stat -f %m` directly; replace with `mt="$(run_fn _mtime "$f")"` so the harness runs on GNU stat too.
2. **`_self` resolution.** `SESH_SELF` override; `SESH_HOSTNAME` in `_hosts` → that host; **near-miss** `SESH_HOSTNAME=dev-10`, `SESH_HOSTS="dev-1 dev-2"` → empty; no match → empty.
3. **self vs remote, no double-list.** `SESH_HOSTNAME=alpha`, `SESH_HOSTS="alpha beta"`, a fake `SESH_TMUX` serving alpha's sessions, a fake `SESH_SSH` serving beta's, plus a **pre-seeded stale `remote.alpha.list`**. Assert: alpha sessions appear once (from local tmux), beta from ssh, zero duplicate alpha rows from the stale cache.
4. **OS spawn branches (dry-run) + real `_mtime`.** With `SESH_NEWWIN=1 SESH_DRYRUN=1`: `SESH_UNAME=Linux` → output has `spawn[linux]: setsid -f alacritty -e …`; `SESH_UNAME=Darwin` → `spawn[darwin]: open -na …Ghostty… -e …`. Separately, with **no** `SESH_UNAME` override, `_mtime` returns a valid epoch for a real file (so the mtime assertion runs on the real OS, not the forced one).
5. **`_open_self` dry-run.** `run_fn _open_self <s>` with `SESH_DRYRUN=1`: `TMUX` set → `would switch-client: <s>`; `TMUX` unset → `would open here: <tm> new-session -A -s <s>`; `SESH_NEWWIN=1` → `spawn[os]: …`. Uses `SESH_TMUX` so nothing real runs.
6. **`t_open_newwin` updates** to assert `spawn[darwin]: open -na …` (the new single-owner preview) instead of the old `newwin` string. All other existing tests stay green on `lorium` (`_self` empty → all remote).
7. **Acceptance gate:** `bash bin/tests/sesh.test.sh` reports `failed 0` **on hexane**. What this proves: GNU-userland portability, a real `_mtime` (`stat -c %Y`), and the real `hostname -s → hexane` self-path. It does **not** prove the GUI spawn (the suite is mocked/dry-run), and it is not about `set -u` coverage (the Mac suite already runs every function under `set -u`, since `run_fn` re-enables it when it sources `sesh`).
8. **Non-dry-run spawn smoke (manual, on hexane):** `SESH_NEWWIN=1 sesh <query>` opens a real alacritty window **and** `$STATE/spawn.err` is empty. This is the only check that proves root-cause #3 is actually fixed.

## Edge cases

- **Stale `remote.<self>.list`:** never read (self is listed from live tmux), so no duplicate self rows.
- **Self pick from inside tmux:** `switch-client` without `exec`, so the pane is never replaced by a dead tmux.
- **No display for a new window:** `setsid -f alacritty` writes failure to `spawn.err` instead of vanishing.
- **Hostname drift:** if `hostname -s` ever stops matching a list entry, `_self` is empty and B1 silently reverts to the (broken) all-remote behavior; the direct `_self`-on-hexane Verification check is what catches that, and `SESH_SELF` is the override.
- **Unknown OS:** the `*` branch keeps `_mtime`/`_spawn_window` defined.

## Verification

- `bash bin/tests/sesh.test.sh` green on the Mac and on hexane (the gate).
- On hexane: `SESH_SELF= SESH_HOSTNAME= _self` (real) prints `hexane`; `sesh` lists hexane Claude (local) + hexane tmux (local) + dev boxes (remote); `SESH_DRYRUN=1 sesh <hexane-session>` shows a local `tmux new-session` (not `hx-connect`); `SESH_DRYRUN=1 sesh <dev-1-session>` shows `hx-connect dev-1 …`; `SESH_NEWWIN=1 sesh <hexane-session>` opens a real alacritty window with an empty `spawn.err`.
- On the Mac: the full suite and real behavior match pre-B1; only the new-window dry-run string changes.
- de-slop lint clean (0 hard) on this spec and the commit/PR text.

## Rollout

Single branch `feat/sesh-hexane-b1`, stacked on `feat/sesh-multihost` (PR #56). The spec and the `sesh` + test changes land together. hexane tracks `master`. The acceptance-gate run and real use on hexane follow once #56 and B1 merge and hexane pulls. During development, check out the branch on hexane directly. B2 (login auto-restore) gets its own spec and extracts the shared `sesh-os.sh`.
