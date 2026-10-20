# sesh Linux auto-save and login restore (B2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On hexane, save the Claude sessions open in foot windows every 60 s, with each window's Hyprland workspace and monitor, and reopen them there, without moving focus, when Hyprland starts.

**Architecture:** A new sourced file, `sesh/lib/os.sh`, holds every OS-specific primitive: window spawn, process liveness, Hyprland window capture, the save gate and Hyprland placement. `sesh-save` gains a Linux path (gate, placement, history). `sesh-restore` gains a separate Linux function (lock, cap, placed spawns, verify, fixes, marker, notification), and its macOS loop stays byte-for-byte. A systemd user timer runs the save, and `hyprland.lua` runs the restore at `hyprland.start`.

**Tech Stack:** Bash (macOS `/bin/bash` 3.2.57 and Arch bash 5.3), jq 1.8.2, Hyprland 0.56.2 (Lua config, runtime control through `hyprctl eval`), foot 1.28, systemd `--user`. Tests use the existing harness `sesh/tests/sesh.test.sh` with a temp `$HOME`, a fake `hyprctl`, a fake `/proc` and dry runs. No network, no real windows.

**Spec:** `sesh/docs/2026-10-19-sesh-linux-b2-design.md`
**Branch and worktree:** `feat/sesh-linux-b2` at `/home/vania/.dotfiles/.claude/worktrees/sesh-linux-b2`. It already holds the spec and has no upstream.

## Global Constraints

- `WT=/home/vania/.dotfiles/.claude/worktrees/sesh-linux-b2`. Edit files only under `$WT`. Never edit, check out, stash or reset `/home/vania/.dotfiles`: other sessions use that checkout. Never edit live files under `~/.config`.
- Run the suite against the worktree: `SESH_BIN="$WT/sesh/sesh" bash "$WT/sesh/tests/sesh.test.sh"`. Without `SESH_BIN` it tests the main checkout. `SESH_TEST_ONLY="t_a t_b"` (added in Task 1) runs only the named tests.
- Commit from the worktree with hooks off. The trailer is the last paragraph:
  `git -C "$WT" -c core.hooksPath=/dev/null commit -m "<subject>" -m "<body>" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"`
  The repo's hooks would run the main checkout's `./install`. Never push. The controller opens the PR in Task 10.
- The Bash tool runs zsh. Unquoted `$VAR` is not word-split, `PIPESTATUS` does not exist, and `noclobber` is on, so `>` onto an existing file fails (use `>|`). Run scripts with `bash`.
- `sesh/lib/os.sh` must parse under bash 3.2: no associative arrays, no `mapfile`, no `${x,,}`, no `declare -A`, and `sed` (not `${var//…}`) for backslash escaping. Callers run with `set -u`, so initialize every `local`.
- The Mac behaves exactly as today. The macOS restore loop stays byte-for-byte, and a macOS save writes only `saved_at`, `local[].id`, `local[].cwd` and `remote`.
- Only a session UUID and fixed paths go into a Hyprland command string. Workspace names are escaped for a Lua double-quoted string: `\` becomes `\\`, and `"` becomes `\"`.
- Never add a `monitor` rule to an exec. On Hyprland 0.56.2 it moves focus and warps the cursor (probed).
- Saving fails closed. If any `hyprctl` or `jq` call fails, `sesh-save` exits without writing.
- Defaults: `SESH_CAP` 20 on Linux and 12 on macOS, `SESH_STAGGER` 1.5 s, `SESH_VERIFY_WAIT` 15 s, 20 history files, and the timer every 60 s.
- Tests never reach the live compositor. The suite sets `SESH_HYPRCTL=false`, and tests that need Hyprland install the fake from `mkhypr`.
- New prose (README, docs, commit messages) has no em-dashes. Code comments follow the file's existing style.

---

## File structure

| File | Change | Task |
|---|---|---|
| `sesh/lib/os.sh` | New. OS detection, `_mtime`, `_spawn_window` (Task 1); `_proc_stat`, `_alive`, `_want_session` (2); `_capture_windows` (3); `_save_gate` (4); `_ws_lua`, `_hypr_eval`, `_spawn_placed`, `_move_window`, `_move_workspace` (6) | 1, 2, 3, 4, 6 |
| `sesh/sesh` | Resolve `SESH_DIR`, source the lib, drop the inline OS block. The Linux new-window default becomes foot | 1 |
| `sesh/sesh-save` | Rewritten: gate, Linux placement, history. The remote block is unchanged | 4 |
| `sesh/sesh-local` | `--sid <uuid>` form and a dry run | 5 |
| `sesh/sesh-restore` | Source the lib and add the Linux path. The macOS loop is unchanged | 7 |
| `sesh/tests/sesh.test.sh` | Hermetic `SESH_HYPRCTL`, a `RUN` list with `SESH_TEST_ONLY`, helpers and new tests. Four existing tests change | 1 to 7 |
| `sesh/systemd/sesh-save.service`, `sesh/systemd/sesh-save.timer` | New | 8 |
| `ubuntu.conf.yaml` | Link the units, and enable the timer where Hyprland is installed | 8 |
| `hypr/hyprland.lua` | Run `sesh-restore` in `hyprland.start` | 8 |
| `sesh/README.md` | Linux section, tables, limitations, test count | 9 |

The suite grows from 66 to 156 tests: 67 after Task 1, 74 after Task 2, 86 after Task 3, 114 after Task 4 (each of those two gained three assertions in review; see Revisions), 119 after Task 5, 129 after Task 6 and 156 after Task 7.

---

## Task 1: Shared OS layer and the picker

**Run from:** `$WT`

**Files:**
- Create: `sesh/lib/os.sh`
- Modify: `sesh/sesh` (header line 31; the block from `set -u` to the end of the OS `case`, lines 33 to 55)
- Modify: `sesh/tests/sesh.test.sh` (after `P=0; F=0`; the two `alacritty` assertions; the runner; one new test)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - In `lib/os.sh`: the globals `SESH_OS` (`darwin`, `linux` or `other`), `HYPRCTL` (from `SESH_HYPRCTL`, default `hyprctl`) and `PROC` (from `SESH_PROC`, default `/proc`).
  - `_mtime <file>` prints an epoch. `_spawn_window <argv…>` opens a new terminal window; on Linux it uses `${SESH_TERMINAL:-foot}`.
  - Every script that sources the lib first sets `SESH_DIR` with exactly this line, and sets `STATE` before it calls `_spawn_window`:
    `SESH_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"`
  - In the test file: the `RUN` list, the `SESH_TEST_ONLY` filter, and the default `SESH_HYPRCTL=false`.

- [ ] **Step 1: Make the test file hermetic and add the runner list**

In `sesh/tests/sesh.test.sh`, directly after the line `P=0; F=0`, add:

```bash
# Never reach the live compositor. Tests that need Hyprland install a fake (mkhypr).
export SESH_HYPRCTL=false
```

Replace the runner, from the line `for t in t_aititle t_userfallback …` through its closing `done`, with:

```bash
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
# SESH_TEST_ONLY="t_a t_b" runs just those tests (the red step of a TDD cycle).
[ -n "${SESH_TEST_ONLY:-}" ] && RUN="$SESH_TEST_ONLY"
for t in $RUN; do
  "$t"
  [ -n "${TMP:-}" ] && rm -rf "$TMP"
done
```

Later tasks add one `RUN="$RUN …"` line each, directly above the `# SESH_TEST_ONLY=` comment line.

- [ ] **Step 2: Write the failing tests**

In `t_open_self_newwin`, the `assert_has "new window spawns a terminal" …` line becomes:

```bash
  assert_has "new window spawns a terminal" "spawn[linux]: setsid -f foot -e tmux new-session -A -s mysess" "$out"
```

In `t_spawn_branches`, the `assert_has "linux new-window spawns via setsid+terminal" …` line becomes:

```bash
  assert_has "linux new-window spawns via setsid+terminal" "spawn[linux]: setsid -f foot -e" "$out"
```

Directly above the line that starts `RUN="t_aititle`, add:

```bash
echo "# lib/os.sh loading"
t_lib_via_symlink(){ newtmp; export HOME="$TMP"
  # The picker is reached through symlinks (~/bin/dotbin/sesh -> …/bin/sesh -> sesh/sesh),
  # and it must still find lib/os.sh beside its real file.
  mkdir -p "$TMP/bin"; ln -s "$SESH" "$TMP/bin/sesh"
  out="$( ( set +u; source "$TMP/bin/sesh" >/dev/null 2>&1; type _spawn_window >/dev/null 2>&1 && printf '%s' "$SESH_DIR" ) </dev/null )"
  want="$(cd "$_BIN" && pwd -P)"
  if [ "$out" = "$want" ]; then ok "sesh through a symlink resolves its real dir and loads lib/os.sh"; else no "SESH_DIR via symlink should be $want (got '$out')"; fi
}
```

- [ ] **Step 3: Run the suite and watch it fail**

Run: `SESH_BIN="$WT/sesh/sesh" bash "$WT/sesh/tests/sesh.test.sh" | tail -5`
Expected: three `NOT OK` lines (the two foot assertions and `SESH_DIR via symlink`), and the last line `# passed 64, failed 3`.

- [ ] **Step 4: Create `sesh/lib/os.sh`**

```bash
# sesh/lib/os.sh — OS-specific primitives shared by sesh, sesh-save and sesh-restore.
#
# Sourced, never executed. The caller sets SESH_DIR and STATE first. SESH_UNAME
# overrides $(uname) so the test suite drives every branch on one machine.
# Must parse under bash 3.2 (macOS /bin/bash): no associative arrays, no mapfile,
# no ${x,,}, and sed rather than ${var//} for backslash escaping. Callers run set -u.
#
# Seams: SESH_UNAME, SESH_DRYRUN, SESH_TERMINAL (Linux terminal, default foot),
#        SESH_TERMINAL_APP (macOS .app, default Ghostty), SESH_HYPRCTL (hyprctl
#        binary), SESH_PROC (/proc root).

case "${SESH_UNAME:-$(uname)}" in
  Darwin) SESH_OS=darwin ;;
  Linux)  SESH_OS=linux ;;
  *)      SESH_OS=other ;;
esac
HYPRCTL="${SESH_HYPRCTL:-hyprctl}"
PROC="${SESH_PROC:-/proc}"

# ---- files and new windows ---------------------------------------------------------
case "$SESH_OS" in
  darwin)
    _mtime(){ stat -f %m "$1" 2>/dev/null; }
    _spawn_window(){ if [ -n "${SESH_DRYRUN:-}" ]; then printf 'spawn[darwin]: open -na %s --args -e %s\n' "${SESH_TERMINAL_APP:-/Applications/Ghostty.app}" "$*"; return; fi
                     open -na "${SESH_TERMINAL_APP:-/Applications/Ghostty.app}" --args -e "$@"; } ;;
  linux)
    _mtime(){ stat -c %Y "$1" 2>/dev/null; }
    _spawn_window(){ if [ -n "${SESH_DRYRUN:-}" ]; then printf 'spawn[linux]: setsid -f %s -e %s\n' "${SESH_TERMINAL:-foot}" "$*"; return; fi
                     mkdir -p "$STATE" 2>/dev/null; setsid -f "${SESH_TERMINAL:-foot}" -e "$@" 2>>"$STATE/spawn.err"; } ;;
  *)
    _mtime(){ stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }
    _spawn_window(){ if [ -n "${SESH_DRYRUN:-}" ]; then printf 'spawn[other]: %s -e %s\n' "${SESH_TERMINAL:-xterm}" "$*"; return; fi
                     "${SESH_TERMINAL:-xterm}" -e "$@" & } ;;
esac
```

- [ ] **Step 5: Switch `sesh` to the lib**

In `sesh/sesh`, header line 31 becomes:

```bash
#        SESH_TERMINAL     Linux terminal binary for a new window (default foot)
```

Replace the block from `set -u` through the `esac` that closes the OS `case` (lines 33 to 55) with:

```bash
set -u
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
SESH_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
SESH_LOCAL="$HOME/.dotfiles/sesh/sesh-local"
SESH_REMOTE="$HOME/.dotfiles/sesh/sesh-remote"
PROJECTS="$HOME/.claude/projects"
STATE="$HOME/.local/state/sesh"
N="${SESH_LIST:-25}"

# OS-family primitives (_mtime, _spawn_window, …) live in lib/os.sh, shared with
# sesh-save and sesh-restore. SESH_UNAME overrides $(uname) so the suite drives both branches.
. "$SESH_DIR/lib/os.sh"
```

The `_age(){ … }` line that followed the `esac` stays where it is, directly after the new `. "$SESH_DIR/lib/os.sh"` line.

- [ ] **Step 6: Run the suite**

Run: `SESH_BIN="$WT/sesh/sesh" bash "$WT/sesh/tests/sesh.test.sh" | tail -2`
Expected: `# passed 67, failed 0`

- [ ] **Step 7: Commit**

```bash
git -C "$WT" add sesh/lib/os.sh sesh/sesh sesh/tests/sesh.test.sh
git -C "$WT" -c core.hooksPath=/dev/null commit -m "sesh: move OS primitives into lib/os.sh; Linux opens foot" \
  -m "lib/os.sh now holds _mtime and _spawn_window for all three scripts. Each script finds it through readlink -f, so a symlinked or worktree copy loads its own lib. The test runner gains a RUN list, SESH_TEST_ONLY and a hermetic SESH_HYPRCTL." \
  -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Process helpers

**Run from:** `$WT`

**Files:**
- Modify: `sesh/lib/os.sh` (append a section)
- Modify: `sesh/tests/sesh.test.sh` (helpers after `run_fn`; three tests; one `RUN` line)

**Interfaces:**
- Consumes: `SESH_OS`, `PROC` (Task 1).
- Produces:
  - `_proc_stat <pid>` prints `"<ppid> <starttime> <comm>"` (comm may contain spaces) from `$PROC/<pid>/stat`, or returns 1.
  - `_alive <pid> [procStart]` returns 0 when the process runs. On Linux the start time must also equal `procStart` when one is given. Other OSes use `kill -0`.
  - `_want_session <kind>`: on Linux only `interactive` (or an empty kind) passes. Other OSes accept every kind.
  - Test helpers: `mkstat <pid> <comm> <ppid> <starttime>` and `clean_env`.

- [ ] **Step 1: Add the test helpers**

In `sesh/tests/sesh.test.sh`, directly after the `run_fn(){ … }` line, add:

```bash

# mkstat <pid> <comm> <ppid> <starttime> : a fake $TMP/proc/<pid>/stat line, laid out
# as the kernel writes it (starttime is field 22 of the raw line).
mkstat(){ mkdir -p "$TMP/proc/$1"
  printf '%s (%s) S %s 0 0 0 0 0 0 0 0 0 0 0 0 0 20 0 1 0 %s 0 0\n' "$1" "$2" "$3" "$4" > "$TMP/proc/$1/stat"; }

# clean_env : unset everything the Linux tests export, so the next test starts clean.
clean_env(){ unset SESH_PROC SESH_UNAME SESH_DRYRUN SESH_SKIP_BOOTGUARD SESH_NOTIFY SESH_STAGGER SESH_VERIFY_WAIT \
                   SESH_MON_WAIT SESH_CAP HYPR_SIMULATE HYPR_LAND_WS HYPR_LAND_MON HYPRLAND_INSTANCE_SIGNATURE 2>/dev/null
             export SESH_HYPRCTL=false; }
```

- [ ] **Step 2: Write the failing tests**

Directly above the line that starts `RUN="t_aititle`, add:

```bash
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
```

Directly above the `# SESH_TEST_ONLY=` comment line, add:

```bash
RUN="$RUN t_proc_stat_parse t_alive_procstart t_want_session"
```

- [ ] **Step 3: Run the new tests and watch them fail**

Run: `SESH_TEST_ONLY="t_proc_stat_parse t_alive_procstart t_want_session" SESH_BIN="$WT/sesh/sesh" bash "$WT/sesh/tests/sesh.test.sh" 2>/dev/null | tail -2`
Expected: `# passed 3, failed 4` (the functions do not exist yet).

- [ ] **Step 4: Append the process section to `sesh/lib/os.sh`**

```bash

# ---- processes (Linux reads $PROC; other OSes use kill -0) ------------------------
# _proc_stat <pid> : print "<ppid> <starttime> <comm>" from $PROC/<pid>/stat.
# comm sits in parentheses and may hold spaces ("tmux: server"), so split after the
# LAST ")". There, field 2 is the ppid and field 20 is starttime (field 22 raw).
_proc_stat(){
  local s="" rest="" comm=""
  s="$(cat "$PROC/$1/stat" 2>/dev/null)" || return 1
  [ -n "$s" ] || return 1
  comm="${s#*(}"; comm="${comm%)*}"
  rest="${s##*) }"
  set -- $rest
  [ $# -ge 20 ] || return 1
  printf '%s %s %s\n' "$2" "${20}" "$comm"
}

# _alive <pid> [procStart] : is this exact process still running? On Linux the
# registry's procStart must equal the kernel start time, so a PID that an early-boot
# process reused after a reboot does not count.
_alive(){
  local st="" start=""
  case "$SESH_OS" in
    linux)
      st="$(_proc_stat "$1")" || return 1
      [ -n "${2:-}" ] || return 0
      start="${st#* }"; start="${start%% *}"
      [ "$start" = "$2" ] ;;
    *) kill -0 "$1" 2>/dev/null ;;
  esac
}

# _want_session <kind> : the registry kind filter. Linux keeps interactive sessions
# (and entries from builds that record no kind). Other OSes keep everything, as before.
_want_session(){
  case "$SESH_OS" in
    linux) [ -z "${1:-}" ] || [ "$1" = interactive ] ;;
    *) return 0 ;;
  esac
}
```

- [ ] **Step 5: Run the suite**

Run: `SESH_BIN="$WT/sesh/sesh" bash "$WT/sesh/tests/sesh.test.sh" | tail -2`
Expected: `# passed 74, failed 0`

- [ ] **Step 6: Commit**

```bash
git -C "$WT" add sesh/lib/os.sh sesh/tests/sesh.test.sh
git -C "$WT" -c core.hooksPath=/dev/null commit -m "sesh: add /proc liveness helpers for Linux" \
  -m "_alive compares the registry's procStart with the kernel start time, so a PID reused after a reboot never counts as a live session. _want_session keeps only interactive sessions on Linux; the Mac keeps every kind, as before." \
  -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Window capture

**Run from:** `$WT`

**Files:**
- Modify: `sesh/lib/os.sh` (append a section)
- Modify: `sesh/tests/sesh.test.sh` (the `mkhypr` and `mkcapture` helpers; three tests; one `RUN` line)

**Interfaces:**
- Consumes: `SESH_OS`, `HYPRCTL`, `_proc_stat` (Tasks 1 and 2).
- Produces:
  - `_capture_windows <pid>…` prints one compact JSON object keyed by each claude PID (as a string). Each value is one of:
    - `{"ws":…,"monitor":…,"at":[x,y],"address":…}` for a placed window;
    - `{}` for a window PID that several windows share (foot server mode);
    - `{"skip":"tmux"}`, `{"skip":"headless"}` or `{"skip":"scratchpad"}`.
  - On Linux it returns 1 when `hyprctl clients -j` or `hyprctl monitors -j` fails or prints a non-array. With no PIDs, or on other OSes, it prints `{}`.
  - Test helpers: `mkhypr` (the fake `hyprctl`, including the `HYPR_SIMULATE` mode Task 7 uses) and `mkcapture` (a window and process fixture).

- [ ] **Step 1: Add the fake Hyprland helpers**

In `sesh/tests/sesh.test.sh`, directly after the `clean_env(){ … }` function, add:

```bash

# mkhypr : a fake hyprctl at $TMP/fake/hyprctl. It serves $TMP/hypr/<query>.json for
# `instances|clients|monitors|workspaces -j` and logs every `eval` to $TMP/hypr/eval.log.
# It exports SESH_HYPRCTL, SESH_PROC and SESH_UNAME=Linux.
# With HYPR_SIMULATE=1, an exec_cmd eval that carries "--sid <uuid>" starts a fake
# session: a registry entry (procStart 77), a claude -> foot chain in $TMP/proc, and a
# foot window. The window lands on $HYPR_LAND_WS, or else on the rule's workspace.
# A workspace it creates sits on $HYPR_LAND_MON (default DP-2).
mkhypr(){ mkdir -p "$TMP/hypr" "$TMP/proc"
  printf '[{"instance":"SIG1","time":1,"pid":100,"wl_socket":"wayland-1"}]\n' > "$TMP/hypr/instances.json"
  printf '[{"id":0,"name":"DP-1","x":0},{"id":2,"name":"DP-2","x":3840}]\n' > "$TMP/hypr/monitors.json"
  printf '[]\n' > "$TMP/hypr/clients.json"
  printf '[]\n' > "$TMP/hypr/workspaces.json"
  cat > "$TMP/fake/hyprctl" <<'EOF'
#!/bin/bash
H="$(cd "$(dirname "$0")/.." && pwd)"
case "$1" in
  instances|clients|monitors|workspaces) cat "$H/hypr/$1.json" ;;
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

# mkcapture : mkhypr plus six windows and the processes under them.
#   300 foot  argo/DP-1     <- 301 zsh <- 302 sesh-local <- 303 claude
#   310 foot  3/DP-2        <- 311 zsh <- 312 claude
#   320 scratchpad          <- 321 zsh <- 322 claude
#   330 foot  erp/DP-1, x2  <- 331 claude              (two windows share pid 330)
#   340 foot  special:stash <- 341 claude
#   350 tmux: server        <- 351 zsh <- 352 claude   (no window)
#   360 systemd             <- 361 claude              (no window)
mkcapture(){ mkhypr
  cat > "$TMP/hypr/clients.json" <<'EOF'
[{"address":"0xa1","pid":300,"class":"foot","workspace":{"id":-5,"name":"argo"},"monitor":0,"at":[10,40]},
 {"address":"0xa2","pid":310,"class":"foot","workspace":{"id":3,"name":"3"},"monitor":2,"at":[3850,40]},
 {"address":"0xa3","pid":320,"class":"scratchpad","workspace":{"id":-98,"name":"special:scratch"},"monitor":2,"at":[0,0]},
 {"address":"0xa4","pid":330,"class":"foot","workspace":{"id":-6,"name":"erp"},"monitor":0,"at":[0,0]},
 {"address":"0xa5","pid":330,"class":"foot","workspace":{"id":-6,"name":"erp"},"monitor":0,"at":[1900,0]},
 {"address":"0xa6","pid":340,"class":"foot","workspace":{"id":-99,"name":"special:stash"},"monitor":2,"at":[0,0]}]
EOF
  mkstat 300 foot 1 1;      mkstat 301 zsh 300 2; mkstat 302 sesh-local 301 3; mkstat 303 claude 302 4
  mkstat 310 foot 1 1;      mkstat 311 zsh 310 2; mkstat 312 claude 311 5
  mkstat 320 alacritty 1 1; mkstat 321 zsh 320 2; mkstat 322 claude 321 6
  mkstat 330 foot 1 1;      mkstat 331 claude 330 7
  mkstat 340 foot 1 1;      mkstat 341 claude 340 8
  mkstat 350 "tmux: server" 1 1; mkstat 351 zsh 350 2; mkstat 352 claude 351 9
  mkstat 360 systemd 1 1;   mkstat 361 claude 360 10
}
```

- [ ] **Step 2: Write the failing tests**

Directly above the line that starts `RUN="t_aititle`, add:

```bash
echo "# window capture (fake hyprctl + fake /proc)"
t_capture_cases(){ newtmp; export HOME="$TMP"; mkcapture
  out="$(run_fn _capture_windows 303 312 322 331 341 352 361)"
  assert_has "claude under sesh-local maps to its foot window" '"303":{"ws":"argo","monitor":"DP-1","at":[10,40],"address":"0xa1"}' "$out"
  assert_has "claude under zsh maps to a numbered workspace"   '"312":{"ws":"3","monitor":"DP-2"' "$out"
  assert_has "the scratchpad window is skipped"                 '"322":{"skip":"scratchpad"}' "$out"
  assert_has "a pid shared by two windows gets no placement"    '"331":{}' "$out"
  assert_has "a stash window is kept"                           '"341":{"ws":"special:stash"' "$out"
  assert_has "claude inside tmux is skipped"                    '"352":{"skip":"tmux"}' "$out"
  assert_has "claude with no window is skipped"                 '"361":{"skip":"headless"}' "$out"
  clean_env
}
t_capture_fail_closed(){ newtmp; export HOME="$TMP"; mkcapture
  printf 'not json\n' > "$TMP/hypr/clients.json"
  if run_fn _capture_windows 303 >/dev/null; then no "bad hyprctl json must fail"; else ok "bad hyprctl json fails (non-zero)"; fi
  clean_env
}
t_capture_darwin(){ newtmp; export HOME="$TMP"
  out="$(SESH_UNAME=Darwin run_fn _capture_windows 303)"
  if [ "$out" = "{}" ]; then ok "darwin capture is empty (no placement)"; else no "darwin capture should be {} (got '$out')"; fi
}
```

Directly above the `# SESH_TEST_ONLY=` comment line, add:

```bash
RUN="$RUN t_capture_cases t_capture_fail_closed t_capture_darwin"
```

- [ ] **Step 3: Run the new tests and watch them fail**

Run: `SESH_TEST_ONLY="t_capture_cases t_capture_fail_closed t_capture_darwin" SESH_BIN="$WT/sesh/sesh" bash "$WT/sesh/tests/sesh.test.sh" 2>/dev/null | tail -2`
Expected: `# passed 1, failed 8`

- [ ] **Step 4: Append the capture section to `sesh/lib/os.sh`**

```bash

# ---- window capture ------------------------------------------------------------------
# _capture_windows <pid>... : print a JSON object keyed by each claude PID:
#   {"ws":"argo","monitor":"DP-1","at":[x,y],"address":"0x…"}  a placed window
#   {}                                       a window PID several windows share (foot server mode)
#   {"skip":"tmux"|"headless"|"scratchpad"}  not a restorable window
# Each claude PID walks up its parents to the first PID that hyprctl lists as a window.
# A tmux ancestor ends the walk (tmux-resurrect owns those panes). macOS and other OSes
# print {}. On Linux a failed Hyprland query returns non-zero, so callers fail closed.
_capture_windows(){
  local clients="" monitors="" table="" out='{}' pid="" p="" hops=0 row="" st="" val=""
  [ "$SESH_OS" = linux ] || { printf '{}'; return 0; }
  [ $# -gt 0 ] || { printf '{}'; return 0; }
  clients="$("$HYPRCTL" clients -j 2>/dev/null)" || return 1
  monitors="$("$HYPRCTL" monitors -j 2>/dev/null)" || return 1
  table="$(jq -rn --argjson c "$clients" --argjson m "$monitors" '
      if ($c | type) != "array" or ($m | type) != "array" then error("bad hyprctl json") else . end
      | ($m | map({key: (.id | tostring), value: .name}) | from_entries) as $mn
      | $c | group_by(.pid)[] | (length | tostring) as $n | .[0]
      | [(.pid | tostring), $n, .address, .workspace.name, ($mn[(.monitor | tostring)] // ""),
         (.at[0] | tostring), (.at[1] | tostring), .class] | @tsv' 2>/dev/null)" || return 1
  for pid in "$@"; do
    p="$pid"; hops=0; val='{"skip":"headless"}'
    while [ "$hops" -lt 64 ]; do
      row="$(printf '%s\n' "$table" | awk -F'\t' -v p="$p" '$1 == p {print; exit}')"
      if [ -n "$row" ]; then
        val="$(printf '%s' "$row" | jq -R -c 'split("\t")
          | if .[1] != "1" then {}
            elif .[7] == "scratchpad" then {skip: "scratchpad"}
            else {ws: .[3], monitor: .[4], at: [(.[5] | tonumber), (.[6] | tonumber)], address: .[2]} end')"
        break
      fi
      st="$(_proc_stat "$p")" || break
      case "${st#* * }" in tmux*) val='{"skip":"tmux"}'; break ;; esac
      p="${st%% *}"
      [ "$p" -gt 1 ] 2>/dev/null || break
      hops=$((hops + 1))
    done
    out="$(printf '%s' "$out" | jq -c --arg k "$pid" --argjson v "$val" '. + {($k): $v}')"
  done
  printf '%s' "$out"
}
```

- [ ] **Step 5: Run the suite**

Run: `SESH_BIN="$WT/sesh/sesh" bash "$WT/sesh/tests/sesh.test.sh" | tail -2`
Expected: `# passed 83, failed 0`

- [ ] **Step 6: Commit**

```bash
git -C "$WT" add sesh/lib/os.sh sesh/tests/sesh.test.sh
git -C "$WT" -c core.hooksPath=/dev/null commit -m "sesh: capture each claude window's Hyprland placement" \
  -m "_capture_windows walks each claude PID up to the window that hyprctl lists. It records the workspace, monitor, position and address, and skips tmux panes, headless sessions and the scratchpad. A failed query returns non-zero, so a save can fail closed." \
  -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Save on Linux

**Run from:** `$WT`

**Files:**
- Modify: `sesh/lib/os.sh` (append a section)
- Rewrite: `sesh/sesh-save`
- Modify: `sesh/tests/sesh.test.sh` (the `mkreg`, `mksave` and `snap` helpers; seven tests; one `RUN` line)

**Interfaces:**
- Consumes: `SESH_OS`, `HYPRCTL`, `_alive`, `_want_session`, `_capture_windows` (Tasks 1 to 3).
- Produces:
  - `_save_gate` returns 0 when `sesh-save` may write. It reads `SNAP` and `STATE` from the caller. On Linux it sets `SESH_INSTANCE` and exports `HYPRLAND_INSTANCE_SIGNATURE` to the live instance. `SESH_SKIP_BOOTGUARD=1` makes it pass on every OS.
  - The snapshot format: `{"saved_at", "instance" (Linux only), "local": [{"id", "cwd", "updated", "ws", "monitor", "at"}], "remote"}`. On macOS `local` entries hold only `id` and `cwd`. On Linux `local` is sorted by monitor name, workspace name, then `at`.
  - `~/.local/state/sesh/history/<UTC timestamp>.<pid>.json` (Linux), keeping the newest 20.
  - Test helpers: `mkreg <pid> <id> <cwd> <procStart> [kind] [updatedAt-ms]`, `mksave` and `snap`.

- [ ] **Step 1: Add the save helpers**

In `sesh/tests/sesh.test.sh`, directly after the `mkcapture(){ … }` function, add:

```bash

# mkreg <pid> <id> <cwd> <procStart> [kind] [updatedAt-ms] : a fake registry entry.
mkreg(){ mkdir -p "$TMP/.claude/sessions"
  printf '{"pid":%s,"sessionId":"%s","cwd":"%s","procStart":"%s","kind":"%s","updatedAt":%s}\n' \
    "$1" "$2" "$3" "$4" "${5:-interactive}" "${6:-1000000}" > "$TMP/.claude/sessions/$1.json"; }
# mksave : mkcapture plus registry entries for claude 303 (argo on DP-1) and 312 (3 on DP-2).
mksave(){ mkcapture
  mkreg 303 "aaaaaaaa-0000-0000-0000-000000000303" "/w/argo" 4 interactive 2000000
  mkreg 312 "bbbbbbbb-0000-0000-0000-000000000312" "/w/three" 5 interactive 1000000; }
snap(){ cat "$TMP/.local/state/sesh/snapshot.json" 2>/dev/null; }
```

- [ ] **Step 2: Write the failing tests**

Directly above the line that starts `RUN="t_aititle`, add:

```bash
echo "# sesh-save on Linux (gate, placement, history)"
t_save_linux_placement(){ newtmp; export HOME="$TMP"; mksave
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
  printf '[{"instance":"A"},{"instance":"B"}]\n' > "$TMP/hypr/instances.json"; bash "$SESHSAVE"
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
  bash "$SESHSAVE"
  assert_has "a failed hyprctl query leaves the snapshot intact" "intact" "$(snap)"
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
```

Directly above the `# SESH_TEST_ONLY=` comment line, add:

```bash
RUN="$RUN t_save_linux_placement t_save_skips_dead_and_kinds t_save_gate t_save_first_run t_save_fail_closed t_save_history t_save_darwin_unchanged"
```

- [ ] **Step 3: Run the new tests and watch them fail**

Run: `SESH_TEST_ONLY="t_save_linux_placement t_save_skips_dead_and_kinds t_save_gate t_save_first_run t_save_fail_closed t_save_history t_save_darwin_unchanged" SESH_BIN="$WT/sesh/sesh" bash "$WT/sesh/tests/sesh.test.sh" 2>/dev/null | grep -c 'NOT OK'`
Expected: a count of at least 5. Today's `sesh-save` writes no `instance`, `ws`, `monitor`, `updated` or history, so those assertions fail. The exact count depends on which fake PIDs happen to exist on the box, because today's script uses `kill -0`.

- [ ] **Step 4: Append the save gate to `sesh/lib/os.sh`**

```bash

# ---- save gate -----------------------------------------------------------------------
# _save_gate : may sesh-save write now? SESH_SKIP_BOOTGUARD=1 always says yes.
#   macOS : not in the first 180 s after boot (the original guard).
#   Linux : exactly one live Hyprland instance, and one of: no snapshot yet, a snapshot
#           this instance wrote, or a finished restore in this instance (the `restored`
#           file). Sets SESH_INSTANCE and exports HYPRLAND_INSTANCE_SIGNATURE.
# The caller sets SNAP and STATE.
_save_gate(){
  local inst="" boot=""
  case "$SESH_OS" in
    linux)
      inst="$("$HYPRCTL" instances -j 2>/dev/null | jq -r 'if type == "array" and length == 1 then .[0].instance else empty end' 2>/dev/null)"
      if [ -z "$inst" ]; then [ -n "${SESH_SKIP_BOOTGUARD:-}" ]; return; fi
      SESH_INSTANCE="$inst"; export HYPRLAND_INSTANCE_SIGNATURE="$inst"
      [ -n "${SESH_SKIP_BOOTGUARD:-}" ] && return 0
      [ -e "$SNAP" ] || return 0
      [ "$(jq -r '.instance // empty' "$SNAP" 2>/dev/null)" = "$inst" ] && return 0
      [ "$(cat "$STATE/restored" 2>/dev/null)" = "$inst" ] ;;
    darwin)
      [ -n "${SESH_SKIP_BOOTGUARD:-}" ] && return 0
      boot=$(sysctl -n kern.boottime 2>/dev/null | sed -n 's/^{ sec = \([0-9]*\),.*/\1/p')
      [ -z "$boot" ] || [ "$(( $(date +%s) - boot ))" -ge 180 ] ;;
    *) return 0 ;;
  esac
}
```

- [ ] **Step 5: Replace `sesh/sesh-save` with this content**

```bash
#!/bin/bash
# sesh-save — snapshot the current LIVE session set to ~/.local/state/sesh/snapshot.json.
#
# Sources (both authoritative, PID-checked — no heuristics):
#   local  = Claude Code sessions in ~/.claude/sessions/*.json with a live PID
#   remote = hexane tmux sessions with a live presence marker (written by sesh-remote)
#
# Run on an interval so the last snapshot before shutdown ~= what you had open;
# sesh-restore rebuilds it at next login. Also runnable by hand.
#   macOS : a LaunchAgent runs it every 120 s.
#   Linux : sesh-save.timer runs it every 60 s. Each local session also records its
#           window's Hyprland workspace, monitor and position, and history/ keeps the
#           last 20 distinct snapshots.
# The save gate (lib/os.sh _save_gate) keeps an early save from overwriting the
# snapshot before sesh-restore has read it. SESH_SKIP_BOOTGUARD=1 skips the gate.
set -u
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

SESH_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
STATE="$HOME/.local/state/sesh"
SNAP="$STATE/snapshot.json"
HIST="$STATE/history"
REG="$HOME/.claude/sessions"
MARKS="$STATE/remote"
mkdir -p "$STATE" "$MARKS"
command -v jq >/dev/null || exit 0
. "$SESH_DIR/lib/os.sh"

_save_gate || exit 0

# Local: live Claude sessions (the registry carries sessionId, cwd, pid and procStart).
# Fields are joined with \x1f: `read` collapses runs of tabs and would shift an empty field.
rows=""
for j in "$REG"/*.json; do
  [ -e "$j" ] || continue
  rec="$(jq -r '[(.pid // "" | tostring), (.sessionId // ""), (.cwd // ""), (.procStart // "" | tostring), (.kind // ""), ((.updatedAt // 0) / 1000 | floor | tostring)] | join("\u001f")' "$j" 2>/dev/null)" || continue
  IFS=$'\x1f' read -r pid id cwd pstart kind upd <<< "$rec"
  [ -n "$pid" ] && [ -n "$id" ] || continue
  _want_session "$kind" || continue
  _alive "$pid" "$pstart" || continue
  rows="$rows$pid"$'\x1f'"$id"$'\x1f'"$cwd"$'\x1f'"$upd"$'\n'
done

# Placement (Linux). A failed Hyprland query exits here, so no snapshot is written from it.
cap="$(_capture_windows $(printf '%s' "$rows" | cut -d $'\x1f' -f1))" || exit 0
local_json="$(printf '%s' "$rows" | jq -R -s -c --argjson cap "$cap" --arg os "$SESH_OS" '
  split("\n") | map(select(length > 0) | split("\u001f"))
  | map(. as $r | ($cap[$r[0]] // {}) as $c
        | select(($c.skip // "") == "")
        | {id: $r[1], cwd: $r[2]}
          + (if $os == "linux"
             then {updated: ($r[3] | tonumber? // 0)} + ($c | {ws, monitor, at} | with_entries(select(.value != null)))
             else {} end))
  | unique_by(.id)
  | if $os == "linux" then sort_by(.monitor // "", .ws // "", (.at // [0, 0])[0], (.at // [0, 0])[1]) else . end')" || exit 0
[ -n "$local_json" ] || local_json='[]'

# Remote: markers are host-namespaced (remote/<host>/<session>). Prune dead PIDs,
# then collect survivors. Legacy flat markers (remote/<session>, from the old
# single-host hx-connect) are migrated into the host tree under the configured legacy
# host when their PID is still live — so a session opened before an in-place upgrade
# still gets snapshotted — and dropped when dead or already claimed host-namespaced.
HOSTDEF="${SESH_HOST:-${HX_HOST:-hexane}}"
for flat in "$MARKS"/*; do
  [ -f "$flat" ] || continue
  fpid=$(cat "$flat" 2>/dev/null)
  dest="$MARKS/$HOSTDEF/$(basename "$flat")"
  if [ -n "$fpid" ] && kill -0 "$fpid" 2>/dev/null && [ ! -e "$dest" ]; then
    mkdir -p "$MARKS/$HOSTDEF"; mv "$flat" "$dest"
  else
    rm -f "$flat"
  fi
done
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

new="$(jq -n --argjson l "$local_json" --argjson r "$remote_json" --arg ts "$(date -u +%FT%TZ)" --arg inst "${SESH_INSTANCE:-}" \
  '{saved_at: $ts} + (if $inst != "" then {instance: $inst} else {} end) + {local: $l, remote: $r}')" || exit 0

# History (Linux): keep the last 20 distinct snapshots. A change in timestamps alone
# (saved_at, updated) does not count.
changed=1
if [ "$SESH_OS" = linux ] && [ -r "$SNAP" ]; then
  norm='del(.saved_at) | .local |= map(del(.updated))'
  [ "$(jq -cS "$norm" "$SNAP" 2>/dev/null)" = "$(printf '%s' "$new" | jq -cS "$norm" 2>/dev/null)" ] && changed=0
fi
printf '%s\n' "$new" > "$SNAP.tmp" && mv "$SNAP.tmp" "$SNAP"
if [ "$SESH_OS" = linux ] && [ "$changed" = 1 ]; then
  mkdir -p "$HIST"
  cp "$SNAP" "$HIST/$(date -u +%Y%m%dT%H%M%SZ).$$.json"
  ls -1t "$HIST"/*.json 2>/dev/null | tail -n +21 | while IFS= read -r old; do rm -f -- "$old"; done
fi
```

- [ ] **Step 6: Run the suite**

Run: `SESH_BIN="$WT/sesh/sesh" bash "$WT/sesh/tests/sesh.test.sh" | tail -2`
Expected: `# passed 111, failed 0`

- [ ] **Step 7: Commit**

```bash
git -C "$WT" add sesh/lib/os.sh sesh/sesh-save sesh/tests/sesh.test.sh
git -C "$WT" -c core.hooksPath=/dev/null commit -m "sesh-save: gate, placement and history on Linux" \
  -m "On Linux a save records each session's workspace, monitor and position, and history/ keeps the last 20 distinct snapshots. The gate writes only for a single live Hyprland instance that wrote the snapshot or finished its restore, and any failed query exits without writing. The macOS snapshot is unchanged." \
  -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: `sesh-local --sid`

**Run from:** `$WT`

**Files:**
- Rewrite: `sesh/sesh-local`
- Modify: `sesh/tests/sesh.test.sh` (one test; one `RUN` line)

**Interfaces:**
- Consumes: nothing from the lib.
- Produces:
  - `sesh-local --sid <uuid>` reads the cwd from the transcript `~/.claude/projects/*/<uuid>.jsonl`, falling back to `$HOME`. It titles the window `claude · <first 8 chars>`, runs `ccf --resume <uuid>` (or plain claude), then runs `exec "${SHELL:-/bin/zsh}" -i`.
  - Under `SESH_DRYRUN=1` either form prints `would run in <cwd> as "claude · <name>": ccf <args>` (with `; then exec $SHELL -i` for `--sid`) and exits 0.
  - The `<cwd> <name> <args…>` form behaves as before.

- [ ] **Step 1: Write the failing test**

Directly above the line that starts `RUN="t_aititle`, add:

```bash
echo "# sesh-local --sid"
t_local_sid(){ newtmp; export HOME="$TMP"
  mkdir -p "$TMP/work dir"
  f="$(mkproj projS 12345678-aaaa-bbbb-cccc-000000000001 yes "T" "x")"
  sed -i.bak "s#/Users/vania/Projects/projS#$TMP/work dir#" "$f"
  out="$(SESH_DRYRUN=1 bash "$_BIN/sesh-local" --sid 12345678-aaaa-bbbb-cccc-000000000001)"
  assert_has "--sid reads the cwd from the transcript"  "would run in $TMP/work dir as" "$out"
  assert_has "--sid titles the window with the id"      'claude · 12345678' "$out"
  assert_has "--sid resumes that session"               "ccf --resume 12345678-aaaa-bbbb-cccc-000000000001" "$out"
  assert_has "--sid keeps the window open with a shell" 'then exec $SHELL -i' "$out"
  out="$(SESH_DRYRUN=1 bash "$_BIN/sesh-local" --sid 99999999-aaaa-bbbb-cccc-000000000009)"
  assert_has "--sid without a transcript falls back to HOME" "would run in $TMP as" "$out"
}
```

Directly above the `# SESH_TEST_ONLY=` comment line, add:

```bash
RUN="$RUN t_local_sid"
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `SESH_TEST_ONLY="t_local_sid" SESH_BIN="$WT/sesh/sesh" bash "$WT/sesh/tests/sesh.test.sh" 2>/dev/null | tail -2`
Expected: `# passed 0, failed 5`. Today's `sesh-local` has no `--sid` form. It cannot launch claude here either, because `$HOME` points at the temp dir.

- [ ] **Step 3: Replace `sesh/sesh-local` with this content**

```bash
#!/bin/bash
# sesh-local <cwd> <name> <claude-args...> — window command for sesh / sesh-restore.
# sesh-local --sid <uuid> — the Linux restore form: read the cwd from the session's
#   transcript, resume it, then keep the window open with an interactive shell.
# cd into <cwd>, title the window "claude · <name>", then launch claude via the `ccf`
# ccflare launcher with the given args (e.g. --resume <id>). A separate launcher so the
# caller hands it clean argv through `open -e` (Ghostty's -e preserves spaced args).
# SESH_DRYRUN=1 prints what it would run.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
keep_shell=""
if [ "${1:-}" = "--sid" ]; then
  sid="${2:?usage: sesh-local --sid <uuid>}"
  f="$(ls "$HOME"/.claude/projects/*/"$sid".jsonl 2>/dev/null | head -1)"
  sid_cwd="$(grep -a -m1 '"cwd"' "$f" 2>/dev/null | jq -rc 'select(.cwd!=null)|.cwd' 2>/dev/null | head -1)"
  set -- "${sid_cwd:-$HOME}" "${sid:0:8}" --resume "$sid"
  keep_shell=1
fi
cwd="${1:?usage: sesh-local <cwd> <name> <claude-args...>}"; shift
name="${1:-claude}"; shift
if [ -n "${SESH_DRYRUN:-}" ]; then
  printf 'would run in %s as "claude · %s": ccf %s%s\n' "$cwd" "$name" "$*" "${keep_shell:+; then exec \$SHELL -i}"
  exit 0
fi
printf '\033]0;claude · %s\007' "$name"   # initial title; claude's TUI may update it
cd "$cwd" 2>/dev/null || cd "$HOME"
unset CLAUDE_CODE_CHILD_SESSION   # a window spawned from within Claude still saves its transcript

# Launch via `ccf` (ccflare API-key routing + --dangerously-skip-permissions). ccf is a
# function in ~/.zshrc.local (machine-local; holds the ccflare key), so source that
# rather than hardcode the key into dotfiles. Fall back to plain claude if it's absent.
[ -r "$HOME/.zshrc.local" ] && . "$HOME/.zshrc.local" >/dev/null 2>&1
if type ccf >/dev/null 2>&1; then
  ccf "$@"
else
  "$HOME/.local/bin/claude" --dangerously-skip-permissions "$@"
fi
# A restored window outlives its session, like any foot window: drop to a shell.
if [ -n "$keep_shell" ]; then exec "${SHELL:-/bin/zsh}" -i; fi
```

- [ ] **Step 4: Run the suite**

Run: `SESH_BIN="$WT/sesh/sesh" bash "$WT/sesh/tests/sesh.test.sh" | tail -2`
Expected: `# passed 119, failed 0`

- [ ] **Step 5: Commit**

```bash
git -C "$WT" add sesh/sesh-local sesh/tests/sesh.test.sh
git -C "$WT" -c core.hooksPath=/dev/null commit -m "sesh-local: add the --sid restore form" \
  -m "sesh-local --sid <uuid> reads the cwd from the transcript, resumes the session, and keeps the window open with a shell. Only a UUID crosses Lua and the shell, so AI-written titles never need quoting. The existing form is unchanged." \
  -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Hyprland placement primitives

**Run from:** `$WT`

**Files:**
- Modify: `sesh/lib/os.sh` (append a section)
- Modify: `sesh/tests/sesh.test.sh` (two tests; one `RUN` line)

**Interfaces:**
- Consumes: `HYPRCTL`, `SESH_DIR` (Task 1).
- Produces:
  - `_ws_lua <ws>` prints a Lua literal: `3`, `"special:stash"` or `"name:argo"`, escaped.
  - `_hypr_eval <lua>` runs `"$HYPRCTL" eval <lua>`. Under `SESH_DRYRUN` it prints `hyprctl eval: <lua>` instead.
  - `_spawn_placed <id> [ws]` evals `hl.dispatch(hl.dsp.exec_cmd("[workspace <target> silent] ${SESH_TERMINAL:-foot} $SESH_DIR/sesh-local --sid <id>"))`. With no workspace, or a name that holds `[`, `]` or `;`, it drops the rule.
  - `_move_window <address> <ws>` and `_move_workspace <ws> <monitor>`.

- [ ] **Step 1: Write the failing tests**

Directly above the line that starts `RUN="t_aititle`, add:

```bash
echo "# Hyprland placement (dry-run Lua)"
t_spawn_placed_rules(){ newtmp; export HOME="$TMP"
  export SESH_UNAME=Linux SESH_DRYRUN=1
  id=aaaaaaaa-0000-0000-0000-000000000001
  out="$(run_fn _spawn_placed "$id" argo)"
  assert_has "a named workspace gets a silent rule"      '[workspace name:argo silent] foot ' "$out"
  assert_has "only the uuid follows sesh-local --sid"     "/sesh-local --sid $id\"))" "$out"
  out="$(run_fn _spawn_placed "$id" 3)"
  assert_has "a numbered workspace rule"                  '[workspace 3 silent] foot ' "$out"
  out="$(run_fn _spawn_placed "$id" special:stash)"
  assert_has "the stash rule"                             '[workspace special:stash silent] foot ' "$out"
  out="$(run_fn _spawn_placed "$id" 'my "q" \ws')"
  assert_has "quotes and backslashes are escaped for Lua" '[workspace name:my \"q\" \\ws silent]' "$out"
  out="$(run_fn _spawn_placed "$id" 'a]b')"
  assert_hasnt "a name holding ] opens unplaced"          '[workspace' "$out"
  out="$(run_fn _spawn_placed "$id" '')"
  assert_has "no workspace opens unplaced"                'exec_cmd("foot ' "$out"
  clean_env
}
t_move_lua(){ newtmp; export HOME="$TMP"
  export SESH_UNAME=Linux SESH_DRYRUN=1
  out="$(run_fn _move_window 0xa1 argo)"
  assert_has "window move by address, no follow" 'hl.dsp.window.move({ workspace = "name:argo", follow = false, window = "address:0xa1" })' "$out"
  out="$(run_fn _move_window 0xa1 3)"
  assert_has "a numbered target is a bare number" 'workspace = 3,' "$out"
  out="$(run_fn _move_workspace argo DP-1)"
  assert_has "workspace move to a monitor" 'hl.dsp.workspace.move({ workspace = "name:argo", monitor = "DP-1" })' "$out"
  clean_env
}
```

Directly above the `# SESH_TEST_ONLY=` comment line, add:

```bash
RUN="$RUN t_spawn_placed_rules t_move_lua"
```

- [ ] **Step 2: Run the new tests and watch them fail**

Run: `SESH_TEST_ONLY="t_spawn_placed_rules t_move_lua" SESH_BIN="$WT/sesh/sesh" bash "$WT/sesh/tests/sesh.test.sh" 2>/dev/null | tail -2`
Expected: `# passed 1, failed 9`

- [ ] **Step 3: Append the placement section to `sesh/lib/os.sh`**

```bash

# ---- placement (Linux / Hyprland) ----------------------------------------------------
# Probed on Hyprland 0.56.2: an exec with "[workspace <ws> silent]" places the window
# without moving focus. Adding a `monitor` rule moves focus and warps the cursor, so we
# never use one. workspace.move shifts an inactive workspace with no focus change.
# Hyprland ignores unknown keys in these tables, so a typo fails silently.

# _lua_esc : escape stdin for a Lua double-quoted string (\ and ").
_lua_esc(){ sed 's/\\/\\\\/g; s/"/\\"/g'; }

# _ws_lua <ws> : the workspace as a Lua literal: 3, "special:stash" or "name:argo".
_ws_lua(){
  local esc=""
  case "$1" in
    ''|*[!0-9]*) ;;
    *) printf '%s' "$1"; return 0 ;;
  esac
  esc="$(printf '%s' "$1" | _lua_esc)"
  case "$1" in
    special:*) printf '"%s"' "$esc" ;;
    *) printf '"name:%s"' "$esc" ;;
  esac
}

# _hypr_eval <lua> : run one Lua chunk in Hyprland, or print it under SESH_DRYRUN.
_hypr_eval(){
  if [ -n "${SESH_DRYRUN:-}" ]; then printf 'hyprctl eval: %s\n' "$1"; return 0; fi
  "$HYPRCTL" eval "$1" </dev/null >/dev/null 2>&1
}

# _spawn_placed <id> [ws] : open a foot window that resumes session <id>, silently on
# workspace <ws>. Hyprland runs the command, so the rule applies from the first frame.
# Only <id> (a UUID) and fixed paths enter the command. A name holding [ ] or ;
# cannot sit inside a rule, so that window opens unplaced.
_spawn_placed(){
  local id="$1" ws="${2:-}" rule="" cmd="" esc=""
  case "$ws" in
    ''|*'['*|*']'*|*';'*) ;;
    special:*) rule="[workspace $ws silent] " ;;
    *[!0-9]*)  rule="[workspace name:$ws silent] " ;;
    *)         rule="[workspace $ws silent] " ;;
  esac
  cmd="${rule}${SESH_TERMINAL:-foot} $SESH_DIR/sesh-local --sid $id"
  esc="$(printf '%s' "$cmd" | _lua_esc)"
  _hypr_eval "hl.dispatch(hl.dsp.exec_cmd(\"$esc\"))"
}

# _move_window <address> <ws> : move one window to <ws> without following it.
_move_window(){ _hypr_eval "hl.dispatch(hl.dsp.window.move({ workspace = $(_ws_lua "$2"), follow = false, window = \"address:$1\" }))"; }

# _move_workspace <ws> <monitor> : move a workspace to a monitor.
_move_workspace(){ _hypr_eval "hl.dispatch(hl.dsp.workspace.move({ workspace = $(_ws_lua "$1"), monitor = \"$2\" }))"; }
```

- [ ] **Step 4: Run the suite**

Run: `SESH_BIN="$WT/sesh/sesh" bash "$WT/sesh/tests/sesh.test.sh" | tail -2`
Expected: `# passed 129, failed 0`

- [ ] **Step 5: Commit**

```bash
git -C "$WT" add sesh/lib/os.sh sesh/tests/sesh.test.sh
git -C "$WT" -c core.hooksPath=/dev/null commit -m "sesh: Hyprland placement primitives" \
  -m "_spawn_placed opens foot through a silent [workspace] exec rule, the form probed on Hyprland 0.56.2 to leave focus and the cursor alone. _move_window and _move_workspace fix placement afterwards. Workspace names are escaped for Lua with sed, which behaves the same under bash 3.2." \
  -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Restore on Linux

**Run from:** `$WT`

**Files:**
- Rewrite: `sesh/sesh-restore`
- Modify: `sesh/tests/sesh.test.sh` (pin two existing tests to Darwin; the `mkrestore` and `evals` helpers; eight tests; one `RUN` line)

**Interfaces:**
- Consumes: `SESH_OS`, `HYPRCTL`, `_proc_stat`, `_alive`, `_capture_windows`, `_spawn_placed`, `_move_window`, `_move_workspace` (Tasks 1 to 6). It also uses `sesh-local --sid` (Task 5) and the snapshot format (Task 4).
- Produces:
  - In `sesh-restore`: `_linux_running <id>` (prints the PID), `_take_lock`, `_restore_done` (the EXIT trap) and `restore_linux`.
  - State: `restored` (the instance signature, not written in a dry run) and `restore.lock/` (it holds `pid` = `"<pid> <starttime>"`).
  - Tunables: `SESH_CAP` (default 20 on Linux), `SESH_STAGGER`, `SESH_VERIFY_WAIT`, `SESH_MON_WAIT` (iterations of 0.2 s, default 50) and `SESH_NOTIFY`.

- [ ] **Step 1: Pin the two remote-restore tests to macOS**

Linux restore skips remote entries, so these two tests describe macOS behavior. In `t_restore_opens_per_host`, the `out=` line becomes:

```bash
  out="$(SESH_UNAME=Darwin SESH_DRYRUN=1 bash "$SESHRESTORE" 2>&1)"   # remote restore is macOS-only
```

In `t_restore_legacy_uses_sesh_host`, the `out=` line becomes:

```bash
  out="$(SESH_UNAME=Darwin SESH_HOST=mybox SESH_DRYRUN=1 bash "$SESHRESTORE" 2>&1)"   # remote restore is macOS-only
```

- [ ] **Step 2: Add the restore helpers**

In `sesh/tests/sesh.test.sh`, directly after the `snap(){ … }` line, add:

```bash

# mkrestore : mkhypr, a fake notify-send, transcripts and cwds for three sessions, and a
# snapshot that an OLD Hyprland instance wrote (ids 1 and 3 on argo/DP-1, id 2 on 3/DP-2).
mkrestore(){ mkhypr
  export HYPRLAND_INSTANCE_SIGNATURE=SIG1 SESH_STAGGER=0 SESH_VERIFY_WAIT=0 SESH_NOTIFY="$TMP/fake/notify"
  printf '#!/bin/bash\necho "$@" >> "%s/fake/notify.log"\n' "$TMP" > "$TMP/fake/notify"; chmod +x "$TMP/fake/notify"
  mkdir -p "$TMP/w/argo" "$TMP/w/three" "$TMP/w/argo3"
  for i in 1 2 3; do mkproj "p$i" "aaaaaaaa-0000-0000-0000-00000000000$i" no "" "hi" >/dev/null; done
  cat > "$TMP/.local/state/sesh/snapshot.json" <<EOF
{"saved_at":"t","instance":"OLD","local":[
 {"id":"aaaaaaaa-0000-0000-0000-000000000001","cwd":"$TMP/w/argo","ws":"argo","monitor":"DP-1","at":[0,0],"updated":300},
 {"id":"aaaaaaaa-0000-0000-0000-000000000002","cwd":"$TMP/w/three","ws":"3","monitor":"DP-2","at":[0,0],"updated":200},
 {"id":"aaaaaaaa-0000-0000-0000-000000000003","cwd":"$TMP/w/argo3","ws":"argo","monitor":"DP-1","at":[1900,0],"updated":100}],
 "remote":[{"host":"dev-1","session":"api"}]}
EOF
}
evals(){ cat "$TMP/hypr/eval.log" 2>/dev/null; }
```

- [ ] **Step 3: Write the failing tests**

Directly above the line that starts `RUN="t_aititle`, add:

```bash
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
  assert_has   "the cap keeps the newest (id 1)" "--sid aaaaaaaa-0000-0000-0000-000000000001" "$out"
  assert_has   "the cap keeps the newest (id 2)" "--sid aaaaaaaa-0000-0000-0000-000000000002" "$out"
  assert_hasnt "the cap drops the oldest (id 3)" "--sid aaaaaaaa-0000-0000-0000-000000000003" "$out"
  first="$(printf '%s\n' "$out" | grep -o -- '--sid [0-9a-f-]*' | head -1)"
  if [ "$first" = "--sid aaaaaaaa-0000-0000-0000-000000000001" ]; then ok "spawns follow snapshot order"; else no "the first spawn should be id 1 (got '$first')"; fi
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
```

Directly above the `# SESH_TEST_ONLY=` comment line, add:

```bash
RUN="$RUN t_restore_linux_dry t_restore_linux_cap_order t_restore_linux_skips t_restore_linux_full t_restore_linux_monitor_fix t_restore_linux_marker_paths t_restore_linux_lock t_restore_linux_not_started"
```

- [ ] **Step 4: Run the dry-run tests and watch them fail**

Run only the two dry-run tests. Today's `sesh-restore` would try `open -na` on a non-dry run.
Run: `SESH_TEST_ONLY="t_restore_linux_dry t_restore_linux_cap_order" SESH_BIN="$WT/sesh/sesh" bash "$WT/sesh/tests/sesh.test.sh" 2>/dev/null | tail -2`
Expected: `# passed 3, failed 6`

- [ ] **Step 5: Replace `sesh/sesh-restore` with this content**

The macOS part (from `n=0` to the end) and the helper functions above it are today's code, unchanged.

```bash
#!/bin/bash
# sesh-restore — rebuild the last snapshot (~/.local/state/sesh/snapshot.json) as
# terminal windows: local Claude sessions resumed in their dirs (`claude --resume`),
# open remote sessions reattached over mosh on the host each one belongs to (host-less
# legacy entries use the configured SESH_HOST, default hexane). Skips anything already
# live, caps the count,
# and (for remote) skips hosts that are unreachable.
#
#   macOS: runs at login via a LaunchAgent and opens Ghostty windows.
#   Linux: Hyprland runs it at start (hyprland.lua). Each session reopens in foot,
#          silently, on its saved workspace and monitor; remote entries are skipped.
#          When it finishes it marks this Hyprland instance as restored, which lets
#          sesh-save write again.
#   By hand via `revive`. Preview: SESH_DRYRUN=1 revive
#   Tunables: SESH_CAP (default 12 on macOS, 20 on Linux). Linux only: SESH_STAGGER
#   (seconds between windows, default 1.5) and SESH_VERIFY_WAIT (whole seconds to wait
#   for the windows to start, default 15). Log: ~/.local/state/sesh/restore.log
set -u
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

SESH_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
STATE="$HOME/.local/state/sesh"
SNAP="${SESH_SNAPSHOT:-$STATE/snapshot.json}"
LOG="$STATE/restore.log"
REG="$HOME/.claude/sessions"
MARKS="$STATE/remote"
GHOSTTY="/Applications/Ghostty.app"
SESH_LOCAL="$HOME/.dotfiles/sesh/sesh-local"
SESH_REMOTE="$HOME/.dotfiles/sesh/sesh-remote"
PROJECTS="$HOME/.claude/projects"
CAP="${SESH_CAP:-12}"
DRY="${SESH_DRYRUN:-}"
mkdir -p "$STATE"
log(){ printf '%s  %s\n' "$(date '+%F %T')" "$*" >>"$LOG"; }
. "$SESH_DIR/lib/os.sh"
[ "$SESH_OS" = linux ] && CAP="${SESH_CAP:-20}"

command -v jq >/dev/null || { log "FATAL: jq not found"; exit 1; }
[ -r "$SNAP" ]  || { log "no snapshot at $SNAP; nothing to restore"; exit 0; }

name_of(){ # <jsonl> <id> : latest ai-title -> first user msg -> short id
  local t id="${2:-}"
  t="$(jq -rc 'select(.type=="ai-title")|.aiTitle' "$1" 2>/dev/null | tail -1)"
  [ -n "$t" ] || t="$(jq -rc 'select(.type=="user")|.message.content|if type=="array" then (map(select(.type=="text").text)|join(" ")) else tostring end' "$1" 2>/dev/null | head -1 | tr '\n\t' '  ' | sed 's/^ *//;s/ *$//' | cut -c1-48)"
  printf '%s' "${t:-${id:0:8}}"
}
jsonl_for(){ ls "$PROJECTS"/*/"$1".jsonl 2>/dev/null | head -1; }
local_running(){ local j; for j in "$REG"/*.json; do [ -e "$j" ] || continue
  [ "$(jq -rc '.sessionId' "$j" 2>/dev/null)" = "$1" ] || continue
  kill -0 "$(jq -rc '.pid' "$j" 2>/dev/null)" 2>/dev/null && return 0; done; return 1; }
remote_open(){ [ -e "$MARKS/$1/$2" ] && kill -0 "$(cat "$MARKS/$1/$2" 2>/dev/null)" 2>/dev/null; }
reachable(){ local host="$1" ip port
  ip=$(ssh -G "$host" 2>/dev/null | awk '$1=="hostname"{print $2}')
  port=$(ssh -G "$host" 2>/dev/null | awk '$1=="port"{print $2}')
  nc -z -G 3 "${ip:-$host}" "${port:-22}" >/dev/null 2>&1; }
openwin(){ # <connect-script> <args...>
  if [ -n "$DRY" ]; then printf 'DRYRUN would open: %s\n' "$*"; return; fi
  open -na "$GHOSTTY" --args -e "$@"; sleep 1; }

# ---- Linux (Hyprland) ---------------------------------------------------------------
LOCK="$STATE/restore.lock"

# _linux_running <id> : print the registry PID of running session <id>; non-zero if none.
_linux_running(){
  local j="" rec="" pid="" sid="" pstart=""
  for j in "$REG"/*.json; do
    [ -e "$j" ] || continue
    rec="$(jq -r '[(.pid // "" | tostring), (.sessionId // ""), (.procStart // "" | tostring)] | join("\u001f")' "$j" 2>/dev/null)" || continue
    IFS=$'\x1f' read -r pid sid pstart <<< "$rec"
    if [ "$sid" = "$1" ] && [ -n "$pid" ] && _alive "$pid" "$pstart"; then printf '%s' "$pid"; return 0; fi
  done
  return 1
}

# _take_lock : one restore at a time. The lock records its owner's PID and start time,
# so a lock left by a killed restore is taken over.
_take_lock(){
  local lp="" lstart="" me=""
  if ! mkdir "$LOCK" 2>/dev/null; then
    read -r lp lstart 2>/dev/null < "$LOCK/pid"
    if [ -n "$lp" ] && _alive "$lp" "$lstart"; then return 1; fi
    rm -rf -- "${LOCK:?}"
    mkdir "$LOCK" 2>/dev/null || return 1
  fi
  me="$(_proc_stat $$)"; me="${me#* }"; me="${me%% *}"
  printf '%s %s\n' "$$" "$me" > "$LOCK/pid"
}

# _restore_done (EXIT trap) : mark this Hyprland instance as restored (not in a dry run),
# so sesh-save may write again, and release the lock.
_restore_done(){
  [ -n "$DRY" ] || printf '%s\n' "$HYPRLAND_INSTANCE_SIGNATURE" > "$STATE/restored"
  rm -rf -- "${LOCK:?}"
}

# restore_linux : reopen the snapshot's local sessions as foot windows, each placed
# silently on its saved workspace, then fix placement and notify once.
restore_linux(){
  local id="" cwd="" ws="" mon="" f="" pid="" sel="" want="" have="" existing="" spawned="" fixed=""
  local cap_json="" actual="" addr="" wsmon="" msg="" extra="" all=0 waited=0 i=0
  local n=0 total=0 started=0 s_running=0 s_transcript=0 s_cwd=0 s_bad=0 s_remote=0
  if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    log "linux: HYPRLAND_INSTANCE_SIGNATURE is unset; run this inside a Hyprland session"; return 0
  fi
  _take_lock || { log "another restore holds $LOCK; exiting"; return 0; }
  trap _restore_done EXIT

  # Wait up to 10 s for the monitors the snapshot names, then use what is there.
  want="$(jq -r '[.local[]?.monitor // empty] | unique | .[]' "$SNAP" 2>/dev/null)"
  for i in $(seq 1 "${SESH_MON_WAIT:-50}"); do
    have="$("$HYPRCTL" monitors -j 2>/dev/null | jq -r '.[].name' 2>/dev/null)"
    printf '%s\n' "$want" | grep -v '^$' | grep -Fxvq -f <(printf '%s\n' "$have") || break
    sleep 0.2
  done
  existing="$("$HYPRCTL" workspaces -j 2>/dev/null | jq -r '.[].name' 2>/dev/null)"

  # The newest SESH_CAP entries by `updated`, spawned in snapshot order.
  sel="$(jq -r --argjson cap "$CAP" '
      [.local // [] | to_entries[] | .value + {ord: .key}]
      | sort_by(-(.updated // 0)) | .[:$cap] | sort_by(.ord)[]
      | [.id, (.cwd // ""), (.ws // ""), (.monitor // "")] | map(tostring) | join("\u001f")' "$SNAP" 2>/dev/null)"
  while IFS=$'\x1f' read -r id cwd ws mon; do
    [ -n "$id" ] || continue
    total=$((total + 1))
    case "$id" in *[!0-9a-f-]*) log "skip local '$id' (not a session id)"; s_bad=$((s_bad + 1)); continue ;; esac
    if _linux_running "$id" >/dev/null; then log "skip local $id (already running)"; s_running=$((s_running + 1)); continue; fi
    f="$(jsonl_for "$id")"
    if [ -z "$f" ]; then log "skip local $id (no transcript)"; s_transcript=$((s_transcript + 1)); continue; fi
    if [ -z "$cwd" ] || [ ! -d "$cwd" ]; then log "skip local $id (cwd gone: ${cwd:-none})"; s_cwd=$((s_cwd + 1)); continue; fi
    log "open local $id on ${ws:-the current workspace}${mon:+ ($mon)}"
    _spawn_placed "$id" "$ws"
    spawned="$spawned$id"$'\x1f'"$ws"$'\x1f'"$mon"$'\n'
    n=$((n + 1))
    [ -n "$DRY" ] || sleep "${SESH_STAGGER:-1.5}"
  done <<< "$sel"
  s_remote="$(jq -r '.remote // [] | length' "$SNAP" 2>/dev/null)"
  [ "${s_remote:-0}" -gt 0 ] && log "skip $s_remote remote session(s) (not restored on linux)"
  if [ -n "$DRY" ]; then log "dry run: would open $n window(s)"; return 0; fi

  # Verify: give the new windows up to SESH_VERIFY_WAIT seconds to start.
  while :; do
    all=1
    while IFS=$'\x1f' read -r id ws mon; do
      [ -n "$id" ] || continue
      _linux_running "$id" >/dev/null || { all=0; break; }
    done <<< "$spawned"
    [ "$all" = 1 ] && break
    [ "$waited" -ge $(( ${SESH_VERIFY_WAIT:-15} * 5 )) ] && break
    sleep 0.2; waited=$((waited + 1))
  done

  # Fix placement: a window off its workspace moves there, and a workspace this restore
  # created moves to its saved monitor when that monitor is present.
  while IFS=$'\x1f' read -r id ws mon; do
    [ -n "$id" ] || continue
    pid="$(_linux_running "$id")" || { log "did not start: $id"; continue; }
    started=$((started + 1))
    [ -n "$ws" ] || continue
    cap_json="$(_capture_windows "$pid")" || continue
    actual="$(printf '%s' "$cap_json" | jq -r --arg p "$pid" '.[$p].ws // empty')"
    addr="$(printf '%s' "$cap_json" | jq -r --arg p "$pid" '.[$p].address // empty')"
    if [ -n "$addr" ] && [ "$actual" != "$ws" ]; then
      log "fix: move $id from ${actual:-?} to $ws"; _move_window "$addr" "$ws"
    fi
    case "$ws" in special:*) continue ;; esac
    [ -n "$mon" ] || continue
    printf '%s\n' "$existing" | grep -Fxq -- "$ws" && continue
    printf '%s\n' "$fixed" | grep -Fxq -- "$ws" && continue
    fixed="$fixed$ws"$'\n'
    wsmon="$("$HYPRCTL" workspaces -j 2>/dev/null | jq -r --arg w "$ws" '.[] | select(.name == $w) | .monitor' 2>/dev/null)"
    if [ -n "$wsmon" ] && [ "$wsmon" != "$mon" ] && printf '%s\n' "$have" | grep -Fxq -- "$mon"; then
      log "fix: move workspace $ws from $wsmon to $mon"; _move_workspace "$ws" "$mon"
    fi
  done <<< "$spawned"

  msg="restored $started of $total"
  [ "$s_running" -gt 0 ]     && extra="$extra, running $s_running"
  [ "$s_cwd" -gt 0 ]         && extra="$extra, cwd gone $s_cwd"
  [ "$s_transcript" -gt 0 ]  && extra="$extra, no transcript $s_transcript"
  [ $((n - started)) -gt 0 ] && extra="$extra, didn't start $((n - started))"
  [ "$s_bad" -gt 0 ]         && extra="$extra, bad id $s_bad"
  [ -n "$extra" ] && msg="$msg (${extra#, })"
  log "done: $msg"
  if [ "$total" -gt 0 ]; then "${SESH_NOTIFY:-notify-send}" "sesh" "$msg" >/dev/null 2>&1 || true; fi
  return 0
}

if [ "$SESH_OS" = linux ]; then restore_linux; exit 0; fi

n=0
# ---- local ----
while IFS=$'\t' read -r id cwd; do
  [ -n "$id" ] || continue
  [ "$n" -ge "$CAP" ] && { log "cap $CAP reached; stopping"; break; }
  if local_running "$id"; then log "skip local $id (already running)"; continue; fi
  f="$(jsonl_for "$id")"; [ -n "$f" ] || { log "skip local $id (no transcript)"; continue; }
  [ -n "$cwd" ] && [ "$cwd" != "null" ] || cwd="$HOME"
  name="$(name_of "$f" "$id")"
  log "open local '$name' ($id in $cwd)"
  openwin "$SESH_LOCAL" "$cwd" "$name" --resume "$id"
  n=$((n + 1))
done < <(jq -rc '.local[]? | [.id, (.cwd // "")] | @tsv' "$SNAP" 2>/dev/null)

# ---- remote (host-aware; host-less legacy entries default to the configured
# single host SESH_HOST/HX_HOST, else hexane) ----
HOSTDEF="${SESH_HOST:-${HX_HOST:-hexane}}"
while IFS=$'\t' read -r host sess; do
  [ -n "$sess" ] || continue
  [ "$n" -ge "$CAP" ] && { log "cap $CAP reached; stopping"; break; }
  if remote_open "$host" "$sess"; then log "skip remote $host:$sess (already open)"; continue; fi
  if [ -z "$DRY" ] && ! reachable "$host"; then log "skip remote $host:$sess ($host unreachable)"; continue; fi
  log "open remote $host:$sess"
  openwin "$SESH_REMOTE" "$host" "$sess"
  n=$((n + 1))
done < <(jq -rc --arg hd "$HOSTDEF" '.remote[]? | [(.host // $hd), .session] | @tsv' "$SNAP" 2>/dev/null)
log "done: opened $n window(s)"
```

Before you save, check the macOS section against the original. `git -C "$WT" diff sesh/sesh-restore` must show no changed lines from `n=0` to the end, and no changes inside `name_of`, `jsonl_for`, `local_running`, `remote_open`, `reachable` or `openwin`.

- [ ] **Step 6: Run the suite**

Run: `SESH_BIN="$WT/sesh/sesh" bash "$WT/sesh/tests/sesh.test.sh" | tail -2`
Expected: `# passed 156, failed 0`

- [ ] **Step 7: Commit**

```bash
git -C "$WT" add sesh/sesh-restore sesh/tests/sesh.test.sh
git -C "$WT" -c core.hooksPath=/dev/null commit -m "sesh-restore: Linux path with placed foot windows" \
  -m "On Linux, restore takes a lock and opens the newest SESH_CAP sessions through silent [workspace] exec rules. It then checks that each one started, moves misplaced windows and new workspaces back, marks the Hyprland instance as restored and sends one notification. The macOS loop is unchanged, and two remote-restore tests now pin SESH_UNAME=Darwin." \
  -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Units and wiring

**Run from:** `$WT`

**Files:**
- Create: `sesh/systemd/sesh-save.service`, `sesh/systemd/sesh-save.timer`
- Modify: `ubuntu.conf.yaml` (two link lines; one shell step)
- Modify: `hypr/hyprland.lua` (one exec in `hyprland.start`)

**Interfaces:**
- Consumes: `sesh-save` (Task 4) and `sesh-restore` (Task 7) at their installed path `~/.dotfiles/sesh/`.
- Produces: the units `sesh-save.service` and `sesh-save.timer`, and the restore hook at Hyprland start.

- [ ] **Step 1: Run the checks and watch them fail**

Run:
```bash
systemd-analyze --user verify "$WT/sesh/systemd/sesh-save.service" "$WT/sesh/systemd/sesh-save.timer"; echo "verify rc=$?"
grep -c 'sesh-restore' "$WT/hypr/hyprland.lua"; grep -c 'sesh-save' "$WT/ubuntu.conf.yaml"
```
Expected: `verify` fails because the files do not exist, and both counts are `0`.

- [ ] **Step 2: Create `sesh/systemd/sesh-save.service`**

```ini
[Unit]
Description=sesh: snapshot open Claude sessions and their Hyprland placement

[Service]
Type=oneshot
ExecStart=%h/.dotfiles/sesh/sesh-save
```

- [ ] **Step 3: Create `sesh/systemd/sesh-save.timer`**

```ini
[Unit]
Description=sesh: snapshot open Claude sessions every 60s

[Timer]
# The pattern chrome-ws-snapshot.timer already uses on hexane. No Condition= on the
# service: a skipped start leaves OnUnitActiveSec nothing to count from. sesh-save's
# own gate handles a box with no Hyprland.
OnBootSec=1min
OnUnitActiveSec=60s
AccuracySec=15s

[Install]
WantedBy=timers.target
```

- [ ] **Step 4: Wire `ubuntu.conf.yaml`**

Directly after the line `    ~/.config/systemd/user/tmux.service: systemd/tmux.service`, add:

```yaml
    ~/.config/systemd/user/sesh-save.service: sesh/systemd/sesh-save.service
    ~/.config/systemd/user/sesh-save.timer: sesh/systemd/sesh-save.timer
```

At the end of the file, after the `Linger so the tmux service starts at boot pre-login` step, add:

```yaml
    # sesh auto-save (Hyprland desktops only): sesh-save.timer snapshots the open Claude
    # sessions and their workspaces every 60 s; hyprland.lua runs sesh-restore at start.
    - ['if command -v Hyprland >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then systemctl --user daemon-reload && systemctl --user enable --now sesh-save.timer; else echo "no Hyprland or no systemd --user; skipping sesh-save.timer"; fi', "Enable sesh-save.timer (Hyprland desktops)"]
```

- [ ] **Step 5: Hook `hypr/hyprland.lua`**

Inside `hl.on("hyprland.start", …)`, directly after the line `    hl.exec_cmd(terminal)`, add:

```lua
    -- sesh: reopen the Claude sessions that were open when this desktop last went away
    -- (reboot, logout or crash), each in foot on its saved workspace, silently.
    -- sesh-save.timer starts saving again once this restore finishes.
    -- Log: ~/.local/state/sesh/restore.log. Preview: SESH_DRYRUN=1 revive
    hl.exec_cmd("~/.dotfiles/sesh/sesh-restore")
```

- [ ] **Step 6: Run the checks**

Run:
```bash
systemd-analyze --user verify "$WT/sesh/systemd/sesh-save.service" "$WT/sesh/systemd/sesh-save.timer"; echo "verify rc=$?"
luac -p "$WT/hypr/hyprland.lua" && echo "lua ok"
python3 -c 'import sys, yaml; yaml.safe_load(open(sys.argv[1])); print("yaml ok")' "$WT/ubuntu.conf.yaml"
grep -c 'sesh-restore' "$WT/hypr/hyprland.lua"; grep -c 'sesh-save' "$WT/ubuntu.conf.yaml"
```
Expected: `verify rc=0` with no other output, `lua ok`, `yaml ok`, then `1` and `4` (the two link lines, the comment and the shell step).

- [ ] **Step 7: Commit**

```bash
git -C "$WT" add sesh/systemd ubuntu.conf.yaml hypr/hyprland.lua
git -C "$WT" -c core.hooksPath=/dev/null commit -m "sesh: systemd timer and Hyprland start hook" \
  -m "sesh-save.timer runs sesh-save every 60 s, and ./install enables it only where Hyprland is installed. hyprland.lua runs sesh-restore inside hyprland.start, so a reboot, a logout and a compositor crash all trigger a restore." \
  -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Documentation and the bash 3.2 run

**Run from:** `$WT`

**Files:**
- Modify: `sesh/README.md`

**Interfaces:**
- Consumes: every earlier task.
- Produces: user documentation, and proof that the suite passes under the Mac's bash 3.2.

- [ ] **Step 1: Add the Linux intro bullet**

In `sesh/README.md`, directly after the bullet `- **Remote** \`tmux\` sessions on a box you reach over \`mosh\`, reattached in place.`, add:

```markdown
- **Linux desktop** Claude sessions in foot windows on Hyprland, reopened on their own workspaces. See [Linux (Hyprland)](#linux-hyprland-auto-save-and-restore).
```

- [ ] **Step 2: Add the Linux section**

Directly above the line `## Gotchas that cost us hours`, add:

```markdown
## Linux (Hyprland): auto-save and restore

On a Hyprland desktop, `sesh` saves the Claude sessions open in terminal windows and reopens them when Hyprland starts. That covers a reboot, a logout and a compositor crash. Each session comes back in a foot window, resumed by ID, on the workspace and monitor it had. Focus does not move.

How it works:

1. `sesh-save.timer` runs `sesh-save` every 60 s. For each live interactive Claude session, `sesh-save` walks parent PIDs up to a PID that `hyprctl clients` lists. That window gives the workspace, monitor and position.
2. At Hyprland start, `hyprland.lua` runs `sesh-restore`. It opens the newest `SESH_CAP` sessions (default 20), 1.5 s apart, through `[workspace <ws> silent]` exec rules. Then it moves any workspace it created to the saved monitor and sends one notification.
3. A gate protects the snapshot. `sesh-save` writes only when one Hyprland instance is live, and that instance wrote the snapshot or finished its restore. So a save right after login or a crash cannot replace your sessions with an empty set.

Not restored: the SUPER+C scratchpad, claude inside tmux (tmux-resurrect's job), headless sessions and remote (mosh) windows.

Install on a Hyprland box:

1. `./install` links `sesh/systemd/sesh-save.{service,timer}` into `~/.config/systemd/user/`, and it enables the timer when `Hyprland` is installed. To do it by hand, link the two files, then run `systemctl --user daemon-reload && systemctl --user enable --now sesh-save.timer`.
2. `hypr/hyprland.lua` already runs `sesh-restore` inside `hl.on("hyprland.start", …)`.

Check it:

- `systemctl --user list-timers sesh-save.timer` shows the timer.
- `jq '.local[] | {id, ws, monitor}' ~/.local/state/sesh/snapshot.json` lists the saved sessions and their workspaces.
- `SESH_DRYRUN=1 revive` prints the windows a restore would open.
- `~/.local/state/sesh/restore.log` records each restore.

Recover sessions that died without a reboot, for example after earlyoom killed a few:

1. Pick a file in `~/.local/state/sesh/history/`, which keeps the last 20 distinct snapshots.
2. Run `SESH_SNAPSHOT=<that file> revive`. Restore skips sessions that are running, so only the missing ones open.

If saves stop after a Hyprland restart, the restore for that instance never ran. Run `revive` once.

```

- [ ] **Step 3: Update the file map table**

In the table under `## The pieces (file map)`:

1. Replace the `sesh/sesh-save` row with:
   ```markdown
   | `sesh/sesh-save` | Snapshots live local (PID-checked) + remote (marker) sessions to `snapshot.json`. On Linux it also records each window's workspace and monitor. |
   ```
2. Replace the `sesh/sesh-restore` row with:
   ```markdown
   | `sesh/sesh-restore` | Rebuilds the snapshot as windows: Ghostty at login on macOS, placed foot windows at Hyprland start on Linux. Skips live ones; caps the count. |
   ```
3. Replace the `sesh/sesh-local` row with:
   ```markdown
   | `sesh/sesh-local` | Launcher for a **local** Claude session: `cd`, set title, resume Claude. `--sid <uuid>` is the Linux restore form. |
   ```
4. Replace the `sesh/tests/sesh.test.sh` row with:
   ```markdown
   | `sesh/tests/sesh.test.sh` | 156 tests (cache, multi-host, self-detection, Linux save and restore). Fakes `ssh`, `hyprctl` and `/proc`, so nothing live is touched. |
   ```
5. Directly after the `sesh/sesh` row, add:
   ```markdown
   | `sesh/lib/os.sh` | OS-specific primitives the three scripts share: window spawn, liveness, Hyprland capture and placement, the save gate. |
   | `sesh/systemd/sesh-save.{service,timer}` | Linux: runs `sesh-save` every 60 s. |
   | `hypr/hyprland.lua` | Linux: runs `sesh-restore` at Hyprland start. |
   ```

- [ ] **Step 4: Update the flags table, the limitations and the test count**

1. In the `## Flags and environment` table, replace the `SESH_CAP` row with:
   ```markdown
   | | `SESH_CAP` | Max windows `sesh-restore` opens (default 12 on macOS, 20 on Linux) |
   ```
2. Directly after the `SESH_SSH` row, add:
   ```markdown
   | | `SESH_TERMINAL` | Linux terminal for a new window (default foot) |
   | | `SESH_STAGGER` | Linux: seconds between restored windows (default 1.5) |
   | | `SESH_VERIFY_WAIT` | Linux: whole seconds restore waits for windows to start (default 15) |
   | | `SESH_SNAPSHOT` | Restore from this file instead of `snapshot.json` |
   | | `SESH_SKIP_BOOTGUARD` | Skip the save gate (manual runs and tests) |
   | | `SESH_HYPRCTL`, `SESH_PROC`, `SESH_NOTIFY`, `SESH_UNAME` | Test seams: `hyprctl` binary, `/proc` root, notifier, OS |
   | | `SESH_TEST_ONLY` | Run only the named tests in the suite |
   ```
3. In `## Known limitations`, replace the bullet that starts `- **Restore fires at login, not on crash.**` with:
   ```markdown
   - **macOS restore fires at login, not on crash.** After a force-quit or a terminal crash, run `revive` by hand. On Linux, restore runs at every Hyprland start, so a compositor crash is covered. A single foot window that dies still needs `revive`.
   ```
4. In `## Verify and test`, replace the line `# -> # passed 18, failed 0` with `# -> # passed 156, failed 0`.

- [ ] **Step 5: Run the full checks on hexane**

Run:
```bash
SESH_BIN="$WT/sesh/sesh" bash "$WT/sesh/tests/sesh.test.sh" | tail -1
for f in sesh sesh-save sesh-restore sesh-local sesh-remote lib/os.sh; do bash -n "$WT/sesh/$f" && echo "syntax ok: $f"; done
python3 ~/.claude/skills/de-slopping/ste_lint.py "$WT/sesh/docs/2026-10-19-sesh-linux-b2-design.md" | tail -1
```
Expected: `# passed 156, failed 0`, six `syntax ok` lines, and `0 hard` in the lint summary.

- [ ] **Step 6: Run the suite under the Mac's bash 3.2**

This copies only the worktree's `sesh/` folder to a temp dir on the Mac (`ssh laptop`). It touches nothing else there.

Run:
```bash
tar -C "$WT" -cf - sesh | ssh -o BatchMode=yes -o ConnectTimeout=5 laptop 'rm -rf /tmp/sesh-b2 && mkdir -p /tmp/sesh-b2 && tar -C /tmp/sesh-b2 -xf -'
ssh -o BatchMode=yes laptop 'cd /tmp && PATH=/opt/homebrew/bin:$PATH SESH_BIN=/tmp/sesh-b2/sesh/sesh /bin/bash /tmp/sesh-b2/sesh/tests/sesh.test.sh | tail -1; rm -rf /tmp/sesh-b2'
```
Expected: `# passed 156, failed 0`. If the laptop is unreachable, report that and continue: Task 11 repeats this check.

- [ ] **Step 7: Commit**

```bash
git -C "$WT" add sesh/README.md
git -C "$WT" -c core.hooksPath=/dev/null commit -m "sesh: document the Linux auto-save and restore" \
  -m "The README gains a Linux section covering how the save, gate and restore work, the install steps, the checks and recovery from history. The file map, flags table, limitations and test count are updated." \
  -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: Pull request (controller)

**Run from:** the controller session, not a subagent.

- [ ] **Step 1: Confirm the branch holds only this work**

Run: `git -C "$WT" fetch -q origin && git -C "$WT" log --oneline origin/master..HEAD && git -C "$WT" diff --stat origin/master...HEAD`
Expected: the spec and plan commit plus the nine task commits. Only files from the file structure table, the spec and this plan change.

- [ ] **Step 2: Push and open the PR**

```bash
git -C "$WT" push -u origin feat/sesh-linux-b2
gh pr create --repo issmirnov/dotfiles --base master --head feat/sesh-linux-b2 \
  --title "sesh: Linux auto-save and login restore for foot windows (B2)" --body-file <body file>
```

Write the body in plain English with no em-dashes. Cover what it does, how it is tested (156 tests on hexane and under the Mac's bash 3.2), what is deliberately left out, and the deploy steps from Task 11. End it with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

- [ ] **Step 3: Wait for the review bots**

Follow the watching-pr-bot-reviews skill: run `prbots wait <PR> --trigger` in the background, then read `prbots <PR>` and handle the findings.

---

## Task 11: Deploy and acceptance on hexane (controller and user, after the merge)

**Run from:** the controller session, with the user. Do this only after the user merges the PR.

- [ ] **Step 1: Update the main checkout safely.** Run `git -C ~/.dotfiles status --short` first. Other sessions keep local edits there, and `git pull` autostashes them. Pull only when the tree is clean or the user says to proceed.
- [ ] **Step 2: Link and enable the units** (no sudo needed):
  ```bash
  ln -s ~/.dotfiles/sesh/systemd/sesh-save.service ~/.dotfiles/sesh/systemd/sesh-save.timer ~/.config/systemd/user/
  systemctl --user daemon-reload && systemctl --user enable --now sesh-save.timer
  ```
- [ ] **Step 3: Check the first save.** Within a minute, `jq '.local[] | {id, ws, monitor}' ~/.local/state/sesh/snapshot.json` lists every foot Claude session, and the workspaces and monitors match `hyprctl clients -j`.
- [ ] **Step 4: Check the plan.** `SESH_DRYRUN=1 revive` prints one `hyprctl eval:` spawn line per session that is not running.
- [ ] **Step 5: Logout test (user).** The user logs out of Hyprland and back in. Each window returns to its workspace and monitor with no duplicates, the notification is correct, `~/.local/state/sesh/restored` holds the new instance, and `snapshot.json` updates again within a minute.
- [ ] **Step 6: Reboot test (user).** The same result after a real reboot.
- [ ] **Step 7: Mac check (user or controller).** After the Mac pulls, `launchctl list | grep sesh` is unchanged and `SESH_DRYRUN=1 revive` prints the same kind of lines as before.
- [ ] **Step 8: Update memory.** Update `session-restore-status.md` to say hexane auto-restore is live.

---

## Self-review notes

**Spec coverage.**
- A (shared layer): Tasks 1, 2, 3, 4 and 6.
- B (capture): Task 3.
- C (save, including the instance rule of the gate): Task 4.
- D (restore): Task 7, with the trigger in Task 8.
- E (`--sid`): Task 5.
- F (units and wiring): Task 8.
- G (probe results): shapes Tasks 6 and 7.
- Testing items 1 to 12: Tasks 2 to 7. Item 13 (regression): Tasks 1 and 7.
- Verification: Tasks 9 and 11. Rollout: Tasks 10 and 11.

**Edge cases.**
- An unplugged monitor is covered by the `have` check before `_move_workspace`, but no dedicated test exercises it.
- The earlyoom recovery path (`SESH_SNAPSHOT`) is an existing seam, documented in Task 9.

**Signatures used across tasks.**
- `_capture_windows <pid>…`, `_alive <pid> [procStart]`, `_spawn_placed <id> [ws]`, `_move_window <address> <ws>`, `_move_workspace <ws> <monitor>`, `_save_gate` and `_proc_stat <pid>` keep the same names and arguments in every task that uses them.
- Test helpers build on each other: `mkcapture` calls `mkhypr`, `mksave` calls `mkcapture`, and `mkrestore` calls `mkhypr`.

## Revisions during execution

- **Task 3 capture (review fix, commits 7164472 and 209f22c).** jq `@tsv` escaped backslashes and nothing decoded them, so a workspace named `a\b` came back as `a\\b`. `_capture_windows` now builds one JSON object keyed by window PID. It reads the clients JSON on stdin, checks every jq status, and uses `jq -e`, so an empty hyprctl reply fails closed instead of reporting every session as headless. The fixture gains window 370 on workspace `a\b`, and `t_capture_fail_closed` asserts status 1 for bad, non-array and empty replies. Three assertions were added, so later counts are three higher than first planned. The Task 3 code block above shows the original version.
- **Task 4 save (review fix, commit 782dd38).** A non-numeric `updatedAt` made the per-file jq fail, so `|| continue` dropped the session. On the Mac that changed behavior, because the old script never read the field. The conversion is now total (`if type == "number" … else 0`). Fail-closed exits print `sesh-save: … snapshot left as is` to stderr, and history is copied only after the snapshot write succeeds. The two-instance gate fixture is `SIG1,B`, so the test fails if the exactly-one rule goes. A new test, `t_save_odd_updatedat`, and one stderr assertion add three assertions in all.

**Known deviations from the spec text, already folded into the spec.**
- The gate also passes when the snapshot's `instance` is the live instance.
- The macOS restore loop stays separate.
- `SESH_SKIP_BOOTGUARD` also skips the Linux gate.
- Four existing tests change.
