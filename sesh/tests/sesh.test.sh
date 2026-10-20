#!/bin/bash
# Tests for `sesh` cache + same-window logic. Sources sesh as a library and
# calls its functions against a throwaway $HOME, injecting the ssh call via
# $SESH_SSH so no network is touched.
#
#   bash ~/.dotfiles/sesh/tests/sesh.test.sh
#
# Sesh must be sourceable without running main (BASH_SOURCE guard), and must
# expose: name_of, _cwd_of, candidates, do_open.
SESH="${SESH_BIN:-$HOME/.dotfiles/sesh/sesh}"
# resolve the sibling scripts from SESH's own dir, so a worktree run (SESH_BIN=...)
# tests that tree's sesh-remote/sesh-save/sesh-restore, not the live ~/.dotfiles ones.
_BIN="$(cd "$(dirname "$SESH")" 2>/dev/null && pwd)"
HXCONNECT="$_BIN/sesh-remote"
SESHSAVE="$_BIN/sesh-save"
SESHRESTORE="$_BIN/sesh-restore"
P=0; F=0
# Never reach the live compositor. Tests that need Hyprland install a fake (mkhypr).
export SESH_HYPRCTL=false
ok(){ P=$((P+1)); echo "ok $((P+F)) - $1"; }
no(){ F=$((F+1)); echo "NOT OK $((P+F)) - $1"; }
has(){ case "$2" in *"$1"*) return 0;; *) return 1;; esac; }   # has <needle> <haystack>
assert_has(){ if has "$2" "$3"; then ok "$1"; else no "$1 (missing: $2)"; fi; }
assert_hasnt(){ if has "$2" "$3"; then no "$1 (unexpected: $2)"; else ok "$1"; fi; }
assert_file(){ if [ -e "$2" ]; then ok "$1"; else no "$1 (no file: $2)"; fi; }
assert_nofile(){ if [ -e "$2" ]; then no "$1 (file present: $2)"; else ok "$1"; fi; }

# pin a non-host SESH_HOSTNAME so the suite is independent of the machine it runs on
# (else a box named like a test host — e.g. hexane — would be treated as self); self
# tests set SESH_HOSTNAME explicitly after newtmp to override this.
newtmp(){ TMP="$(mktemp -d)"; mkdir -p "$TMP/.claude/projects" "$TMP/.local/state/sesh" "$TMP/fake"; export SESH_HOSTNAME=__testhost__; }

# mkproj <proj> <id> <ai:yes|no> <title> <usercontent>  -> prints jsonl path
mkproj(){ local d="$TMP/.claude/projects/$1"; mkdir -p "$d"; local f="$d/$2.jsonl"; : >"$f"
  printf '{"type":"user","cwd":"/Users/vania/Projects/%s","message":{"role":"user","content":"%s"}}\n' "$1" "$5" >>"$f"
  [ "$3" = yes ] && printf '{"type":"ai-title","aiTitle":"%s"}\n' "$4" >>"$f"
  printf '%s' "$f"; }

# run_fn <fn> <args...> : source sesh in a clean subshell and call a function.
# Relies on exported HOME + SESH_* env already set by the caller.
run_fn(){ ( set +u; source "$SESH" >/dev/null 2>&1; "$@" ) </dev/null; }

# mkstat <pid> <comm> <ppid> <starttime> : a fake $TMP/proc/<pid>/stat line, laid out
# as the kernel writes it (starttime is field 22 of the raw line).
mkstat(){ mkdir -p "$TMP/proc/$1"
  printf '%s (%s) S %s 0 0 0 0 0 0 0 0 0 0 0 0 0 20 0 1 0 %s 0 0\n' "$1" "$2" "$3" "$4" > "$TMP/proc/$1/stat"; }

# clean_env : unset everything the Linux tests export, so the next test starts clean.
clean_env(){ unset SESH_PROC SESH_UNAME SESH_DRYRUN SESH_SKIP_BOOTGUARD SESH_NOTIFY SESH_STAGGER SESH_VERIFY_WAIT \
                   SESH_MON_WAIT SESH_CAP HYPR_SIMULATE HYPR_LAND_WS HYPR_LAND_MON HYPR_REQUIRE_SIG HYPRLAND_INSTANCE_SIGNATURE 2>/dev/null
             export SESH_HYPRCTL=false; }

# mkhypr : a fake hyprctl at $TMP/fake/hyprctl. It serves $TMP/hypr/<query>.json for
# `instances|clients|monitors|workspaces -j` and logs every `eval` to $TMP/hypr/eval.log.
# It exports SESH_HYPRCTL, SESH_PROC and SESH_UNAME=Linux.
# With HYPR_SIMULATE=1, an exec_cmd eval that carries "--sid <uuid>" starts a fake
# session: a registry entry (procStart 77), a claude -> foot chain in $TMP/proc, and a
# foot window. The window lands on $HYPR_LAND_WS, or else on the rule's workspace.
# A workspace it creates sits on $HYPR_LAND_MON (default DP-2).
# HYPR_REQUIRE_SIG=1 makes clients/monitors/workspaces fail unless HYPRLAND_INSTANCE_SIGNATURE=SIG1.
mkhypr(){ mkdir -p "$TMP/hypr" "$TMP/proc"
  printf '[{"instance":"SIG1","time":1,"pid":100,"wl_socket":"wayland-1"}]\n' > "$TMP/hypr/instances.json"
  printf '[{"id":0,"name":"DP-1","x":0},{"id":2,"name":"DP-2","x":3840}]\n' > "$TMP/hypr/monitors.json"
  printf '[]\n' > "$TMP/hypr/clients.json"
  printf '[]\n' > "$TMP/hypr/workspaces.json"
  cat > "$TMP/fake/hyprctl" <<'EOF'
#!/bin/bash
H="$(cd "$(dirname "$0")/.." && pwd)"
case "$1" in
  instances) cat "$H/hypr/instances.json" ;;
  clients|monitors|workspaces)
    # HYPR_REQUIRE_SIG=1: answer only a caller aimed at the live instance (SIG1), as
    # real hyprctl fails (exit 4) when the signature names a dead instance.
    if [ -n "${HYPR_REQUIRE_SIG:-}" ] && [ "${HYPRLAND_INSTANCE_SIGNATURE:-}" != "SIG1" ]; then exit 4; fi
    cat "$H/hypr/$1.json" ;;
  eval)
    printf '%s\n' "$2" >> "$H/hypr/eval.log"
    sid="$(printf '%s' "$2" | sed -n 's/.*--sid \([0-9a-f-]*\).*/\1/p')"
    if [ -n "${HYPR_SIMULATE:-}" ] && [ -n "$sid" ]; then
      ws="${HYPR_LAND_WS:-$(printf '%s' "$2" | sed -n 's/.*\[workspace \(name:\)\{0,1\}\([^] ]*\) silent\].*/\2/p')}"
      ws="${ws:-1}"
      n=$(wc -l < "$H/hypr/eval.log"); foot=$((7000 + n)); cl=$((8000 + n))
      mkdir -p "$H/proc/$foot" "$H/proc/$cl" "$H/.claude/sessions"
      printf '%s (foot) S 1 0 0 0 0 0 0 0 0 0 0 0 0 0 20 0 1 0 1 0 0\n' "$foot" > "$H/proc/$foot/stat"
      printf '%s (claude) S %s 0 0 0 0 0 0 0 0 0 0 0 0 0 20 0 1 0 77 0 0\n' "$cl" "$foot" > "$H/proc/$cl/stat"
      printf '{"pid":%s,"sessionId":"%s","cwd":"/tmp","procStart":"77","kind":"interactive","updatedAt":1}\n' "$cl" "$sid" > "$H/.claude/sessions/$cl.json"
      jq --argjson p "$foot" --arg w "$ws" '. + [{address: ("0xf" + ($p|tostring)), pid: $p, class: "foot", workspace: {id: 1, name: $w}, monitor: 2, at: [0, 0]}]' "$H/hypr/clients.json" > "$H/hypr/c.tmp" && mv "$H/hypr/c.tmp" "$H/hypr/clients.json"
      jq --arg w "$ws" --arg m "${HYPR_LAND_MON:-DP-2}" 'if any(.[]; .name == $w) then . else . + [{id: -1, name: $w, monitor: $m}] end' "$H/hypr/workspaces.json" > "$H/hypr/w.tmp" && mv "$H/hypr/w.tmp" "$H/hypr/workspaces.json"
    fi ;;
esac
EOF
  chmod +x "$TMP/fake/hyprctl"
  export SESH_HYPRCTL="$TMP/fake/hyprctl" SESH_PROC="$TMP/proc" SESH_UNAME=Linux; }

# mkcapture : mkhypr plus eight windows and the processes under them.
#   300 foot  argo/DP-1     <- 301 zsh <- 302 sesh-local <- 303 claude
#   310 foot  3/DP-2        <- 311 zsh <- 312 claude
#   320 scratchpad          <- 321 zsh <- 322 claude
#   330 foot  erp/DP-1, x2  <- 331 claude              (two windows share pid 330)
#   340 foot  special:stash <- 341 claude
#   350 tmux: server        <- 351 zsh <- 352 claude   (no window)
#   360 systemd             <- 361 claude              (no window)
#   370 foot  a\b/DP-1       <- 371 claude              (a backslash in the workspace name)
#   380 foot  special:sesh-stage <- 381 claude          (a window a failed move left on the stage)
mkcapture(){ mkhypr
  cat > "$TMP/hypr/clients.json" <<'EOF'
[{"address":"0xa1","pid":300,"class":"foot","workspace":{"id":-5,"name":"argo"},"monitor":0,"at":[10,40]},
 {"address":"0xa2","pid":310,"class":"foot","workspace":{"id":3,"name":"3"},"monitor":2,"at":[3850,40]},
 {"address":"0xa3","pid":320,"class":"scratchpad","workspace":{"id":-98,"name":"special:scratch"},"monitor":2,"at":[0,0]},
 {"address":"0xa4","pid":330,"class":"foot","workspace":{"id":-6,"name":"erp"},"monitor":0,"at":[0,0]},
 {"address":"0xa5","pid":330,"class":"foot","workspace":{"id":-6,"name":"erp"},"monitor":0,"at":[1900,0]},
 {"address":"0xa6","pid":340,"class":"foot","workspace":{"id":-99,"name":"special:stash"},"monitor":2,"at":[0,0]},
 {"address":"0xa7","pid":370,"class":"foot","workspace":{"id":-7,"name":"a\\b"},"monitor":0,"at":[0,0]},
 {"address":"0xa8","pid":380,"class":"foot","workspace":{"id":-97,"name":"special:sesh-stage"},"monitor":2,"at":[0,0]}]
EOF
  mkstat 300 foot 1 1;      mkstat 301 zsh 300 2; mkstat 302 sesh-local 301 3; mkstat 303 claude 302 4
  mkstat 310 foot 1 1;      mkstat 311 zsh 310 2; mkstat 312 claude 311 5
  mkstat 320 alacritty 1 1; mkstat 321 zsh 320 2; mkstat 322 claude 321 6
  mkstat 330 foot 1 1;      mkstat 331 claude 330 7
  mkstat 340 foot 1 1;      mkstat 341 claude 340 8
  mkstat 350 "tmux: server" 1 1; mkstat 351 zsh 350 2; mkstat 352 claude 351 9
  mkstat 360 systemd 1 1;   mkstat 361 claude 360 10
  mkstat 370 foot 1 1;      mkstat 371 claude 370 11
  mkstat 380 foot 1 1;      mkstat 381 claude 380 12
}

# mkreg <pid> <id> <cwd> <procStart> [kind] [updatedAt-ms] : a fake registry entry.
mkreg(){ mkdir -p "$TMP/.claude/sessions"
  printf '{"pid":%s,"sessionId":"%s","cwd":"%s","procStart":"%s","kind":"%s","updatedAt":%s}\n' \
    "$1" "$2" "$3" "$4" "${5:-interactive}" "${6:-1000000}" > "$TMP/.claude/sessions/$1.json"; }
# mksave : mkcapture plus registry entries for claude 303 (argo on DP-1) and 312 (3 on DP-2).
mksave(){ mkcapture
  mkreg 303 "aaaaaaaa-0000-0000-0000-000000000303" "/w/argo" 4 interactive 2000000
  mkreg 312 "bbbbbbbb-0000-0000-0000-000000000312" "/w/three" 5 interactive 1000000; }
snap(){ cat "$TMP/.local/state/sesh/snapshot.json" 2>/dev/null; }

# mkrestore : mkhypr, a fake notify-send, transcripts and cwds for three sessions, and a
# snapshot that an OLD Hyprland instance wrote (ids 1 and 3 on argo/DP-1, id 2 on 3/DP-2).
mkrestore(){ mkhypr
  export HYPRLAND_INSTANCE_SIGNATURE=SIG1 SESH_STAGGER=0 SESH_VERIFY_WAIT=0 SESH_NOTIFY="$TMP/fake/notify"
  printf '#!/bin/bash\necho "$@" >> "%s/fake/notify.log"\n' "$TMP" > "$TMP/fake/notify"; chmod +x "$TMP/fake/notify"
  mkdir -p "$TMP/w/argo" "$TMP/w/three" "$TMP/w/argo3"
  for i in 1 2 3; do mkproj "p$i" "aaaaaaaa-0000-0000-0000-00000000000$i" no "" "hi" >/dev/null; done
  cat > "$TMP/.local/state/sesh/snapshot.json" <<EOF
{"saved_at":"t","instance":"OLD","local":[
 {"id":"aaaaaaaa-0000-0000-0000-000000000001","cwd":"$TMP/w/argo","ws":"argo","monitor":"DP-1","at":[0,0],"updated":200},
 {"id":"aaaaaaaa-0000-0000-0000-000000000002","cwd":"$TMP/w/three","ws":"3","monitor":"DP-2","at":[0,0],"updated":100},
 {"id":"aaaaaaaa-0000-0000-0000-000000000003","cwd":"$TMP/w/argo3","ws":"argo","monitor":"DP-1","at":[1900,0],"updated":300}],
 "remote":[{"host":"dev-1","session":"api"}]}
EOF
}
evals(){ cat "$TMP/hypr/eval.log" 2>/dev/null; }

# ---------------------------------------------------------------------------
echo "# name_of"
t_aititle(){ newtmp; export HOME="$TMP"
  f="$(mkproj projA idAAAAAAAAAA yes "Real Title A" "hello there friend")"
  out="$(run_fn name_of "$f" idAAAAAAAAAA)"
  assert_has "ai-title wins" "Real Title A" "$out"
}
t_userfallback(){ newtmp; export HOME="$TMP"
  f="$(mkproj projB idBBBBBBBBBB no "" "first user message wins when no ai title exists here")"
  out="$(run_fn name_of "$f" idBBBBBBBBBB)"
  assert_has "falls back to user msg" "first user message" "$out"
}

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
t_hosts_single_fallback(){ newtmp; export HOME="$TMP"; unset SESH_HOSTS SESH_HOST HX_HOST 2>/dev/null
  # a one-box user who set SESH_HOST (per the README) must see THAT box in the picker,
  # not the built-in example list.
  out="$(SESH_HOST=mybox run_fn _hosts)"
  assert_has   "SESH_HOST used as single-host picker fallback"  "mybox" "$out"
  assert_hasnt "single-host fallback replaces example defaults" "dev-1" "$out"
}
t_hosts_single_legacy(){ newtmp; export HOME="$TMP"; unset SESH_HOSTS SESH_HOST HX_HOST 2>/dev/null
  out="$(HX_HOST=legacybox run_fn _hosts)"
  assert_has "legacy HX_HOST honored as single-host fallback" "legacybox" "$out"
}

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
  # hostname dev-1 vs a list containing dev-10: a missing -x would substring-match dev-10.
  out="$(SESH_HOSTNAME=dev-1 SESH_HOSTS='dev-10 dev-2' run_fn _self)"
  if [ -z "$out" ]; then ok "near-miss: dev-1 does not match dev-10 (exact -x)"; else no "near-miss should be empty (got '$out')"; fi
}

echo "# local label cache (mtime-keyed)"
t_cache_hit(){ newtmp; export HOME="$TMP"
  f="$(mkproj projA idAAAAAAAAAA yes "Real Title A" "hello")"
  mt="$(run_fn _mtime "$f")"
  printf '%s\t%s\t%s\t%s\n' "$f" "$mt" "/tmp/seedcwd" "SENTINEL_CACHED" > "$TMP/.local/state/sesh/labels.tsv"
  printf '#!/bin/bash\necho __SESH_OK__\n' > "$TMP/fake/ssh"; chmod +x "$TMP/fake/ssh"   # hermetic: no real network
  export SESH_SSH="$TMP/fake/ssh" SESH_HOSTS=hexane
  out="$(run_fn candidates)"
  assert_has   "cache hit reuses cached label" "SENTINEL_CACHED" "$out"
  assert_hasnt "cache hit skips recompute"     "Real Title A"    "$out"
  unset SESH_SSH SESH_HOSTS
}
t_cache_miss_mtime(){ newtmp; export HOME="$TMP"
  f="$(mkproj projA idAAAAAAAAAA yes "Real Title A" "hello")"
  # seed with a STALE mtime so it no longer matches the file -> recompute
  printf '%s\t%s\t%s\t%s\n' "$f" "100000000" "/tmp/seedcwd" "SENTINEL_CACHED" > "$TMP/.local/state/sesh/labels.tsv"
  printf '#!/bin/bash\necho __SESH_OK__\n' > "$TMP/fake/ssh"; chmod +x "$TMP/fake/ssh"   # hermetic: no real network
  export SESH_SSH="$TMP/fake/ssh" SESH_HOSTS=hexane
  out="$(run_fn candidates)"
  assert_has   "mtime change recomputes label" "Real Title A"    "$out"
  assert_hasnt "stale cache entry discarded"    "SENTINEL_CACHED" "$out"
  unset SESH_SSH SESH_HOSTS
}

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
t_open_remote_passes_host(){ newtmp; export HOME="$TMP"
  cat > "$TMP/fake/ssh" <<'EOF'
#!/bin/bash
[ "$5" = beta ] && printf 'b1\n'
echo __SESH_OK__
EOF
  chmod +x "$TMP/fake/ssh"
  export SESH_SSH="$TMP/fake/ssh" SESH_HOSTS="beta" SESH_REFRESH=1 SESH_DRYRUN=1
  out="$(run_fn main b1)"
  assert_has "remote open passes host then session" "sesh-remote beta b1" "$out"
  unset SESH_SSH SESH_HOSTS SESH_REFRESH SESH_DRYRUN
}

echo "# sesh-remote host-aware"
t_hxconnect_host_marker(){ newtmp; export HOME="$TMP"
  # fake mosh records its argv AND whether the host-namespaced marker exists at call time
  printf '#!/bin/bash\n[ -e "%s/.local/state/sesh/remote/dev-2/web" ] && echo OK > "%s/fake/mark"\necho "$@" > "%s/fake/argv"\n' "$TMP" "$TMP" "$TMP" > "$TMP/fake/mosh"
  chmod +x "$TMP/fake/mosh"
  SESH_MOSH="$TMP/fake/mosh" bash "$HXCONNECT" dev-2 web
  argv="$(cat "$TMP/fake/argv" 2>/dev/null)"
  assert_has  "mosh targets host + attach-or-create" "dev-2 -- tmux new-session -A -s web" "$argv"
  assert_file "host-namespaced marker existed during run" "$TMP/fake/mark"
}

echo "# sesh-save host-namespaced"
t_save_host_namespaced(){ newtmp; export HOME="$TMP"
  mkdir -p "$TMP/.claude/sessions" "$TMP/.local/state/sesh/remote/dev-1"
  echo $$ > "$TMP/.local/state/sesh/remote/dev-1/foo"     # $$ is this test runner's live PID
  : > "$TMP/.local/state/sesh/remote/legacyflat"          # a stale legacy flat marker
  SESH_SKIP_BOOTGUARD=1 bash "$SESHSAVE"
  out="$(cat "$TMP/.local/state/sesh/snapshot.json" 2>/dev/null)"
  assert_has    "save emits host"            '"host": "dev-1"' "$out"
  assert_has    "save emits session"         '"session": "foo"' "$out"
  assert_nofile "legacy flat marker pruned"  "$TMP/.local/state/sesh/remote/legacyflat"
}
t_save_migrates_live_flat(){ newtmp; export HOME="$TMP"
  mkdir -p "$TMP/.claude/sessions" "$TMP/.local/state/sesh/remote"
  echo $$ > "$TMP/.local/state/sesh/remote/liveflat"      # LIVE legacy flat marker (old hx-connect, mid-upgrade)
  : > "$TMP/.local/state/sesh/remote/deadflat"            # dead legacy flat marker
  SESH_HOST=mybox SESH_SKIP_BOOTGUARD=1 bash "$SESHSAVE"
  out="$(cat "$TMP/.local/state/sesh/snapshot.json" 2>/dev/null)"
  assert_has    "live flat marker survives into snapshot" '"session": "liveflat"' "$out"
  assert_has    "migrated under configured SESH_HOST"     '"host": "mybox"'        "$out"
  assert_file   "live flat migrated to host dir"          "$TMP/.local/state/sesh/remote/mybox/liveflat"
  assert_nofile "dead flat marker pruned"                 "$TMP/.local/state/sesh/remote/deadflat"
  assert_nofile "original flat marker moved away"         "$TMP/.local/state/sesh/remote/liveflat"
}

echo "# sesh-restore host-aware"
# Contract: the jq read defaults a missing host to hexane.
t_restore_jq_contract(){
  local EXPR='.remote[]? | [(.host // $hd), .session] | @tsv'
  out="$(printf '%s' '{"remote":[{"host":"dev-1","session":"api"}]}' | jq -rc --arg hd hexane "$EXPR")"
  assert_has "new format keeps host"                  "$(printf 'dev-1\tapi')"     "$out"
  out="$(printf '%s' '{"remote":[{"session":"legacy"}]}' | jq -rc --arg hd hexane "$EXPR")"
  assert_has "old format defaults to configured host" "$(printf 'hexane\tlegacy')" "$out"
  out="$(printf '%s' '{"remote":[{"session":"legacy"}]}' | jq -rc --arg hd mybox "$EXPR")"
  assert_has "old format honors configured host"      "$(printf 'mybox\tlegacy')"  "$out"
}
# Integration: dry-run restore must call sesh-remote with host THEN session.
t_restore_opens_per_host(){ newtmp; export HOME="$TMP"
  printf '{"saved_at":"t","local":[],"remote":[{"host":"dev-1","session":"api"},{"session":"legacy"}]}' > "$TMP/.local/state/sesh/snapshot.json"
  out="$(SESH_UNAME=Darwin SESH_DRYRUN=1 bash "$SESHRESTORE" 2>&1)"   # remote restore is macOS-only
  assert_has "restore opens new-format host:session" "sesh-remote dev-1 api" "$out"
  assert_has "restore defaults old-format to hexane"  "sesh-remote hexane legacy" "$out"
}
t_restore_legacy_uses_sesh_host(){ newtmp; export HOME="$TMP"
  # host-less snapshot + configured single host must restore to THAT box, not literal hexane.
  printf '{"saved_at":"t","local":[],"remote":[{"session":"legacy"}]}' > "$TMP/.local/state/sesh/snapshot.json"
  out="$(SESH_UNAME=Darwin SESH_HOST=mybox SESH_DRYRUN=1 bash "$SESHRESTORE" 2>&1)"   # remote restore is macOS-only
  assert_has "legacy restore targets configured SESH_HOST" "sesh-remote mybox legacy" "$out"
}

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
  assert_has "new window spawns a terminal" "spawn[linux]: setsid -f foot -e tmux new-session -A -s mysess" "$out"
}
t_open_self_in_tmux_real(){ newtmp; export HOME="$TMP"; unset SESH_NEWWIN 2>/dev/null
  # Exercise the REAL (non-dry) in-tmux branch with a call-recording fake tmux that
  # reports the session already exists (has-session exit 0, as a `tmux ls` pick always does).
  printf '#!/bin/bash\necho "$@" >> "%s/fake/calls"\ncase "$1" in has-session) exit 0;; esac\n' "$TMP" > "$TMP/fake/tmux"; chmod +x "$TMP/fake/tmux"
  TMUX=/tmp/fake,1,0 SESH_TMUX="$TMP/fake/tmux" run_fn _open_self mysess
  calls="$(cat "$TMP/fake/calls" 2>/dev/null)"
  assert_has   "existing session checked via has-session" "has-session -t =mysess"   "$calls"
  assert_has   "switches by exact name"                   "switch-client -t =mysess" "$calls"
  assert_hasnt "never uses nesting new-session -dA"       "new-session -dA"           "$calls"
}

echo "# do_open window mode (dry-run)"
t_open_here(){ newtmp; export HOME="$TMP"
  export SESH_DRYRUN=1
  out="$(run_fn do_open ccx /some/dir thename --resume theid)"
  assert_has   "default opens in current window (exec)" "here" "$out"
  assert_hasnt "default is not a new window"            "newwin" "$out"
  unset SESH_DRYRUN
}
t_spawn_branches(){ newtmp; export HOME="$TMP"
  export SESH_DRYRUN=1 SESH_NEWWIN=1
  out="$(SESH_UNAME=Linux  run_fn do_open ccx /d name --resume id)"
  assert_has "linux new-window spawns via setsid+terminal" "spawn[linux]: setsid -f foot -e" "$out"
  out="$(SESH_UNAME=Darwin run_fn do_open ccx /d name --resume id)"
  assert_has "darwin new-window spawns via open -na"       "spawn[darwin]: open -na"               "$out"
  unset SESH_DRYRUN SESH_NEWWIN
}
t_mtime_real(){ newtmp; export HOME="$TMP"
  f="$(mkproj projA idAAAAAAAAAA yes "T" "x")"
  out="$(run_fn _mtime "$f")"
  if [ "${out:-0}" -gt 0 ] 2>/dev/null; then ok "mtime returns an epoch on the real OS"; else no "mtime should be an epoch (got '$out')"; fi
}

echo "# lib/os.sh loading"
t_lib_via_symlink(){ newtmp; export HOME="$TMP"
  # The picker is reached through symlinks (~/bin/dotbin/sesh -> …/bin/sesh -> sesh/sesh),
  # and it must still find lib/os.sh beside its real file.
  mkdir -p "$TMP/bin"; ln -s "$SESH" "$TMP/bin/sesh"
  out="$( ( set +u; source "$TMP/bin/sesh" >/dev/null 2>&1; type _spawn_window >/dev/null 2>&1 && printf '%s' "$SESH_DIR" ) </dev/null )"
  want="$(cd "$_BIN" && pwd -P)"
  if [ "$out" = "$want" ]; then ok "sesh through a symlink resolves its real dir and loads lib/os.sh"; else no "SESH_DIR via symlink should be $want (got '$out')"; fi
}
echo "# process helpers (fake /proc)"
t_proc_stat_parse(){ newtmp; export HOME="$TMP"
  mkstat 4242 "tmux: server" 77 9001
  out="$(SESH_UNAME=Linux SESH_PROC="$TMP/proc" run_fn _proc_stat 4242)"
  assert_has "proc_stat reads ppid, start time and a comm with spaces" "77 9001 tmux: server" "$out"
}
t_alive_procstart(){ newtmp; export HOME="$TMP"
  mkstat 500 claude 1 4321
  if SESH_UNAME=Linux SESH_PROC="$TMP/proc" run_fn _alive 500 4321; then ok "alive when the start time matches"; else no "alive when the start time matches"; fi
  if SESH_UNAME=Linux SESH_PROC="$TMP/proc" run_fn _alive 500 9999; then no "a reused pid (other start time) must count as dead"; else ok "a reused pid (other start time) counts as dead"; fi
  if SESH_UNAME=Linux SESH_PROC="$TMP/proc" run_fn _alive 501 4321; then no "a missing pid must count as dead"; else ok "a missing pid counts as dead"; fi
}
t_want_session(){ newtmp; export HOME="$TMP"
  if SESH_UNAME=Linux run_fn _want_session interactive; then ok "linux keeps interactive sessions"; else no "linux keeps interactive sessions"; fi
  if SESH_UNAME=Linux run_fn _want_session sdk; then no "linux must drop non-interactive sessions"; else ok "linux drops non-interactive sessions"; fi
  if SESH_UNAME=Darwin run_fn _want_session sdk; then ok "darwin keeps every kind, as before"; else no "darwin keeps every kind, as before"; fi
}
echo "# window capture (fake hyprctl + fake /proc)"
t_capture_cases(){ newtmp; export HOME="$TMP"; mkcapture
  out="$(run_fn _capture_windows 303 312 322 331 341 352 361 371)"
  assert_has "claude under sesh-local maps to its foot window" '"303":{"ws":"argo","monitor":"DP-1","at":[10,40],"address":"0xa1"}' "$out"
  assert_has "claude under zsh maps to a numbered workspace"   '"312":{"ws":"3","monitor":"DP-2"' "$out"
  assert_has "the scratchpad window is skipped"                 '"322":{"skip":"scratchpad"}' "$out"
  assert_has "a pid shared by two windows gets no placement"    '"331":{}' "$out"
  assert_has "a stash window is kept"                           '"341":{"ws":"special:stash"' "$out"
  assert_has "claude inside tmux is skipped"                    '"352":{"skip":"tmux"}' "$out"
  assert_has "claude with no window is skipped"                 '"361":{"skip":"headless"}' "$out"
  assert_has "a backslash in a workspace name survives"        '"371":{"ws":"a\\b"' "$out"
  clean_env
}
t_capture_fail_closed(){ newtmp; export HOME="$TMP"; mkcapture
  printf 'not json\n' > "$TMP/hypr/clients.json"
  run_fn _capture_windows 303 >/dev/null; rc=$?
  if [ "$rc" = 1 ]; then ok "bad hyprctl json fails with status 1"; else no "bad hyprctl json should fail with status 1 (got $rc)"; fi
  printf '{}\n' > "$TMP/hypr/clients.json"
  run_fn _capture_windows 303 >/dev/null; rc=$?
  if [ "$rc" = 1 ]; then ok "non-array hyprctl json fails with status 1"; else no "non-array hyprctl json should fail with status 1 (got $rc)"; fi
  : > "$TMP/hypr/clients.json"
  run_fn _capture_windows 303 >/dev/null; rc=$?
  if [ "$rc" = 1 ]; then ok "an empty hyprctl reply fails with status 1"; else no "an empty hyprctl reply should fail with status 1 (got $rc)"; fi
  clean_env
}
t_capture_darwin(){ newtmp; export HOME="$TMP"
  out="$(SESH_UNAME=Darwin run_fn _capture_windows 303)"
  if [ "$out" = "{}" ]; then ok "darwin capture is empty (no placement)"; else no "darwin capture should be {} (got '$out')"; fi
}
echo "# sesh-save on Linux (gate, placement, history)"
t_save_linux_placement(){ newtmp; export HOME="$TMP"; mksave
  # DP-1's session gets the larger id, so only the monitor sort can put it first.
  mkreg 303 "zzzzzzzz-0000-0000-0000-000000000303" "/w/argo" 4 interactive 2000000
  bash "$SESHSAVE"
  out="$(snap)"
  assert_has   "linux save records the instance"    '"instance": "SIG1"' "$out"
  assert_has   "linux save records the workspace"   '"ws": "argo"'       "$out"
  assert_has   "linux save records the monitor"     '"monitor": "DP-2"'  "$out"
  assert_has   "linux save records updated (s)"     '"updated": 2000'    "$out"
  assert_hasnt "the window address stays out"       'address'            "$out"
  first="$(jq -r '.local[0].ws' "$TMP/.local/state/sesh/snapshot.json" 2>/dev/null)"
  if [ "$first" = "argo" ]; then ok "local is sorted by monitor name (DP-1 first)"; else no "local should start with argo on DP-1 (got '$first')"; fi
  clean_env
}
t_save_skips_dead_and_kinds(){ newtmp; export HOME="$TMP"; mksave
  mkreg 331 "cccccccc-0000-0000-0000-000000000331" "/w/x" 999 interactive   # fixture start time is 7
  mkreg 341 "dddddddd-0000-0000-0000-000000000341" "/w/y" 8 sdk
  mkreg 352 "eeeeeeee-0000-0000-0000-000000000352" "/w/z" 9 interactive     # inside tmux
  bash "$SESHSAVE"
  out="$(snap)"
  assert_hasnt "a reused pid (procStart mismatch) is not saved" "cccccccc" "$out"
  assert_hasnt "a non-interactive session is not saved"         "dddddddd" "$out"
  assert_hasnt "a tmux session is not saved"                    "eeeeeeee" "$out"
  assert_has   "a live interactive session is saved"            "aaaaaaaa" "$out"
  clean_env
}
t_save_gate(){ newtmp; export HOME="$TMP"; mksave
  S="$TMP/.local/state/sesh"
  printf '{"saved_at":"old","instance":"OLD","local":[{"id":"keep-me"}],"remote":[]}\n' > "$S/snapshot.json"
  bash "$SESHSAVE"
  assert_has "an old instance's snapshot is kept until restore runs" "keep-me" "$(snap)"
  printf 'SIG1\n' > "$S/restored"; bash "$SESHSAVE"
  assert_hasnt "after restore marks this instance, save writes" "keep-me" "$(snap)"
  printf '{"saved_at":"x","instance":"SIG1","local":[{"id":"mine"}],"remote":[]}\n' > "$S/snapshot.json"; : > "$S/restored"
  bash "$SESHSAVE"
  assert_hasnt "a snapshot this instance wrote may be replaced" '"mine"' "$(snap)"
  printf '[]\n' > "$TMP/hypr/instances.json"
  printf '{"saved_at":"y","instance":"SIG1","local":[{"id":"held"}],"remote":[]}\n' > "$S/snapshot.json"
  bash "$SESHSAVE"
  assert_has "no live instance: no write" "held" "$(snap)"
  printf '[{"instance":"SIG1"},{"instance":"B"}]\n' > "$TMP/hypr/instances.json"; bash "$SESHSAVE"
  assert_has "two live instances: no write" "held" "$(snap)"
  clean_env
}
t_save_first_run(){ newtmp; export HOME="$TMP"; mksave
  bash "$SESHSAVE"
  assert_has "first deploy: no snapshot yet, so save writes" "aaaaaaaa" "$(snap)"
  mkreg 341 "dddddddd-0000-0000-0000-000000000341" "/w/y" 8 interactive
  bash "$SESHSAVE"
  assert_has "later saves in the same instance keep writing" "dddddddd" "$(snap)"
  clean_env
}
t_save_fail_closed(){ newtmp; export HOME="$TMP"; mksave
  printf '{"saved_at":"z","instance":"SIG1","local":[{"id":"intact"}],"remote":[]}\n' > "$TMP/.local/state/sesh/snapshot.json"
  printf 'garbage\n' > "$TMP/hypr/clients.json"
  err="$(bash "$SESHSAVE" 2>&1 >/dev/null)"
  assert_has "a failed hyprctl query leaves the snapshot intact" "intact" "$(snap)"
  assert_has "a fail-closed save says why on stderr" "Hyprland query failed" "$err"
  clean_env
}
t_save_history(){ newtmp; export HOME="$TMP"; mksave
  H="$TMP/.local/state/sesh/history"
  bash "$SESHSAVE"; c1="$(ls "$H" 2>/dev/null | wc -l | tr -d ' ')"
  mkreg 303 "aaaaaaaa-0000-0000-0000-000000000303" "/w/argo" 4 interactive 3000000   # only updatedAt moves
  bash "$SESHSAVE"; c2="$(ls "$H" | wc -l | tr -d ' ')"
  mkreg 341 "dddddddd-0000-0000-0000-000000000341" "/w/y" 8 interactive              # the set changes
  bash "$SESHSAVE"; c3="$(ls "$H" | wc -l | tr -d ' ')"
  if [ "$c1" = 1 ] && [ "$c2" = 1 ] && [ "$c3" = 2 ]; then ok "history adds a file only when the set changes"; else no "history counts should be 1/1/2 (got $c1/$c2/$c3)"; fi
  for i in $(seq 10 34); do touch -t "2001010100$i" "$H/old$i.json"; done
  rm -f "$TMP/.claude/sessions/341.json"; bash "$SESHSAVE"
  c4="$(ls "$H" | wc -l | tr -d ' ')"
  if [ "$c4" = 20 ]; then ok "history is pruned to the newest 20"; else no "history should hold 20 files (got $c4)"; fi
  clean_env
}
t_save_darwin_unchanged(){ newtmp; export HOME="$TMP"
  mkdir -p "$TMP/.claude/sessions"
  printf '{"pid":%s,"sessionId":"mac-1","cwd":"/Users/x"}\n' "$$" > "$TMP/.claude/sessions/$$.json"
  SESH_UNAME=Darwin SESH_SKIP_BOOTGUARD=1 bash "$SESHSAVE"
  out="$(snap)"
  assert_has    "darwin save keeps id and cwd"     '"id": "mac-1"' "$out"
  assert_hasnt  "darwin save adds no instance"     'instance'      "$out"
  assert_hasnt  "darwin save adds no placement"    '"ws"'          "$out"
  assert_hasnt  "darwin save adds no updated"      'updated'       "$out"
  assert_nofile "darwin save writes no history"    "$TMP/.local/state/sesh/history"
}
t_save_odd_updatedat(){ newtmp; export HOME="$TMP"; mksave
  mkreg 312 "bbbbbbbb-0000-0000-0000-000000000312" "/w/three" 5 interactive '"2026-10-19T10:00:00Z"'
  bash "$SESHSAVE"
  assert_has "linux saves a session whose updatedAt is not a number" "bbbbbbbb" "$(snap)"
  clean_env
  H2="$TMP/mac"; mkdir -p "$H2/.claude/sessions" "$H2/.local/state/sesh"
  printf '{"pid":%s,"sessionId":"mac-2","cwd":"/Users/x","updatedAt":"soon"}\n' "$$" > "$H2/.claude/sessions/$$.json"
  HOME="$H2" SESH_UNAME=Darwin SESH_SKIP_BOOTGUARD=1 bash "$SESHSAVE"
  assert_has "darwin saves a session whose updatedAt is not a number, as before" '"id": "mac-2"' "$(cat "$H2/.local/state/sesh/snapshot.json" 2>/dev/null)"
}
t_save_stale_signature(){ newtmp; export HOME="$TMP"; mksave
  # After a compositor crash the systemd manager still holds the old signature. The gate
  # must aim hyprctl at the live instance, or every save would fail closed.
  HYPR_REQUIRE_SIG=1 HYPRLAND_INSTANCE_SIGNATURE=STALE bash "$SESHSAVE"
  assert_has "save reaches the live instance despite a stale signature in the env" "aaaaaaaa" "$(snap)"
  clean_env
}
echo "# sesh-local --sid"
t_local_sid(){ newtmp; export HOME="$TMP"
  mkdir -p "$TMP/work dir"
  f="$(mkproj projS 12345678-aaaa-bbbb-cccc-000000000001 yes "T" "x")"
  sed -i.bak "s#/Users/vania/Projects/projS#$TMP/work dir#" "$f"
  out="$(SESH_DRYRUN=1 bash "$_BIN/sesh-local" --sid 12345678-aaaa-bbbb-cccc-000000000001 </dev/null)"
  assert_has "--sid reads the cwd from the transcript"  "would run in $TMP/work dir as" "$out"
  assert_has "--sid titles the window with the id"      'as "claude · 12345678"' "$out"
  assert_has "--sid resumes that session"               "ccf --resume 12345678-aaaa-bbbb-cccc-000000000001" "$out"
  assert_has "--sid keeps the window open with a shell" 'then exec $SHELL -i' "$out"
  out="$(SESH_DRYRUN=1 bash "$_BIN/sesh-local" --sid 99999999-aaaa-bbbb-cccc-000000000009 </dev/null)"
  assert_has "--sid without a transcript falls back to HOME" "would run in $TMP as" "$out"
}
t_local_real_run(){ newtmp; export HOME="$TMP"
  # A real (not dry) run with a fake claude, so no Claude starts. stdin is closed and
  # SHELL is a recorder, so the --sid form's final exec cannot wait for input.
  mkdir -p "$TMP/.local/bin" "$TMP/work"
  printf '#!/bin/bash\necho "$PWD|$*" > "%s/fake/claude.ran"\nexit 3\n' "$TMP" > "$TMP/.local/bin/claude"; chmod +x "$TMP/.local/bin/claude"
  printf '#!/bin/bash\necho "$*" > "%s/fake/shell.ran"\n' "$TMP" > "$TMP/fake/shell"; chmod +x "$TMP/fake/shell"
  SESH_DRYRUN= SHELL="$TMP/fake/shell" bash "$_BIN/sesh-local" "$TMP/work" myname --resume abc </dev/null >/dev/null; rc=$?
  if [ "$rc" = 3 ]; then ok "the existing form exits with claude's status, as before"; else no "the existing form should exit 3 (got $rc)"; fi
  assert_nofile "the existing form does not start a shell" "$TMP/fake/shell.ran"
  f="$(mkproj projR 12345678-aaaa-bbbb-cccc-000000000002 no "" "x")"
  sed -i.bak "s#/Users/vania/Projects/projR#$TMP/work#" "$f"
  SESH_DRYRUN= SHELL="$TMP/fake/shell" bash "$_BIN/sesh-local" --sid 12345678-aaaa-bbbb-cccc-000000000002 </dev/null >/dev/null
  assert_has  "--sid resumes in the transcript's cwd" "$TMP/work|--dangerously-skip-permissions --resume 12345678-aaaa-bbbb-cccc-000000000002" "$(cat "$TMP/fake/claude.ran" 2>/dev/null)"
  assert_file "--sid drops to the user's shell after claude exits" "$TMP/fake/shell.ran"
}
echo "# Hyprland placement (dry-run Lua)"
t_spawn_placed_rules(){ newtmp; export HOME="$TMP"
  export SESH_UNAME=Linux SESH_DRYRUN=1
  id=aaaaaaaa-0000-0000-0000-000000000001
  stage='[workspace special:sesh-stage silent] foot '
  out="$(run_fn _spawn_placed "$id" argo)"
  assert_has "a named workspace gets a silent rule"      '[workspace name:argo silent] foot ' "$out"
  assert_has "only the uuid follows sesh-local --sid"     "/sesh-local --sid $id\"))" "$out"
  out="$(run_fn _spawn_placed "$id" 3)"
  assert_has "a numbered workspace rule"                  '[workspace 3 silent] foot ' "$out"
  out="$(run_fn _spawn_placed "$id" special:stash)"
  assert_has "the stash rule"                             '[workspace special:stash silent] foot ' "$out"
  out="$(run_fn _spawn_placed "$id" 'my"q"\ws')"
  assert_has "quotes and backslashes are escaped for Lua" '[workspace name:my\"q\"\\ws silent]' "$out"
  out="$(run_fn _spawn_placed "$id" 'pinley cicd')"
  assert_has "a name with a space is staged (rules split on whitespace)" "$stage" "$out"
  out="$(run_fn _spawn_placed "$id" 'a]b')"
  assert_has "a name holding ] is staged"                 "$stage" "$out"
  out="$(run_fn _spawn_placed "$id" 'a;b')"
  assert_has "a name holding ; is staged"                 "$stage" "$out"
  out="$(run_fn _spawn_placed "$id" 'a[b')"
  assert_has "a name holding [ is staged"                 "$stage" "$out"
  out="$(run_fn _spawn_placed "$id" '')"
  assert_has "no workspace opens unplaced"                'exec_cmd("foot ' "$out"
  out="$(run_fn _spawn_placed 'x; touch /tmp/p #' argo)"; rc=$?
  if [ "$rc" = 1 ] && [ -z "$out" ]; then ok "a non-uuid id is refused"; else no "a non-uuid id should be refused (rc $rc, out '$out')"; fi
  clean_env
}
t_move_lua(){ newtmp; export HOME="$TMP"
  export SESH_UNAME=Linux SESH_DRYRUN=1
  out="$(run_fn _move_window 0xa1 argo)"
  assert_has "window move by address, no follow" 'hl.dsp.window.move({ workspace = "name:argo", follow = false, window = "address:0xa1" })' "$out"
  out="$(run_fn _move_window 0xa1 3)"
  assert_has "a numbered target is a bare number" 'workspace = 3,' "$out"
  out="$(run_fn _move_window 0xa1 special:stash)"
  assert_has "a special target keeps its prefix" 'workspace = "special:stash",' "$out"
  out="$(run_fn _move_window 0xa1 'pinley cicd')"
  assert_has "a move takes a name with a space" 'workspace = "name:pinley cicd",' "$out"
  out="$(run_fn _move_workspace argo DP-1)"
  assert_has "workspace move to a monitor" 'hl.dsp.workspace.move({ workspace = "name:argo", monitor = "DP-1" })' "$out"
  out="$(run_fn _move_workspace argo 'DP"1')"
  assert_has "the monitor name is escaped for Lua" 'monitor = "DP\"1"' "$out"
  clean_env
}
echo "# sesh-restore on Linux"
t_restore_linux_dry(){ newtmp; export HOME="$TMP"; mkrestore
  out="$(SESH_DRYRUN=1 bash "$SESHRESTORE" 2>&1)"
  assert_has    "a dry run plans a placed spawn"         '[workspace name:argo silent] foot ' "$out"
  assert_has    "a numbered workspace is planned"        '[workspace 3 silent] foot ' "$out"
  assert_nofile "a dry run spawns nothing"               "$TMP/hypr/eval.log"
  assert_nofile "a dry run writes no marker"             "$TMP/.local/state/sesh/restored"
  assert_hasnt  "remote entries are not restored on linux" "sesh-remote" "$out"
  clean_env
}
t_restore_linux_cap_order(){ newtmp; export HOME="$TMP"; mkrestore
  out="$(SESH_CAP=2 SESH_DRYRUN=1 bash "$SESHRESTORE" 2>&1)"
  assert_has   "the cap keeps the newest (id 3, updated 300)" "--sid aaaaaaaa-0000-0000-0000-000000000003" "$out"
  assert_has   "the cap keeps the newest (id 1, updated 200)" "--sid aaaaaaaa-0000-0000-0000-000000000001" "$out"
  assert_hasnt "the cap drops the oldest (id 2, updated 100)" "--sid aaaaaaaa-0000-0000-0000-000000000002" "$out"
  first="$(printf '%s\n' "$out" | grep -o -- '--sid [0-9a-f-]*' | head -1)"
  if [ "$first" = "--sid aaaaaaaa-0000-0000-0000-000000000001" ]; then ok "spawns follow snapshot order, not updated order"; else no "the first spawn should be id 1 (got '$first')"; fi
  assert_has   "entries over the cap are logged" "over the cap" "$(cat "$TMP/.local/state/sesh/restore.log" 2>/dev/null)"
  clean_env
}
t_restore_linux_skips(){ newtmp; export HOME="$TMP"; mkrestore
  mkstat 900 claude 1 55; mkreg 900 "aaaaaaaa-0000-0000-0000-000000000001" "$TMP/w/argo" 55   # id 1 is running
  rm -f "$TMP"/.claude/projects/p2/*.jsonl                                                   # id 2 has no transcript
  rmdir "$TMP/w/argo3"                                                                       # id 3 lost its cwd
  SESH_DRYRUN=1 bash "$SESHRESTORE" >/dev/null 2>&1
  log="$(cat "$TMP/.local/state/sesh/restore.log" 2>/dev/null)"
  assert_has "a running session is skipped"    "aaaaaaaa-0000-0000-0000-000000000001 (already running)" "$log"
  assert_has "a missing transcript is skipped" "aaaaaaaa-0000-0000-0000-000000000002 (no transcript)"   "$log"
  assert_has "a missing cwd is skipped"        "aaaaaaaa-0000-0000-0000-000000000003 (cwd gone"         "$log"
  assert_has "remote entries are skipped"      "remote session(s) (not restored on linux)"              "$log"
  clean_env
}
t_restore_linux_full(){ newtmp; export HOME="$TMP"; mkrestore
  export HYPR_SIMULATE=1 HYPR_LAND_WS=1       # every window lands on workspace 1, so the fix must move it
  bash "$SESHRESTORE" >/dev/null 2>&1
  ev="$(evals)"
  assert_has    "spawned through a silent exec rule" 'exec_cmd("[workspace name:argo silent] foot ' "$ev"
  assert_has    "a misplaced window is moved back"   'window.move({ workspace = "name:argo", follow = false, window = "address:0xf' "$ev"
  assert_file   "the marker is written"              "$TMP/.local/state/sesh/restored"
  assert_has    "the marker holds this instance"     "SIG1" "$(cat "$TMP/.local/state/sesh/restored" 2>/dev/null)"
  assert_nofile "the lock is released"               "$TMP/.local/state/sesh/restore.lock"
  assert_has    "one notification with the count"    "restored 3 of 3" "$(cat "$TMP/fake/notify.log" 2>/dev/null)"
  clean_env
}
t_restore_linux_monitor_fix(){ newtmp; export HOME="$TMP"; mkrestore
  export HYPR_SIMULATE=1 HYPR_LAND_MON=DP-2   # new workspaces appear on DP-2
  bash "$SESHRESTORE" >/dev/null 2>&1
  ev="$(evals)"
  assert_has   "a new workspace moves to its saved monitor" 'workspace.move({ workspace = "name:argo", monitor = "DP-1" })' "$ev"
  assert_hasnt "a workspace already on its monitor stays"   'workspace.move({ workspace = 3' "$ev"
  clean_env
}
t_restore_linux_marker_paths(){ newtmp; export HOME="$TMP"; mkrestore
  printf '{"saved_at":"t","instance":"OLD","local":[],"remote":[]}\n' > "$TMP/.local/state/sesh/snapshot.json"
  bash "$SESHRESTORE" >/dev/null 2>&1
  assert_has "the marker is written even when nothing opens" "SIG1" "$(cat "$TMP/.local/state/sesh/restored" 2>/dev/null)"
  rm -f "$TMP/.local/state/sesh/restored"
  ( unset HYPRLAND_INSTANCE_SIGNATURE; bash "$SESHRESTORE" >/dev/null 2>&1 )
  assert_nofile "no marker outside a Hyprland session" "$TMP/.local/state/sesh/restored"
  clean_env
}
t_restore_linux_lock(){ newtmp; export HOME="$TMP"; mkrestore
  mkdir -p "$TMP/.local/state/sesh/restore.lock"; mkstat 4444 bash 1 12
  printf '4444 12\n' > "$TMP/.local/state/sesh/restore.lock/pid"   # a live restore holds the lock
  bash "$SESHRESTORE" >/dev/null 2>&1
  assert_nofile "a held lock stops a second restore" "$TMP/hypr/eval.log"
  rm -f "$TMP/proc/4444/stat"                                       # the holder died: the lock is stale
  HYPR_SIMULATE=1 bash "$SESHRESTORE" >/dev/null 2>&1
  assert_file "a stale lock is taken over" "$TMP/hypr/eval.log"
  clean_env
}
t_restore_linux_not_started(){ newtmp; export HOME="$TMP"; mkrestore
  bash "$SESHRESTORE" >/dev/null 2>&1   # no HYPR_SIMULATE: nothing comes up
  assert_has "the notification counts sessions that did not start" "didn't start 3" "$(cat "$TMP/fake/notify.log" 2>/dev/null)"
  assert_has "the marker is written after failed spawns" "SIG1" "$(cat "$TMP/.local/state/sesh/restored" 2>/dev/null)"
  clean_env
}
t_save_drops_stage(){ newtmp; export HOME="$TMP"; mksave
  mkreg 381 "ffffffff-0000-0000-0000-000000000381" "/w/staged" 12 interactive
  bash "$SESHSAVE"
  ws="$(jq -r '.local[] | select(.id | startswith("ffffffff")) | .ws // "none"' "$TMP/.local/state/sesh/snapshot.json" 2>/dev/null)"
  if [ "$ws" = none ]; then ok "a window left on the stage is saved without placement"; else no "a staged window should have no saved ws (got '$ws')"; fi
  clean_env
}
t_restore_linux_staged(){ newtmp; export HOME="$TMP"; mkrestore
  # "pinley cicd" cannot sit in an exec rule (Hyprland splits on whitespace), so it is staged
  # and then moved by address. The fake does not apply moves, so the window stays staged.
  jq '.local = [.local[0] | .ws = "pinley cicd"]' "$TMP/.local/state/sesh/snapshot.json" > "$TMP/s.tmp" && mv "$TMP/s.tmp" "$TMP/.local/state/sesh/snapshot.json"
  HYPR_SIMULATE=1 bash "$SESHRESTORE" >/dev/null 2>&1
  ev="$(evals)"
  assert_has "a spaced name spawns on the stage"          'exec_cmd("[workspace special:sesh-stage silent] foot ' "$ev"
  assert_has "verify moves it to its workspace by address" 'window.move({ workspace = "name:pinley cicd", follow = false, window = "address:0xf' "$ev"
  assert_has "a window left on the stage is reported"     "still staged 1" "$(cat "$TMP/fake/notify.log" 2>/dev/null)"
  clean_env
}
t_restore_linux_stale_sig(){ newtmp; export HOME="$TMP"; mkrestore
  # A shell that outlived a compositor restart still names the dead instance (OLDSIG).
  HYPRLAND_INSTANCE_SIGNATURE=OLDSIG HYPR_REQUIRE_SIG=1 HYPR_SIMULATE=1 bash "$SESHRESTORE" >/dev/null 2>&1
  assert_has "a stale signature adopts the single live instance" "SIG1" "$(cat "$TMP/.local/state/sesh/restored" 2>/dev/null)"
  assert_has "the restore then reaches the live compositor" 'exec_cmd("[workspace name:argo silent] foot ' "$(evals)"
  rm -f "$TMP/.local/state/sesh/restored" "$TMP/hypr/eval.log"
  printf '[]\n' > "$TMP/hypr/instances.json"
  HYPRLAND_INSTANCE_SIGNATURE=OLDSIG bash "$SESHRESTORE" >/dev/null 2>&1
  assert_nofile "no live instance: no marker" "$TMP/.local/state/sesh/restored"
  clean_env
}
RUN="t_aititle t_userfallback t_hosts_env t_hosts_file t_hosts_default t_hosts_single_fallback t_hosts_single_legacy
     t_self_env t_self_hostname_match t_self_near_miss
     t_cache_hit t_cache_miss_mtime
     t_remote_fresh_skips_ssh t_remote_stale_fail_fallback
     t_remote_success_refresh t_remote_success_empty
     t_multihost_emit t_multihost_fallback t_self_vs_remote
     t_open_self_plain t_open_self_in_tmux t_open_self_in_tmux_real t_open_self_newwin
     t_open_here t_spawn_branches t_mtime_real t_open_remote_passes_host
     t_hxconnect_host_marker t_save_host_namespaced t_save_migrates_live_flat
     t_restore_jq_contract t_restore_opens_per_host t_restore_legacy_uses_sesh_host"
RUN="$RUN t_lib_via_symlink"
RUN="$RUN t_proc_stat_parse t_alive_procstart t_want_session"
RUN="$RUN t_capture_cases t_capture_fail_closed t_capture_darwin"
RUN="$RUN t_save_linux_placement t_save_skips_dead_and_kinds t_save_gate t_save_first_run t_save_fail_closed t_save_history t_save_darwin_unchanged t_save_odd_updatedat t_save_stale_signature t_save_drops_stage"
RUN="$RUN t_local_sid t_local_real_run"
RUN="$RUN t_spawn_placed_rules t_move_lua"
RUN="$RUN t_restore_linux_dry t_restore_linux_cap_order t_restore_linux_skips t_restore_linux_full t_restore_linux_monitor_fix t_restore_linux_marker_paths t_restore_linux_lock t_restore_linux_not_started t_restore_linux_staged t_restore_linux_stale_sig"
# SESH_TEST_ONLY="t_a t_b" runs just those tests (the red step of a TDD cycle).
[ -n "${SESH_TEST_ONLY:-}" ] && RUN="$SESH_TEST_ONLY"
for t in $RUN; do
  "$t"
  [ -n "${TMP:-}" ] && rm -rf "$TMP"
done

echo "# ---"
echo "# passed $P, failed $F"
[ "$F" -eq 0 ]
