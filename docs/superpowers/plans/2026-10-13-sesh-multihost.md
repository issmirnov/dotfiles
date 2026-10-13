# sesh Multi-Host Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Teach the Mac's `sesh` to list, open, and restore tmux sessions across `hexane` + `dev-1`/`dev-2`/`dev-3`, over mosh, instead of only `hexane`.

**Architecture:** Thread one new field, the `host`, through the picker rows, the presence-marker path, and the snapshot schema. Only the picker reads a host list; `sesh-save` and `sesh-restore` carry the host they already hold. Remote queries run per-host in parallel with per-host caches, so a slow box never blocks the picker.

**Tech Stack:** Bash (macOS `/bin/bash` 3.2, no associative arrays), `jq`, `fzf`, `ssh`, `mosh`, launchd. Tests source the scripts as libraries and inject `ssh`/`mosh` via `SESH_SSH`/`HX_MOSH`, so no network is touched.

**Spec:** `docs/superpowers/specs/2026-10-13-sesh-multihost-design.md`

**Branch:** `feat/sesh-multihost` (already created, holds the committed spec).

---

## File structure

| File | Responsibility | Change |
|------|----------------|--------|
| `bin/sesh` | Picker over local Claude + remote tmux | Add `_hosts()` + `_refresh_remote()`; rewrite the remote branch of `candidates()`; pass host to the opener |
| `bin/hx-connect` | Launch one remote session over mosh | Two-arg `<host> <session>`; host-namespaced marker; `HX_MOSH` seam |
| `bin/sesh-save` | Snapshot the live set | Walk host-namespaced markers; emit `{host, session}`; prune legacy flat markers |
| `bin/sesh-restore` | Rebuild the snapshot at login | Read `{host, session}` (default `hexane`); per-host `reachable`/`remote_open`; pass host to `hx-connect` |
| `bin/tests/sesh.test.sh` | Test harness | Migrate the 4 existing remote tests to per-host; add 9 new tests |
| `~/.ssh/config` (local) | Per-host connection reuse | Add `ControlMaster` to dev-1/2/3 blocks |
| dev-1/2/3 (boxes) | mosh transport | `apt install mosh` |

---

## Task 1: Host list helper `_hosts()` in `bin/sesh`

**Files:**
- Modify: `bin/sesh` (add helper near the other helpers, after `_cwd_of` at line 51)
- Test: `bin/tests/sesh.test.sh`

- [ ] **Step 1: Write the failing tests**

Add these three tests to `bin/tests/sesh.test.sh` after the `# name_of` block (after line 43), before `echo "# local label cache (mtime-keyed)"`:

```bash
echo "# _hosts (env > file > default)"
t_hosts_env(){ newtmp; export HOME="$TMP"
  export SESH_HOSTS="h1 h2 h3"
  out="$(run_fn _hosts)"
  assert_has "env host h1 listed" "h1" "$out"
  assert_has "env host h3 listed" "h3" "$out"
  unset SESH_HOSTS
}
t_hosts_file(){ newtmp; export HOME="$TMP"; unset SESH_HOSTS 2>/dev/null
  mkdir -p "$TMP/.config/sesh"; printf 'boxA\n# a comment\n\nboxB\n' > "$TMP/.config/sesh/hosts"
  out="$(run_fn _hosts)"
  assert_has   "file host boxA listed" "boxA" "$out"
  assert_has   "file host boxB listed" "boxB" "$out"
  assert_hasnt "file comment ignored"  "comment" "$out"
}
t_hosts_default(){ newtmp; export HOME="$TMP"; unset SESH_HOSTS 2>/dev/null
  out="$(run_fn _hosts)"
  assert_has "default includes hexane" "hexane" "$out"
  assert_has "default includes dev-1"  "dev-1" "$out"
}
```

Add the three names to the runner `for t in ...` list (lines 118-121), so it begins:

```bash
for t in t_aititle t_userfallback t_hosts_env t_hosts_file t_hosts_default \
         t_cache_hit t_cache_miss_mtime \
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash ~/.dotfiles/bin/tests/sesh.test.sh`
Expected: FAIL on the `t_hosts_*` cases (`_hosts` is not defined, so `run_fn _hosts` prints nothing).

- [ ] **Step 3: Write the implementation**

In `bin/sesh`, after `_cwd_of` (line 51), add:

```bash
# _hosts : boxes the picker queries. SESH_HOSTS env > ~/.config/sesh/hosts > default.
_hosts(){
  if [ -n "${SESH_HOSTS:-}" ]; then printf '%s\n' $SESH_HOSTS; return; fi
  local f="$HOME/.config/sesh/hosts"
  if [ -f "$f" ]; then sed -e 's/#.*//' "$f" | tr ' \t' '\n\n' | sed '/^$/d'; return; fi
  printf '%s\n' hexane dev-1 dev-2 dev-3
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash ~/.dotfiles/bin/tests/sesh.test.sh`
Expected: the `t_hosts_*` cases pass; everything else still passes.

- [ ] **Step 5: Commit**

```bash
git add bin/sesh bin/tests/sesh.test.sh
git commit -m "feat(sesh): add _hosts() list helper (env > file > default)" \
           -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Per-host remote candidates in `bin/sesh`

This rewrites the single-host remote branch of `candidates()` into a per-host parallel refresh plus an emit pass. It also migrates the 4 existing remote tests, which seed the old `remote.list` name that this task renames to `remote.<host>.list`.

**Files:**
- Modify: `bin/sesh`: add `_refresh_remote()`; replace `candidates()` remote branch (lines 79-102)
- Test: `bin/tests/sesh.test.sh`: migrate 4 tests, add 2

- [ ] **Step 1: Migrate the 4 existing remote tests and add 2 new ones**

Replace the whole block from `echo "# remote TTL cache + offline fallback"` through the end of `t_remote_success_empty` (lines 63-101) with:

```bash
echo "# remote TTL cache + offline fallback (single host via SESH_HOSTS=hexane)"
t_remote_fresh_skips_ssh(){ newtmp; export HOME="$TMP"
  echo cachedsess > "$TMP/.local/state/sesh/remote.hexane.list"; touch "$TMP/.local/state/sesh/remote.hexane.list"
  printf '#!/bin/bash\ntouch "%s/fake/ssh.called"\nexit 1\n' "$TMP" > "$TMP/fake/ssh"; chmod +x "$TMP/fake/ssh"
  export SESH_SSH="$TMP/fake/ssh" SESH_HOSTS=hexane SESH_REMOTE_TTL=600
  out="$(run_fn candidates)"
  assert_has    "fresh cache served"        "[hexane] cachedsess" "$out"
  assert_nofile "fresh cache does not ssh"  "$TMP/fake/ssh.called"
  unset SESH_SSH SESH_HOSTS SESH_REMOTE_TTL
}
t_remote_stale_fail_fallback(){ newtmp; export HOME="$TMP"
  echo ghostsess > "$TMP/.local/state/sesh/remote.hexane.list"; touch -t 200001010000 "$TMP/.local/state/sesh/remote.hexane.list"
  printf '#!/bin/bash\nexit 255\n' > "$TMP/fake/ssh"; chmod +x "$TMP/fake/ssh"
  export SESH_SSH="$TMP/fake/ssh" SESH_HOSTS=hexane SESH_REMOTE_TTL=60
  out="$(run_fn candidates)"
  assert_has  "stale cache served on ssh failure" "[hexane] ghostsess" "$out"
  assert_file "failure records negative-cache marker" "$TMP/.local/state/sesh/remote.hexane.fail"
  unset SESH_SSH SESH_HOSTS SESH_REMOTE_TTL
}
t_remote_success_refresh(){ newtmp; export HOME="$TMP"
  echo oldsess > "$TMP/.local/state/sesh/remote.hexane.list"; touch -t 200001010000 "$TMP/.local/state/sesh/remote.hexane.list"
  : > "$TMP/.local/state/sesh/remote.hexane.fail"
  printf '#!/bin/bash\nprintf "newA\\nnewB\\n"; echo __SESH_OK__\n' > "$TMP/fake/ssh"; chmod +x "$TMP/fake/ssh"
  export SESH_SSH="$TMP/fake/ssh" SESH_HOSTS=hexane SESH_REMOTE_TTL=60 SESH_REFRESH=1
  out="$(run_fn candidates)"
  assert_has    "refresh shows new sessions"    "[hexane] newA" "$out"
  assert_has    "refresh shows all new"         "[hexane] newB" "$out"
  assert_hasnt  "refresh drops stale session"   "oldsess"       "$out"
  assert_nofile "success clears negative-cache" "$TMP/.local/state/sesh/remote.hexane.fail"
  unset SESH_SSH SESH_HOSTS SESH_REMOTE_TTL SESH_REFRESH
}
t_remote_success_empty(){ newtmp; export HOME="$TMP"
  echo oldsess > "$TMP/.local/state/sesh/remote.hexane.list"; touch -t 200001010000 "$TMP/.local/state/sesh/remote.hexane.list"
  printf '#!/bin/bash\necho __SESH_OK__\n' > "$TMP/fake/ssh"; chmod +x "$TMP/fake/ssh"
  export SESH_SSH="$TMP/fake/ssh" SESH_HOSTS=hexane SESH_REMOTE_TTL=60
  out="$(run_fn candidates)"
  assert_hasnt "connected+empty clears stale sessions" "oldsess" "$out"
  unset SESH_SSH SESH_HOSTS SESH_REMOTE_TTL
}

echo "# remote multi-host"
# fake ssh: sesh calls `ssh -o ConnectTimeout=5 -o BatchMode=yes <host> <cmd>`,
# so the host is positional arg 5. Branch on it to serve per-host sessions.
t_multihost_emit(){ newtmp; export HOME="$TMP"
  cat > "$TMP/fake/ssh" <<'EOF'
#!/bin/bash
case "$5" in
  alpha) printf 'a1\na2\n';;
  beta)  printf 'b1\n';;
esac
echo __SESH_OK__
EOF
  chmod +x "$TMP/fake/ssh"
  export SESH_SSH="$TMP/fake/ssh" SESH_HOSTS="alpha beta" SESH_REFRESH=1
  out="$(run_fn candidates)"
  assert_has "alpha a1 listed"      "[alpha] a1" "$out"
  assert_has "alpha a2 listed"      "[alpha] a2" "$out"
  assert_has "beta b1 listed"       "[beta] b1"  "$out"
  assert_has "row carries host f3"  "$(printf 'remote\ta1\talpha\t[alpha] a1')" "$out"
  unset SESH_SSH SESH_HOSTS SESH_REFRESH
}
t_multihost_fallback(){ newtmp; export HOME="$TMP"
  echo oldA > "$TMP/.local/state/sesh/remote.alpha.list"; touch -t 200001010000 "$TMP/.local/state/sesh/remote.alpha.list"
  cat > "$TMP/fake/ssh" <<'EOF'
#!/bin/bash
case "$5" in
  alpha) exit 255;;
  beta)  printf 'b1\n'; echo __SESH_OK__;;
esac
EOF
  chmod +x "$TMP/fake/ssh"
  export SESH_SSH="$TMP/fake/ssh" SESH_HOSTS="alpha beta" SESH_REMOTE_TTL=60
  out="$(run_fn candidates)"
  assert_has  "alpha stale list served on failure" "[alpha] oldA" "$out"
  assert_file "alpha failure records neg-cache"    "$TMP/.local/state/sesh/remote.alpha.fail"
  assert_has  "beta refreshed live"                "[beta] b1" "$out"
  unset SESH_SSH SESH_HOSTS SESH_REMOTE_TTL
}
```

Add the 2 new names to the runner list:

```bash
         t_remote_success_refresh t_remote_success_empty \
         t_multihost_emit t_multihost_fallback \
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash ~/.dotfiles/bin/tests/sesh.test.sh`
Expected: the migrated and new remote tests FAIL. The old impl reads `remote.list`, not `remote.hexane.list`, and only knows one `$HOST`, so per-host labels and caches are absent.

- [ ] **Step 3: Write the implementation**

In `bin/sesh`, add `_refresh_remote()` immediately before `candidates()` (before line 54):

```bash
# _refresh_remote <host> : refresh ~/.local/state/sesh/remote.<host>.list per the
# TTL / negative-cache rules. Writes only, emits nothing; safe to run in parallel
# (each host owns its own files).
_refresh_remote(){
  local host="$1" TTL="${SESH_REMOTE_TTL:-60}" NEGTTL="${SESH_NEG_TTL:-30}" attempt raw
  local RCACHE="$STATE/remote.$host.list" RFAIL="$STATE/remote.$host.fail"
  mkdir -p "$STATE" 2>/dev/null
  if   [ -n "${SESH_REFRESH:-}" ];                               then attempt=1
  elif [ -f "$RCACHE" ] && [ "$(_age "$RCACHE")" -lt "$TTL" ];   then attempt=0
  elif [ -f "$RFAIL"  ] && [ "$(_age "$RFAIL")"  -lt "$NEGTTL" ]; then attempt=0
  else                                                               attempt=1
  fi
  [ "$attempt" = 1 ] || return 0
  raw="$("${SESH_SSH:-ssh}" -o ConnectTimeout=5 -o BatchMode=yes "$host" \
        'tmux ls -F "#{session_name}" 2>/dev/null; echo __SESH_OK__' 2>/dev/null)"
  if printf '%s\n' "$raw" | grep -q '__SESH_OK__'; then
    printf '%s\n' "$raw" | grep -v '__SESH_OK__' | sed '/^[[:space:]]*$/d' > "$RCACHE.tmp" 2>/dev/null \
      && mv "$RCACHE.tmp" "$RCACHE" 2>/dev/null
    rm -f "$RFAIL" 2>/dev/null
  else
    touch "$RFAIL" 2>/dev/null
  fi
}
```

In `candidates()`, replace the remote block (lines 79-102, from `# ---- remote:` through its closing `fi`) with:

```bash
  # ---- remote: per-host TTL cache + negative-cache + offline fallback ----
  local hosts h rc s
  hosts="$(_hosts)"
  for h in $hosts; do _refresh_remote "$h" & done
  wait
  for h in $hosts; do
    rc="$STATE/remote.$h.list"
    [ -f "$rc" ] || continue
    while IFS= read -r s; do
      [ -n "$s" ] && printf 'remote\t%s\t%s\t[%s] %s\n' "$s" "$h" "$h" "$s"
    done < "$rc"
  done
```

Also delete the now-unused `HOST="${HX_HOST:-hexane}"` line (line 33) and the `RCACHE`/`RFAIL` names from the `local` on line 55 (change it to `local LABELS="$STATE/labels.tsv"`).

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash ~/.dotfiles/bin/tests/sesh.test.sh`
Expected: all cases pass (18 migrated/original + 5 from Tasks 1-2).

- [ ] **Step 5: Commit**

```bash
git add bin/sesh bin/tests/sesh.test.sh
git commit -m "feat(sesh): per-host remote candidates, queried in parallel" \
           -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Pass the host to the remote opener in `bin/sesh`

**Files:**
- Modify: `bin/sesh`: `main()` remote case (line 143)
- Test: `bin/tests/sesh.test.sh`

- [ ] **Step 1: Write the failing test**

Add after `t_multihost_fallback`:

```bash
t_open_remote_passes_host(){ newtmp; export HOME="$TMP"
  cat > "$TMP/fake/ssh" <<'EOF'
#!/bin/bash
[ "$5" = beta ] && printf 'b1\n'
echo __SESH_OK__
EOF
  chmod +x "$TMP/fake/ssh"
  export SESH_SSH="$TMP/fake/ssh" SESH_HOSTS="beta" SESH_REFRESH=1 SESH_DRYRUN=1
  out="$(run_fn main b1)"
  assert_has "remote open passes host then session" "hx-connect beta b1" "$out"
  unset SESH_SSH SESH_HOSTS SESH_REFRESH SESH_DRYRUN
}
```

Add `t_open_remote_passes_host` to the runner list (next to `t_open_here t_open_newwin`).

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/.dotfiles/bin/tests/sesh.test.sh`
Expected: FAIL. The old `remote)` case runs `do_open "$HX_CONNECT" "$key"` (session only), so the dry-run shows `hx-connect b1`, not `hx-connect beta b1`.

- [ ] **Step 3: Write the implementation**

In `bin/sesh`, change the `remote)` case (line 143). For a remote row, field 3 (`$f`) now holds the host and field 2 (`$key`) the session:

```bash
    remote) do_open "$HX_CONNECT" "$f" "$key" ;;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ~/.dotfiles/bin/tests/sesh.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add bin/sesh bin/tests/sesh.test.sh
git commit -m "feat(sesh): pass host to hx-connect from the picker" \
           -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Host-aware `bin/hx-connect`

**Files:**
- Modify: `bin/hx-connect` (full rewrite below)
- Test: `bin/tests/sesh.test.sh`

- [ ] **Step 1: Write the failing test**

Add after `t_open_remote_passes_host`:

```bash
echo "# hx-connect host-aware"
t_hxconnect_host_marker(){ newtmp; export HOME="$TMP"
  # fake mosh records its argv AND whether the host-namespaced marker exists at call time
  printf '#!/bin/bash\n[ -e "%s/.local/state/sesh/remote/dev-2/web" ] && echo OK > "%s/fake/mark"\necho "$@" > "%s/fake/argv"\n' "$TMP" "$TMP" "$TMP" > "$TMP/fake/mosh"
  chmod +x "$TMP/fake/mosh"
  HX_MOSH="$TMP/fake/mosh" bash "$HOME/.dotfiles/bin/hx-connect" dev-2 web
  argv="$(cat "$TMP/fake/argv" 2>/dev/null)"
  assert_has  "mosh targets host + attach-or-create" "dev-2 -- tmux new-session -A -s web" "$argv"
  assert_file "host-namespaced marker existed during run" "$TMP/fake/mark"
}
```

Add `t_hxconnect_host_marker` to the runner list.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/.dotfiles/bin/tests/sesh.test.sh`
Expected: FAIL. The current `hx-connect` treats `$1` as the session (so it would run `mosh dev-2 -- tmux new-session -A -s dev-2`) and writes a flat marker `remote/dev-2`, not `remote/dev-2/web`.

- [ ] **Step 3: Write the implementation**

Replace the whole of `bin/hx-connect` with:

```bash
#!/bin/bash
# hx-connect <host> <session> — reconnect to <host>'s tmux session <session> over
# mosh (attach if it exists, else create). A separate launcher so sesh / sesh-restore
# can hand it clean argv through `open ... -e` (an inline `sh -c "..."` gets mangled
# and the window falls back to a bare login shell).
#
# One-arg form `hx-connect <session>` keeps host = $HX_HOST (default hexane) for
# back-compat. Transport is injectable via HX_MOSH (a test seam).
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
host="${1:?usage: hx-connect <host> <session>}"; sess="${2:-}"
if [ -z "$sess" ]; then sess="$host"; host="${HX_HOST:-hexane}"; fi
# Presence marker (this process's PID), host-namespaced so same-named sessions on
# different boxes can't collide. Cleared on exit; sesh-save also prunes dead PIDs.
MARK="$HOME/.local/state/sesh/remote/$host/$sess"
mkdir -p "$(dirname "$MARK")"
echo $$ > "$MARK"
trap 'rm -f "$MARK"' EXIT INT TERM HUP
printf '\033]0;%s:%s\007' "$host" "$sess"   # immediate title until tmux set-titles takes over
"${HX_MOSH:-mosh}" "$host" -- tmux new-session -A -s "$sess"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ~/.dotfiles/bin/tests/sesh.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add bin/hx-connect bin/tests/sesh.test.sh
git commit -m "feat(sesh): hx-connect takes <host> <session>, host-namespaced marker" \
           -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Host-namespaced markers in `bin/sesh-save`

**Files:**
- Modify: `bin/sesh-save`: remote block (lines 37-47)
- Test: `bin/tests/sesh.test.sh`

- [ ] **Step 1: Write the failing test**

Add after `t_hxconnect_host_marker`:

```bash
echo "# sesh-save host-namespaced"
t_save_host_namespaced(){ newtmp; export HOME="$TMP"
  mkdir -p "$TMP/.claude/sessions" "$TMP/.local/state/sesh/remote/dev-1"
  echo $$ > "$TMP/.local/state/sesh/remote/dev-1/foo"     # $$ is this test's live PID
  : > "$TMP/.local/state/sesh/remote/legacyflat"          # a stale legacy flat marker
  bash "$HOME/.dotfiles/bin/sesh-save"
  out="$(cat "$TMP/.local/state/sesh/snapshot.json" 2>/dev/null)"
  assert_has    "save emits host"            '"host": "dev-1"' "$out"
  assert_has    "save emits session"         '"session": "foo"' "$out"
  assert_nofile "legacy flat marker pruned"  "$TMP/.local/state/sesh/remote/legacyflat"
}
```

Add `t_save_host_namespaced` to the runner list.

Note: `sesh-save` skips when system uptime is under 180s; on any normally-running machine this test proceeds. `$$` is the test runner's PID, alive for the whole run, so `kill -0` keeps the marker.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/.dotfiles/bin/tests/sesh.test.sh`
Expected: FAIL. The current remote walk is one level (`$MARKS/*`), so it reads the host directory name `dev-1` as a session and never emits `{host, session}`.

- [ ] **Step 3: Write the implementation**

In `bin/sesh-save`, replace the remote block (lines 37-47, from `# Remote: prune markers...` through `[ -n "$remote_json" ] || remote_json='[]'`) with:

```bash
# Remote: markers are host-namespaced (remote/<host>/<session>). Prune dead PIDs,
# drop any legacy flat markers (remote/<session>), then collect survivors.
for flat in "$MARKS"/*; do [ -f "$flat" ] && rm -f "$flat"; done   # legacy flat markers
for hd in "$MARKS"/*/; do
  [ -d "$hd" ] || continue
  for m in "$hd"*; do
    [ -e "$m" ] || continue
    mpid=$(cat "$m" 2>/dev/null)
    { [ -n "$mpid" ] && kill -0 "$mpid" 2>/dev/null; } || rm -f "$m"
  done
done
remote_json=$(
  for hd in "$MARKS"/*/; do
    [ -d "$hd" ] || continue
    host=$(basename "$hd")
    for m in "$hd"*; do
      [ -e "$m" ] || continue
      jq -n --arg h "$host" --arg s "$(basename "$m")" '{host:$h, session:$s}'
    done
  done | jq -s 'unique_by(.host + "\u0000" + .session)'
)
[ -n "$remote_json" ] || remote_json='[]'
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ~/.dotfiles/bin/tests/sesh.test.sh`
Expected: PASS. (`jq` pretty-prints with a space after the colon, matching the `'"host": "dev-1"'` needle.)

- [ ] **Step 5: Commit**

```bash
git add bin/sesh-save bin/tests/sesh.test.sh
git commit -m "feat(sesh): sesh-save walks host-namespaced markers -> {host, session}" \
           -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Host-aware restore in `bin/sesh-restore`

**Files:**
- Modify: `bin/sesh-restore`: `remote_open` (line 40), `reachable` (lines 41-44), remote block (lines 63-78)
- Test: `bin/tests/sesh.test.sh`

- [ ] **Step 1: Write the failing test (the jq read contract)**

Add after `t_save_host_namespaced`:

```bash
echo "# sesh-restore read contract"
t_restore_jq_contract(){
  local EXPR='.remote[]? | [(.host // "hexane"), .session] | @tsv'
  out="$(printf '%s' '{"remote":[{"host":"dev-1","session":"api"}]}' | jq -rc "$EXPR")"
  assert_has "new format keeps host"        "$(printf 'dev-1\tapi')"   "$out"
  out="$(printf '%s' '{"remote":[{"session":"legacy"}]}' | jq -rc "$EXPR")"
  assert_has "old format defaults to hexane" "$(printf 'hexane\tlegacy')" "$out"
}
```

Add `t_restore_jq_contract` to the runner list. This test pins the exact jq expression the implementation must use, so it passes once Step 3 adopts that expression.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/.dotfiles/bin/tests/sesh.test.sh`
Expected: FAIL only if the expression is wrong. (The test is self-contained jq; it is the contract the next step wires into `sesh-restore`.)

- [ ] **Step 3: Write the implementation**

In `bin/sesh-restore`:

Replace `remote_open` (line 40) with a host-aware version:

```bash
remote_open(){ [ -e "$MARKS/$1/$2" ] && kill -0 "$(cat "$MARKS/$1/$2" 2>/dev/null)" 2>/dev/null; }
```

Replace `reachable` (lines 41-44) so it takes a host argument:

```bash
reachable(){ local host="$1" ip port
  ip=$(ssh -G "$host" 2>/dev/null | awk '$1=="hostname"{print $2}')
  port=$(ssh -G "$host" 2>/dev/null | awk '$1=="port"{print $2}')
  nc -z -G 3 "${ip:-$host}" "${port:-22}" >/dev/null 2>&1; }
```

Replace the entire remote block (lines 63-78) with a per-entry, per-host loop:

```bash
# ---- remote (host-aware; old bare-session snapshots default host=hexane) ----
while IFS=$'\t' read -r host sess; do
  [ -n "$sess" ] || continue
  [ "$n" -ge "$CAP" ] && { log "cap $CAP reached; stopping"; break; }
  if remote_open "$host" "$sess"; then log "skip remote $host:$sess (already open)"; continue; fi
  if [ -z "$DRY" ] && ! reachable "$host"; then log "skip remote $host:$sess ($host unreachable)"; continue; fi
  log "open remote $host:$sess"
  openwin "$HX_CONNECT" "$host" "$sess"
  n=$((n + 1))
done < <(jq -rc '.remote[]? | [(.host // "hexane"), .session] | @tsv' "$SNAP" 2>/dev/null)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ~/.dotfiles/bin/tests/sesh.test.sh`
Expected: PASS (all cases).

- [ ] **Step 5: Commit**

```bash
git add bin/sesh-restore bin/tests/sesh.test.sh
git commit -m "feat(sesh): sesh-restore reopens per-host sessions (old snapshots -> hexane)" \
           -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: One-time box setup (mosh + ssh multiplexing)

Not a repo change. Confirm with the user before the sudo installs.

**Files:**
- Modify: `~/.ssh/config` (local, not in the repo)
- Boxes: dev-1, dev-2, dev-3

- [ ] **Step 1: Confirm, then install mosh on the dev boxes**

Confirm with the user first (sudo on their machines). Then:

```bash
for h in dev-1 dev-2 dev-3; do
  echo "== $h =="
  ssh "$h" 'sudo apt-get update -qq && sudo apt-get install -y mosh'
done
```

- [ ] **Step 2: Verify mosh-server is present**

```bash
for h in dev-1 dev-2 dev-3; do printf '%s: ' "$h"; ssh "$h" 'command -v mosh-server || echo MISSING'; done
```
Expected: a path for each, no `MISSING`.

- [ ] **Step 3: Add connection multiplexing to the dev ssh blocks**

Edit `~/.ssh/config`. Under each of `Host dev-1`, `Host dev-2`, `Host dev-3`, add:

```
    ControlMaster auto
    ControlPath ~/.ssh/sockets/%C
    ControlPersist 10m
```
`~/.ssh/sockets` already exists from the hexane setup; if not, `mkdir -p ~/.ssh/sockets && chmod 700 ~/.ssh/sockets`.

- [ ] **Step 4: Verify multiplexing and mosh reach**

```bash
ssh dev-1 true && ssh -O check dev-1          # expect: "Master running"
mosh dev-1 -- true && echo "mosh dev-1 ok"
```

---

## Task 8: Integration verification, push, and PR

**Files:** none (verification + release)

- [ ] **Step 1: Full test suite**

Run: `bash ~/.dotfiles/bin/tests/sesh.test.sh`
Expected: `# passed 27, failed 0` (18 original + 9 new: 3 hosts, 2 multihost, 1 open-remote, 1 hx-connect, 1 save, 1 restore).

- [ ] **Step 2: Live dry-runs (no windows opened)**

```bash
SESH_DRYRUN=1 sesh            # fzf lists local + hexane + dev-1/2/3 sessions
SESH_DRYRUN=1 sesh <a-dev-1-session-name>   # prints: would open here: .../hx-connect dev-1 <session>
SESH_REFRESH=1 time sesh -h   # a forced refresh across 4 hosts returns promptly; warm run near ~0.45s
```
Open one real dev session to confirm the window attaches over mosh and the marker lands at `~/.local/state/sesh/remote/<host>/<session>`, then close it.

- [ ] **Step 3: Confirm the lint is clean on the changed docs/messages**

```bash
python3 ~/.claude/skills/de-slopping/ste_lint.py docs/superpowers/plans/2026-10-13-sesh-multihost.md | tail -1
```
Expected: `0 hard, N soft`.

- [ ] **Step 4: Push and open the PR**

```bash
git push -u origin feat/sesh-multihost
gh pr create --base master --head feat/sesh-multihost \
  --title "feat(sesh): multi-host remote sessions (hexane + dev-1/2/3)" \
  --body-file <(cat <<'BODY'
## What
Teach the Mac's `sesh` to list, open, and restore tmux sessions across `hexane` and `dev-1`/`dev-2`/`dev-3`, over mosh, instead of only `hexane`.

## How
One new field, the `host`, threaded through the picker rows, the presence-marker path (`remote/<host>/<session>`), and the snapshot (`remote: [{host, session}]`). Per-host caches queried in parallel so a slow box never blocks the picker. Old snapshots restore with host defaulting to `hexane`.

## Verification
- `bash bin/tests/sesh.test.sh` -> `# passed 27, failed 0`
- `SESH_DRYRUN=1 sesh <dev-1 session>` prints the `hx-connect dev-1 <session>` action
- mosh installed on dev-1/2/3; ControlMaster added to their ssh blocks (local)

Spec: `docs/superpowers/specs/2026-10-13-sesh-multihost-design.md`. Increment A of 3.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
BODY
)
```

---

## Self-review notes

- **Spec coverage:** host list (Task 1), per-host parallel picker + offline fallback (Task 2), opener host (Task 3), host-aware `hx-connect` + markers (Task 4), snapshot schema (Task 5), restore + back-compat (Task 6), mosh + ssh setup (Task 7), verification (Task 8). All spec sections map to a task.
- **Bash 3.2:** no associative arrays used; `reachable` runs per entry (a down host costs one `nc` timeout per session, acceptable at login).
- **Back-compat:** one-arg `hx-connect` and `.host // "hexane"` keep the straddling restore cycle working.
- **Leftover:** the old single-host `remote.list`/`remote.fail` cache files become orphaned after Task 2; harmless, removed by hand or on next state cleanup.
