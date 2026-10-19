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
