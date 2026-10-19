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
