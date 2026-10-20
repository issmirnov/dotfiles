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

# ---- window capture ------------------------------------------------------------------
# _capture_windows <pid>... : print a JSON object keyed by each claude PID:
#   {"ws":"argo","monitor":"DP-1","at":[x,y],"address":"0x…"}  a placed window
#   {}                                       a window PID several windows share (foot server mode)
#   {"skip":"tmux"|"headless"|"scratchpad"}  not a restorable window
# Each claude PID walks up its parents to the first PID that hyprctl lists as a window.
# A tmux ancestor ends the walk (tmux-resurrect owns those panes). macOS and other OSes
# print {}. On Linux a failed Hyprland query or jq step returns non-zero, so callers fail closed.
_capture_windows(){
  local clients="" monitors="" wins="" winpids="" out='{}' pid="" p="" hops=0 st="" val=""
  [ "$SESH_OS" = linux ] || { printf '{}'; return 0; }
  [ $# -gt 0 ] || { printf '{}'; return 0; }
  clients="$("$HYPRCTL" clients -j 2>/dev/null)" || return 1
  monitors="$("$HYPRCTL" monitors -j 2>/dev/null)" || return 1
  # One JSON object keyed by window PID, with each value already in its final shape.
  # It stays JSON end to end (no TSV round trip), so a workspace name keeps its backslashes.
  wins="$(printf '%s' "$clients" | jq -ce --argjson m "$monitors" '
      if type != "array" or ($m | type) != "array" then error("bad hyprctl json") else . end
      | ($m | map({key: (.id | tostring), value: .name}) | from_entries) as $mn
      | group_by(.pid)
      | map({key: (.[0].pid | tostring), value:
          (if length != 1 then {}
           elif .[0].class == "scratchpad" then {skip: "scratchpad"}
           else {ws: .[0].workspace.name, monitor: ($mn[(.[0].monitor | tostring)] // ""), at: .[0].at, address: .[0].address} end)})
      | from_entries' 2>/dev/null)" || return 1
  winpids="$(printf '%s' "$wins" | jq -r 'keys[]')" || return 1
  for pid in "$@"; do
    p="$pid"; hops=0; val='{"skip":"headless"}'
    while [ "$hops" -lt 64 ]; do
      if printf '%s\n' "$winpids" | grep -Fxq -- "$p"; then
        val="$(printf '%s' "$wins" | jq -c --arg p "$p" '.[$p]')" || return 1
        break
      fi
      st="$(_proc_stat "$p")" || break
      case "${st#* * }" in tmux*) val='{"skip":"tmux"}'; break ;; esac
      p="${st%% *}"
      [ "$p" -gt 1 ] 2>/dev/null || break
      hops=$((hops + 1))
    done
    out="$(printf '%s' "$out" | jq -c --arg k "$pid" --argjson v "$val" '. + {($k): $v}')" || return 1
  done
  printf '%s' "$out"
}

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
