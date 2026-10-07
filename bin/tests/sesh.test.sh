#!/bin/bash
# Tests for `sesh` cache + same-window logic. Sources sesh as a library and
# calls its functions against a throwaway $HOME, injecting the ssh call via
# $SESH_SSH so no network is touched.
#
#   bash ~/.dotfiles/bin/tests/sesh.test.sh
#
# Sesh must be sourceable without running main (BASH_SOURCE guard), and must
# expose: name_of, _cwd_of, candidates, do_open.
SESH="$HOME/.dotfiles/bin/sesh"
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

echo "# local label cache (mtime-keyed)"
t_cache_hit(){ newtmp; export HOME="$TMP"
  f="$(mkproj projA idAAAAAAAAAA yes "Real Title A" "hello")"
  mt="$(stat -f %m "$f")"
  printf '%s\t%s\t%s\t%s\n' "$f" "$mt" "/tmp/seedcwd" "SENTINEL_CACHED" > "$TMP/.local/state/sesh/labels.tsv"
  out="$(run_fn candidates)"
  assert_has   "cache hit reuses cached label" "SENTINEL_CACHED" "$out"
  assert_hasnt "cache hit skips recompute"     "Real Title A"    "$out"
}
t_cache_miss_mtime(){ newtmp; export HOME="$TMP"
  f="$(mkproj projA idAAAAAAAAAA yes "Real Title A" "hello")"
  # seed with a STALE mtime so it no longer matches the file -> recompute
  printf '%s\t%s\t%s\t%s\n' "$f" "100000000" "/tmp/seedcwd" "SENTINEL_CACHED" > "$TMP/.local/state/sesh/labels.tsv"
  out="$(run_fn candidates)"
  assert_has   "mtime change recomputes label" "Real Title A"    "$out"
  assert_hasnt "stale cache entry discarded"    "SENTINEL_CACHED" "$out"
}

echo "# remote TTL cache + offline fallback"
t_remote_fresh_skips_ssh(){ newtmp; export HOME="$TMP"
  echo cachedsess > "$TMP/.local/state/sesh/remote.list"; touch "$TMP/.local/state/sesh/remote.list"
  printf '#!/bin/bash\ntouch "%s/fake/ssh.called"\nexit 1\n' "$TMP" > "$TMP/fake/ssh"; chmod +x "$TMP/fake/ssh"
  export SESH_SSH="$TMP/fake/ssh" SESH_REMOTE_TTL=600
  out="$(run_fn candidates)"
  assert_has    "fresh cache served"        "[hexane] cachedsess" "$out"
  assert_nofile "fresh cache does not ssh"  "$TMP/fake/ssh.called"
  unset SESH_SSH SESH_REMOTE_TTL
}
t_remote_stale_fail_fallback(){ newtmp; export HOME="$TMP"
  echo ghostsess > "$TMP/.local/state/sesh/remote.list"; touch -t 200001010000 "$TMP/.local/state/sesh/remote.list"
  printf '#!/bin/bash\nexit 255\n' > "$TMP/fake/ssh"; chmod +x "$TMP/fake/ssh"
  export SESH_SSH="$TMP/fake/ssh" SESH_REMOTE_TTL=60
  out="$(run_fn candidates)"
  assert_has  "stale cache served on ssh failure" "[hexane] ghostsess" "$out"
  assert_file "failure records negative-cache marker" "$TMP/.local/state/sesh/remote.fail"
  unset SESH_SSH SESH_REMOTE_TTL
}
t_remote_success_refresh(){ newtmp; export HOME="$TMP"
  echo oldsess > "$TMP/.local/state/sesh/remote.list"; touch -t 200001010000 "$TMP/.local/state/sesh/remote.list"
  : > "$TMP/.local/state/sesh/remote.fail"   # seeded marker that a successful refresh must clear
  printf '#!/bin/bash\nprintf "newA\\nnewB\\n"; echo __SESH_OK__\n' > "$TMP/fake/ssh"; chmod +x "$TMP/fake/ssh"
  export SESH_SSH="$TMP/fake/ssh" SESH_REMOTE_TTL=60 SESH_REFRESH=1   # -r forces the attempt past the negative-cache
  out="$(run_fn candidates)"
  assert_has    "refresh shows new sessions"   "[hexane] newA" "$out"
  assert_has    "refresh shows all new"        "[hexane] newB" "$out"
  assert_hasnt  "refresh drops stale session"  "oldsess"       "$out"
  assert_nofile "success clears negative-cache" "$TMP/.local/state/sesh/remote.fail"
  unset SESH_SSH SESH_REMOTE_TTL SESH_REFRESH
}
t_remote_success_empty(){ newtmp; export HOME="$TMP"
  echo oldsess > "$TMP/.local/state/sesh/remote.list"; touch -t 200001010000 "$TMP/.local/state/sesh/remote.list"
  printf '#!/bin/bash\necho __SESH_OK__\n' > "$TMP/fake/ssh"; chmod +x "$TMP/fake/ssh"  # connected, zero sessions
  export SESH_SSH="$TMP/fake/ssh" SESH_REMOTE_TTL=60
  out="$(run_fn candidates)"
  assert_hasnt "connected+empty clears stale sessions" "oldsess" "$out"
  unset SESH_SSH SESH_REMOTE_TTL
}

echo "# do_open window mode (dry-run)"
t_open_here(){ newtmp; export HOME="$TMP"
  export SESH_DRYRUN=1
  out="$(run_fn do_open ccx /some/dir thename --resume theid)"
  assert_has   "default opens in current window (exec)" "here" "$out"
  assert_hasnt "default is not a new window"            "newwin" "$out"
  unset SESH_DRYRUN
}
t_open_newwin(){ newtmp; export HOME="$TMP"
  export SESH_DRYRUN=1 SESH_NEWWIN=1
  out="$(run_fn do_open ccx /some/dir thename --resume theid)"
  assert_has "SESH_NEWWIN forces a new window" "newwin" "$out"
  unset SESH_DRYRUN SESH_NEWWIN
}

for t in t_aititle t_userfallback t_cache_hit t_cache_miss_mtime \
         t_remote_fresh_skips_ssh t_remote_stale_fail_fallback \
         t_remote_success_refresh t_remote_success_empty \
         t_open_here t_open_newwin; do
  "$t"
  [ -n "${TMP:-}" ] && rm -rf "$TMP"
done

echo "# ---"
echo "# passed $P, failed $F"
[ "$F" -eq 0 ]
