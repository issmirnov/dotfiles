# sesh hexane-native B1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `sesh` run correctly on hexane via OS-family-agnostic utils and smart self-session detection. On hexane the picker then lists this box's Claude (local), this box's own tmux (local, direct), and the other boxes (remote), and opens in alacritty.

**Architecture:** Inline an OS `case` (switchable via `SESH_UNAME`) for `_mtime` and `_spawn_window`, with one dry-run owner per dispatch path. Detect "self" by `hostname -s` in the host list. Special-case `host == self` in `candidates()` (local `tmux ls`) and `main()` (local attach with a `$TMUX` guard). The Mac's real behavior is unchanged; only the new-window dry-run string changes.

**Tech Stack:** Bash (macOS `/bin/bash` 3.2 + Arch bash 5.3), `jq`, `fzf`, `tmux`, `mosh`, alacritty/Ghostty. Tests source `sesh` under a temp `$HOME` and inject `ssh`/`tmux`/OS/hostname via seams; no network, no GUI.

**Spec:** `docs/superpowers/specs/2026-10-13-sesh-hexane-native-b1-design.md`
**Branch:** `feat/sesh-hexane-b1` (stacked on `feat/sesh-multihost` / PR #56), already holds the spec.

---

## File structure

| File | Change |
|------|--------|
| `bin/sesh` | Inline OS `case` (`_mtime`+`_spawn_window`); rewrite `do_open`; add `_self`; self-aware `candidates()`; add `_open_self`; branch the `main()` remote arm |
| `bin/tests/sesh.test.sh` | `SESH_BIN` seam + de-BSD line 72; replace `t_open_newwin`; add OS/self/self-vs-remote/open-self tests; update runner |

All current behavior on the Mac stays; the only Mac-visible change is the new-window **dry-run** string (`would open newwin:` → `spawn[darwin]:`), covered by an updated test.

---

## Task 1: OS-compat primitives + single dry-run owner + portable harness

**Files:**
- Modify: `bin/sesh` (remove `GHOSTTY=` line 30; replace `_mtime` line 37 with the OS `case`; rewrite `do_open` lines 126-138)
- Modify: `bin/tests/sesh.test.sh` (`SESH_BIN` seam line 10; de-BSD line 72; replace `t_open_newwin`; add `t_spawn_branches`, `t_mtime_real`; runner)

- [ ] **Step 1: Write/adjust the tests**

In `bin/tests/sesh.test.sh`, change line 10 from:
```bash
SESH="$HOME/.dotfiles/bin/sesh"
```
to (lets the suite test a `sesh` outside `~/.dotfiles`, e.g. a worktree on hexane):
```bash
SESH="${SESH_BIN:-$HOME/.dotfiles/bin/sesh}"
```

Change line 72 (in `t_cache_hit`) from `mt="$(stat -f %m "$f")"` to the OS-portable seam:
```bash
  mt="$(run_fn _mtime "$f")"
```

Replace the whole `t_open_newwin` function (lines 232-237) with these two tests:
```bash
t_spawn_branches(){ newtmp; export HOME="$TMP"
  export SESH_DRYRUN=1 SESH_NEWWIN=1
  out="$(SESH_UNAME=Linux  run_fn do_open ccx /d name --resume id)"
  assert_has "linux new-window spawns via setsid+terminal" "spawn[linux]: setsid -f alacritty -e" "$out"
  out="$(SESH_UNAME=Darwin run_fn do_open ccx /d name --resume id)"
  assert_has "darwin new-window spawns via open -na"       "spawn[darwin]: open -na"               "$out"
  unset SESH_DRYRUN SESH_NEWWIN
}
t_mtime_real(){ newtmp; export HOME="$TMP"
  f="$(mkproj projA idAAAAAAAAAA yes "T" "x")"
  out="$(run_fn _mtime "$f")"
  if [ "${out:-0}" -gt 0 ] 2>/dev/null; then ok "mtime returns an epoch on the real OS"; else no "mtime should be an epoch (got '$out')"; fi
}
```

In the runner `for t in …` list, replace `t_open_newwin` with `t_spawn_branches t_mtime_real` (keep `t_open_here`). The relevant line becomes:
```bash
         t_open_here t_spawn_branches t_mtime_real t_open_remote_passes_host \
```

- [ ] **Step 2: Run to verify failure**

Run: `bash ~/.dotfiles/bin/tests/sesh.test.sh`
Expected: FAIL. `t_spawn_branches` can't find `spawn[...]` (no `_spawn_window` yet; `do_open` still prints `would open newwin:`). `t_mtime_real` passes already (current `_mtime` works on the Mac).

- [ ] **Step 3: Implement in `bin/sesh`**

Delete line 30 entirely:
```bash
GHOSTTY="/Applications/Ghostty.app"
```

Replace line 37:
```bash
_mtime(){ stat -f %m "$1" 2>/dev/null; }
```
with the OS `case` (defines `_mtime` and `_spawn_window`; `SESH_UNAME` overrides `$(uname)` so the suite drives both branches; `_spawn_window` owns its dry-run preview):
```bash
# OS-family primitives. SESH_UNAME overrides $(uname) so the suite drives both branches.
case "${SESH_UNAME:-$(uname)}" in
  Darwin)
    _mtime(){ stat -f %m "$1" 2>/dev/null; }
    _spawn_window(){ if [ -n "${SESH_DRYRUN:-}" ]; then printf 'spawn[darwin]: open -na %s --args -e %s\n' "${SESH_TERMINAL_APP:-/Applications/Ghostty.app}" "$*"; return; fi
                     open -na "${SESH_TERMINAL_APP:-/Applications/Ghostty.app}" --args -e "$@"; } ;;
  Linux)
    _mtime(){ stat -c %Y "$1" 2>/dev/null; }
    _spawn_window(){ if [ -n "${SESH_DRYRUN:-}" ]; then printf 'spawn[linux]: setsid -f %s -e %s\n' "${SESH_TERMINAL:-alacritty}" "$*"; return; fi
                     setsid -f "${SESH_TERMINAL:-alacritty}" -e "$@" 2>>"$STATE/spawn.err"; } ;;
  *)
    _mtime(){ stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }
    _spawn_window(){ if [ -n "${SESH_DRYRUN:-}" ]; then printf 'spawn[other]: %s -e %s\n' "${SESH_TERMINAL:-xterm}" "$*"; return; fi
                     "${SESH_TERMINAL:-xterm}" -e "$@" & } ;;
esac
```

Replace `do_open` (lines 126-138) with:
```bash
# do_open <cmd> <args...> : same-window (exec) by default; new window with SESH_NEWWIN.
# New-window delegates to _spawn_window, which owns its own dry-run preview.
do_open(){
  if [ -n "${SESH_NEWWIN:-}" ]; then
    _spawn_window "$@"
  elif [ -n "${SESH_DRYRUN:-}" ]; then
    printf 'would open here: %s\n' "$*"
  else
    exec "$@"
  fi
}
```

Also update the header comment for `-n` (line 21) and add `SESH_TERMINAL`/`SESH_TERMINAL_APP` to the flags block (lines 19-27):
```bash
#   -n | SESH_NEWWIN=1     open a new terminal window instead of the current one
```
and after the `SESH_SSH` line add:
```bash
#        SESH_TERMINAL     Linux terminal binary for a new window (default alacritty)
#        SESH_TERMINAL_APP macOS .app bundle for a new window (default Ghostty)
```

- [ ] **Step 4: Run to verify pass**

Run: `bash ~/.dotfiles/bin/tests/sesh.test.sh`
Expected: all pass, `failed 0`. Also `bash -n bin/sesh` clean.

- [ ] **Step 5: Commit**

Stage ONLY these two files (never `git add -A`; `yabai/yabairc` + `.bak` must stay out):
```bash
cd ~/.dotfiles
git add bin/sesh bin/tests/sesh.test.sh
git commit -m "feat(sesh): OS-agnostic _mtime/_spawn_window; single dry-run owner" \
           -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `_self()` self-detection

**Files:**
- Modify: `bin/sesh` (add `_self` after `_hosts`, ~line 60)
- Modify: `bin/tests/sesh.test.sh` (add 3 tests + runner)

- [ ] **Step 1: Write the failing tests**

Add after the `t_hosts_default` function (near line 67):
```bash
echo "# _self detection"
t_self_env(){ newtmp; export HOME="$TMP"
  out="$(SESH_SELF=whatever run_fn _self)"
  assert_has "SESH_SELF forces self" "whatever" "$out"
}
t_self_hostname_match(){ newtmp; export HOME="$TMP"; unset SESH_SELF 2>/dev/null
  out="$(SESH_HOSTNAME=dev-1 SESH_HOSTS='dev-1 dev-2' run_fn _self)"
  assert_has "hostname in list resolves to self" "dev-1" "$out"
}
t_self_near_miss(){ newtmp; export HOME="$TMP"; unset SESH_SELF 2>/dev/null
  out="$(SESH_HOSTNAME=dev-10 SESH_HOSTS='dev-1 dev-2' run_fn _self)"
  if [ -z "$out" ]; then ok "near-miss (dev-10 vs dev-1) yields empty self"; else no "near-miss should be empty (got '$out')"; fi
}
```
Add `t_self_env t_self_hostname_match t_self_near_miss` to the runner list (e.g. right after `t_hosts_default`).

- [ ] **Step 2: Run to verify failure**

Run: `bash ~/.dotfiles/bin/tests/sesh.test.sh`
Expected: the `t_self_*` cases FAIL (`_self` undefined → `run_fn _self` prints nothing).

- [ ] **Step 3: Implement**

In `bin/sesh`, add immediately after the `_hosts` function (after its closing `}`, ~line 60):
```bash
# _self : the host-list entry that is THIS box (SESH_SELF, else hostname -s if listed).
# grep -Fqx = exact, fixed-string match, so dev-1 never matches a list with dev-10.
_self(){
  if [ -n "${SESH_SELF:-}" ]; then printf '%s' "$SESH_SELF"; return; fi
  local h; h="${SESH_HOSTNAME:-$(hostname -s 2>/dev/null)}"
  [ -n "$h" ] && _hosts | grep -Fqx "$h" && printf '%s' "$h"
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bash ~/.dotfiles/bin/tests/sesh.test.sh`
Expected: all pass, `failed 0`.

- [ ] **Step 5: Commit**

```bash
cd ~/.dotfiles
git add bin/sesh bin/tests/sesh.test.sh
git commit -m "feat(sesh): _self() self-detection (hostname in host list, exact match)" \
           -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Self-aware `candidates()` (local tmux for self, ssh for others)

**Files:**
- Modify: `bin/sesh` (`candidates()` remote branch, lines 112-123)
- Modify: `bin/tests/sesh.test.sh` (add `t_self_vs_remote` + runner)

- [ ] **Step 1: Write the failing test**

Add after `t_multihost_fallback` (near line 170):
```bash
t_self_vs_remote(){ newtmp; export HOME="$TMP"; unset SESH_SELF 2>/dev/null
  printf '#!/bin/bash\n[ "$1" = ls ] && printf "selfA\\nselfB\\n"\n' > "$TMP/fake/tmux"; chmod +x "$TMP/fake/tmux"
  cat > "$TMP/fake/ssh" <<'EOF'
#!/bin/bash
case "$5" in beta) printf 'b1\n';; esac
echo __SESH_OK__
EOF
  chmod +x "$TMP/fake/ssh"
  echo staleSelf > "$TMP/.local/state/sesh/remote.alpha.list"   # stale self cache must NOT surface
  export SESH_HOSTNAME=alpha SESH_HOSTS="alpha beta" SESH_TMUX="$TMP/fake/tmux" SESH_SSH="$TMP/fake/ssh" SESH_REFRESH=1
  out="$(run_fn candidates)"
  assert_has   "self tmux listed locally"     "[alpha] selfA" "$out"
  assert_has   "remote beta listed over ssh"  "[beta] b1"     "$out"
  assert_hasnt "stale self cache not emitted" "staleSelf"     "$out"
  unset SESH_HOSTNAME SESH_HOSTS SESH_TMUX SESH_SSH SESH_REFRESH
}
```
Add `t_self_vs_remote` to the runner list (near the other `t_multihost_*`).

- [ ] **Step 2: Run to verify failure**

Run: `bash ~/.dotfiles/bin/tests/sesh.test.sh`
Expected: `t_self_vs_remote` FAILS. The current loop has no self-awareness. It would ssh for `alpha` (the fake ssh returns nothing for alpha) and would emit the stale `staleSelf` from the cache file.

- [ ] **Step 3: Implement**

In `bin/sesh`, replace the remote branch of `candidates()` (lines 112-123, from `# ---- remote:` through its closing `done`) with:
```bash
  # ---- remote: self via local `tmux ls`; other hosts over ssh (per-host cache) ----
  local hosts h rc s self
  self="$(_self)"
  hosts="$(_hosts)"
  for h in $hosts; do [ "$h" = "$self" ] && continue; _refresh_remote "$h" & done
  wait
  for h in $hosts; do
    if [ "$h" = "$self" ]; then
      "${SESH_TMUX:-tmux}" ls -F '#{session_name}' 2>/dev/null | while IFS= read -r s; do
        [ -n "$s" ] && printf 'remote\t%s\t%s\t[%s] %s\n' "$s" "$h" "$h" "$s"
      done
    else
      rc="$STATE/remote.$h.list"; [ -f "$rc" ] || continue
      while IFS= read -r s; do
        [ -n "$s" ] && printf 'remote\t%s\t%s\t[%s] %s\n' "$s" "$h" "$h" "$s"
      done < "$rc"
    fi
  done
```

Add `SESH_TMUX` to the flags block in the header (after the `SESH_SSH` line):
```bash
#        SESH_TMUX         local tmux binary (default tmux; a test seam)
```

- [ ] **Step 4: Run to verify pass**

Run: `bash ~/.dotfiles/bin/tests/sesh.test.sh`
Expected: all pass, `failed 0`. The existing `t_multihost_*` tests still pass (they run on `lorium`, so `_self` is empty and no host is treated as self).

- [ ] **Step 5: Commit**

```bash
cd ~/.dotfiles
git add bin/sesh bin/tests/sesh.test.sh
git commit -m "feat(sesh): candidates() lists self tmux locally, others over ssh" \
           -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: `_open_self()` local attach + `main()` self branch

**Files:**
- Modify: `bin/sesh` (add `_open_self` after `do_open`; branch the `remote)` arm in `main`, line 164)
- Modify: `bin/tests/sesh.test.sh` (add 3 tests + runner)

- [ ] **Step 1: Write the failing tests**

Add before the `# do_open window mode (dry-run)` block (near line 224):
```bash
echo "# _open_self (local tmux attach)"
t_open_self_plain(){ newtmp; export HOME="$TMP"; unset TMUX SESH_NEWWIN 2>/dev/null
  out="$(SESH_DRYRUN=1 SESH_TMUX=tmux run_fn _open_self mysess)"
  assert_has "plain shell attaches in place" "would open here: tmux new-session -A -s mysess" "$out"
}
t_open_self_in_tmux(){ newtmp; export HOME="$TMP"; unset SESH_NEWWIN 2>/dev/null
  out="$(SESH_DRYRUN=1 TMUX=/tmp/fake,1,0 SESH_TMUX=tmux run_fn _open_self mysess)"
  assert_has "inside tmux switches client" "would switch-client: mysess" "$out"
}
t_open_self_newwin(){ newtmp; export HOME="$TMP"
  out="$(SESH_DRYRUN=1 SESH_NEWWIN=1 SESH_UNAME=Linux SESH_TMUX=tmux run_fn _open_self mysess)"
  assert_has "new window spawns a terminal" "spawn[linux]: setsid -f alacritty -e tmux new-session -A -s mysess" "$out"
}
```
Add `t_open_self_plain t_open_self_in_tmux t_open_self_newwin` to the runner list.

- [ ] **Step 2: Run to verify failure**

Run: `bash ~/.dotfiles/bin/tests/sesh.test.sh`
Expected: the `t_open_self_*` cases FAIL (`_open_self` undefined).

- [ ] **Step 3: Implement**

In `bin/sesh`, add after the `do_open` function (after its closing `}`):
```bash
# _open_self <session> : attach a LOCAL tmux session. $TMUX-guarded so a pick from
# inside tmux switches the client instead of exec'ing (which would kill the pane).
_open_self(){
  local s="$1" tm="${SESH_TMUX:-tmux}"
  if [ -z "${SESH_NEWWIN:-}" ] && [ -n "${TMUX:-}" ]; then
    [ -n "${SESH_DRYRUN:-}" ] && { printf 'would switch-client: %s\n' "$s"; return 0; }
    "$tm" new-session -dA -s "$s" \; switch-client -t "$s"
  else
    do_open "$tm" new-session -A -s "$s"
  fi
}
```

Change the `main()` remote arm (line 164) from:
```bash
    remote) do_open "$HX_CONNECT" "$f" "$key" ;;
```
to (self → local attach; others → mosh, unchanged):
```bash
    remote) if [ "$f" = "$(_self)" ]; then _open_self "$key"; else do_open "$HX_CONNECT" "$f" "$key"; fi ;;
```

- [ ] **Step 4: Run to verify pass**

Run: `bash ~/.dotfiles/bin/tests/sesh.test.sh`
Expected: all pass, `failed 0`. `t_open_remote_passes_host` still passes (on `lorium` `_self` is empty, so the `else` hx-connect path runs).

- [ ] **Step 5: Commit**

```bash
cd ~/.dotfiles
git add bin/sesh bin/tests/sesh.test.sh
git commit -m "feat(sesh): _open_self local attach with \$TMUX guard; main routes self" \
           -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Verify on the Mac, acceptance-gate on hexane, non-dry-run spawn smoke

**Files:** none (verification)

- [ ] **Step 1: Full suite on the Mac**

Run: `bash ~/.dotfiles/bin/tests/sesh.test.sh`
Expected: `failed 0`. `SESH_DRYRUN=1 sesh` behaves as before (local + remote rows); only the new-window dry-run string changed.

- [ ] **Step 2: Push the branch (needed so hexane can fetch it)**

```bash
cd ~/.dotfiles
git push -u origin feat/sesh-hexane-b1
```

- [ ] **Step 3: Acceptance gate: run the suite ON hexane via a throwaway worktree (does not disturb hexane's live ~/.dotfiles)**

```bash
ssh hexane 'git -C ~/.dotfiles fetch origin feat/sesh-hexane-b1 && \
  git -C ~/.dotfiles worktree add -f /tmp/sesh-b1 feat/sesh-hexane-b1 && \
  SESH_BIN=/tmp/sesh-b1/bin/sesh bash /tmp/sesh-b1/bin/tests/sesh.test.sh; echo "exit=$?"'
```
Expected: `# passed N, failed 0` and `exit=0` on hexane (GNU stat, real `hostname -s → hexane` self-path). Leave the worktree in place for Step 4. If it fails, fix on the branch and re-run from Step 1 (do not proceed).

- [ ] **Step 4: Non-dry-run checks on hexane (manual, from hexane's alacritty desktop)**

Run from the worktree Step 3 left in place. The `_self` and dry-run checks work over ssh; the real-spawn check needs a Wayland session, so run it from hexane's alacritty desktop.
- **self resolves (over ssh is fine):** `ssh hexane 'cd /tmp/sesh-b1/bin && bash -c "source ./sesh >/dev/null 2>&1; _self; echo"'` → prints `hexane`.
- **dry-run remote (over ssh is fine):** `ssh hexane 'SESH_DRYRUN=1 SESH_BIN=/tmp/sesh-b1/bin/sesh bash /tmp/sesh-b1/bin/sesh <a-dev-1-session>'` → prints `hx-connect dev-1 …` (remote path still mosh).
- **real spawn (must be at hexane's desktop, in alacritty):** `SESH_NEWWIN=1 SESH_BIN=/tmp/sesh-b1/bin/sesh bash /tmp/sesh-b1/bin/sesh <a-hexane-tmux-session>` → a real alacritty window opens attached to that session, and `~/.local/state/sesh/spawn.err` is empty.

Record the results. The window-spawn check is the only one that proves root-cause #3 (alacritty actually launches) is fixed; the mocked suite cannot.

- [ ] **Step 5: Clean up the hexane worktree if still present**

```bash
ssh hexane 'git -C ~/.dotfiles worktree remove --force /tmp/sesh-b1 2>/dev/null; rm -rf /tmp/sesh-b1'
```

---

## Task 6: PR (stacked on #56)

**Files:** none (release)

- [ ] **Step 1: Open the PR**

Base it on the multi-host branch (B1 depends on #56). Write the body to a file, de-slop lint it (0 hard), then:
```bash
cd ~/.dotfiles
gh pr create --base feat/sesh-multihost --head feat/sesh-hexane-b1 \
  --title "feat(sesh): native on hexane — self-detection + OS-agnostic utils (B1)" \
  --body-file <body.md>
```
The body must state:
- **What:** `sesh` works on hexane.
- **How:** inline OS `case`, `_self`, host==self special-case, `_open_self` `$TMUX` guard.
- **Verification:** suite green on Mac and on hexane (worktree); real alacritty spawn smoke; dry-run self/remote.
- **Scope:** B1 only; B2 is login restore.
- **Stacked on PR #56** (merge #56 first).

End with the `🤖 Generated with [Claude Code](https://claude.com/claude-code)` line.

- [ ] **Step 2: Report** the PR URL and the hexane gate result.

---

## Self-review notes

- **Spec coverage:** OS-compat (Task 1), `_self` (Task 2), self-aware candidates incl. stale-cache no-double-list (Task 3), `_open_self` + main routing with `$TMUX` guard (Task 4), Mac + hexane gate + real-spawn smoke (Task 5), PR (Task 6). All spec sections map to a task.
- **Mac-safe:** on `lorium` `_self` is empty, so candidates and `main` take the existing all-remote path; only the new-window dry-run string changes (Task 1 updates its test).
- **Dry-run single owner:** `do_open` new-window delegates to `_spawn_window`; same-window keeps `would open here:`; `_open_self`'s switch-client branch prints its own `would switch-client:`.
- **Hexane gate is real execution:** the worktree + `SESH_BIN` runs the actual B1 `sesh` under GNU userland and the real `hostname -s`; the GUI spawn is covered by the manual Step 4 (the suite can't).
- **No new files, no sourced lib** (deferred to B2); `sesh-save`/`sesh-restore`/launchers untouched.
