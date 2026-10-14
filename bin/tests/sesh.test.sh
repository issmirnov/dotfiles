#!/bin/bash
# Tests for `sesh` cache + same-window logic. Sources sesh as a library and
# calls its functions against a throwaway $HOME, injecting the ssh call via
# $SESH_SSH so no network is touched.
#
#   bash ~/.dotfiles/bin/tests/sesh.test.sh
#
# Sesh must be sourceable without running main (BASH_SOURCE guard), and must
# expose: name_of, _cwd_of, candidates, do_open.
SESH="${SESH_BIN:-$HOME/.dotfiles/bin/sesh}"
HXCONNECT="$HOME/.dotfiles/bin/hx-connect"
SESHSAVE="$HOME/.dotfiles/bin/sesh-save"
SESHRESTORE="$HOME/.dotfiles/bin/sesh-restore"
P=0; F=0
ok(){ P=$((P+1)); echo "ok $((P+F)) - $1"; }
no(){ F=$((F+1)); echo "NOT OK $((P+F)) - $1"; }
has(){ case "$2" in *"$1"*) return 0;; *) return 1;; esac; }   # has <needle> <haystack>
assert_has(){ if has "$2" "$3"; then ok "$1"; else no "$1 (missing: $2)"; fi; }
assert_hasnt(){ if has "$2" "$3"; then no "$1 (unexpected: $2)"; else ok "$1"; fi; }
assert_file(){ if [ -e "$2" ]; then ok "$1"; else no "$1 (no file: $2)"; fi; }
assert_nofile(){ if [ -e "$2" ]; then no "$1 (file present: $2)"; else ok "$1"; fi; }

newtmp(){ TMP="$(mktemp -d)"; mkdir -p "$TMP/.claude/projects" "$TMP/.local/state/sesh" "$TMP/fake"; }

# mkproj <proj> <id> <ai:yes|no> <title> <usercontent>  -> prints jsonl path
mkproj(){ local d="$TMP/.claude/projects/$1"; mkdir -p "$d"; local f="$d/$2.jsonl"; : >"$f"
  printf '{"type":"user","cwd":"/Users/vania/Projects/%s","message":{"role":"user","content":"%s"}}\n' "$1" "$5" >>"$f"
  [ "$3" = yes ] && printf '{"type":"ai-title","aiTitle":"%s"}\n' "$4" >>"$f"
  printf '%s' "$f"; }

# run_fn <fn> <args...> : source sesh in a clean subshell and call a function.
# Relies on exported HOME + SESH_* env already set by the caller.
run_fn(){ ( set +u; source "$SESH" >/dev/null 2>&1; "$@" ) </dev/null; }

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

echo "# hx-connect host-aware"
t_hxconnect_host_marker(){ newtmp; export HOME="$TMP"
  # fake mosh records its argv AND whether the host-namespaced marker exists at call time
  printf '#!/bin/bash\n[ -e "%s/.local/state/sesh/remote/dev-2/web" ] && echo OK > "%s/fake/mark"\necho "$@" > "%s/fake/argv"\n' "$TMP" "$TMP" "$TMP" > "$TMP/fake/mosh"
  chmod +x "$TMP/fake/mosh"
  HX_MOSH="$TMP/fake/mosh" bash "$HXCONNECT" dev-2 web
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

echo "# sesh-restore host-aware"
# Contract: the jq read defaults a missing host to hexane.
t_restore_jq_contract(){
  local EXPR='.remote[]? | [(.host // "hexane"), .session] | @tsv'
  out="$(printf '%s' '{"remote":[{"host":"dev-1","session":"api"}]}' | jq -rc "$EXPR")"
  assert_has "new format keeps host"         "$(printf 'dev-1\tapi')"    "$out"
  out="$(printf '%s' '{"remote":[{"session":"legacy"}]}' | jq -rc "$EXPR")"
  assert_has "old format defaults to hexane"  "$(printf 'hexane\tlegacy')" "$out"
}
# Integration: dry-run restore must call hx-connect with host THEN session.
t_restore_opens_per_host(){ newtmp; export HOME="$TMP"
  printf '{"saved_at":"t","local":[],"remote":[{"host":"dev-1","session":"api"},{"session":"legacy"}]}' > "$TMP/.local/state/sesh/snapshot.json"
  out="$(SESH_DRYRUN=1 bash "$SESHRESTORE" 2>&1)"
  assert_has "restore opens new-format host:session" "hx-connect dev-1 api" "$out"
  assert_has "restore defaults old-format to hexane"  "hx-connect hexane legacy" "$out"
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

for t in t_aititle t_userfallback t_hosts_env t_hosts_file t_hosts_default \
         t_cache_hit t_cache_miss_mtime \
         t_remote_fresh_skips_ssh t_remote_stale_fail_fallback \
         t_remote_success_refresh t_remote_success_empty \
         t_multihost_emit t_multihost_fallback \
         t_open_here t_spawn_branches t_mtime_real t_open_remote_passes_host \
         t_hxconnect_host_marker t_save_host_namespaced \
         t_restore_jq_contract t_restore_opens_per_host; do
  "$t"
  [ -n "${TMP:-}" ] && rm -rf "$TMP"
done

echo "# ---"
echo "# passed $P, failed $F"
[ "$F" -eq 0 ]
