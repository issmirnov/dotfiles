#!/bin/bash
# Tests for tmux/resurrect-save, which saves the tmux environment from
# tmux-resurrect-save.timer (every 60 s) and tmux-resurrect-shutdown.service (once, when
# logind announces a shutdown). Fakes tmux, busctl, gdbus and resurrect's save script.
# Also checks the units and their links in ubuntu.conf.yaml.
#
#   bash tmux/tests/resurrect-save.test.sh
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SAVE="$ROOT/tmux/resurrect-save"
P=0; F=0
ok(){ P=$((P+1)); echo "ok $((P+F)) - $1"; }
no(){ F=$((F+1)); echo "NOT OK $((P+F)) - $1"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$3', got '$2')"; fi; }   # check <name> <got> <want>

T="$(mktemp -d)"; trap 'rm -rf -- "${T:?}"' EXIT
mkdir -p "$T/bin"
# Fake tmux: a server with one session, unless RZ_FAKE_NO_SERVER or RZ_FAKE_NO_SESSIONS.
# It reports the fake save script as resurrect's (unless RZ_FAKE_NO_RESURRECT), and
# run-shell runs its command the way tmux does.
cat > "$T/bin/tmux" <<EOF
#!/bin/bash
case "\$1" in
  list-sessions)
    [ -n "\${RZ_FAKE_NO_SERVER:-}" ] && { echo "no server running" >&2; exit 1; }
    [ -n "\${RZ_FAKE_NO_SESSIONS:-}" ] || echo work ;;
  show-options) [ -n "\${RZ_FAKE_NO_RESURRECT:-}" ] || echo "$T/save.sh" ;;
  run-shell) sh -c "\$2" ;;
  *) exit 1 ;;
esac
EOF
# Fake resurrect save script: logs its start and end, and takes RZ_FAKE_SAVE_SECS.
cat > "$T/save.sh" <<EOF
#!/bin/bash
echo "start \$*" >> "$T/saves.log"
[ -z "\${RZ_FAKE_SAVE_SECS:-}" ] || sleep "\$RZ_FAKE_SAVE_SECS"
echo end >> "$T/saves.log"
EOF
# Fake busctl. Each `wait` takes the next line of \$T/events, "<ok|fail> <true|false>":
# how the wait ends, and what logind's PreparingForShutdown reads afterwards. With no
# event left, the wait fails. Each get-property takes the next line of \$T/preparing,
# and reads false when none is left. --help lists the wait verb unless RZ_FAKE_NO_WAIT.
cat > "$T/bin/busctl" <<EOF
#!/bin/bash
echo "\$*" >> "$T/busctl.log"
case "\$*" in
  --help) [ -n "\${RZ_FAKE_NO_WAIT:-}" ] || echo "  wait OBJECT INTERFACE SIGNAL" ;;
  *" wait "*)
    ev="\$(head -n 1 "$T/events" 2>/dev/null)"; sed -i 1d "$T/events" 2>/dev/null
    [ -n "\$ev" ] || exit 3
    echo "\${ev#* }" > "$T/preparing"
    [ "\${ev%% *}" = ok ] || exit 1
    echo "b true" ;;
  *" get-property "*)
    v="\$(head -n 1 "$T/preparing" 2>/dev/null)"; sed -i 1d "$T/preparing" 2>/dev/null
    echo "b \${v:-false}" ;;
  *) exit 1 ;;
esac
EOF
# Fake gdbus monitor: prints \$T/signals, then stays up like the real monitor
# (RZ_FAKE_HOLD) or exits, which is the bus going away.
cat > "$T/bin/gdbus" <<EOF
#!/bin/bash
echo "\$*" >> "$T/gdbus.log"
echo \$\$ > "$T/gdbus.pid"
[ -f "$T/signals" ] && cat "$T/signals"
[ -n "\${RZ_FAKE_HOLD:-}" ] && exec sleep 300
exit 0
EOF
chmod +x "$T/bin/tmux" "$T/save.sh" "$T/bin/busctl" "$T/bin/gdbus"
export RZ_TMUX="$T/bin/tmux" RZ_BUSCTL="$T/bin/busctl" RZ_GDBUS="$T/bin/gdbus" RZ_LOCK="$T/save.lock"
_saves(){ [ -f "$T/saves.log" ] && tr '\n' '|' < "$T/saves.log"; }   # the save log on one line
# _count <pattern> <log> : how many lines of <log> match. 0 when there is no log.
_count(){ if [ -f "$2" ]; then grep -c -- "$1" "$2"; else echo 0; fi; }
_waits(){ _count ' wait ' "$T/busctl.log"; }                          # how many times it waited
_props(){ _count ' get-property ' "$T/busctl.log"; }                  # how many times it read PreparingForShutdown
_monitors(){ _count '^monitor ' "$T/gdbus.log"; }                     # how many gdbus monitors it started
# _monitor_alive : is the fake gdbus monitor still running? It gets 2 s to go.
_monitor_alive(){
  local pid="" i=0
  pid="$(cat "$T/gdbus.pid" 2>/dev/null)"
  while [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; do
    i=$((i+1)); [ "$i" -lt 20 ] || { echo yes; return; }
    sleep 0.1
  done
  echo no
}
_reset(){ rm -f "$T/saves.log" "$T/busctl.log" "$T/gdbus.log" "$T/gdbus.pid" "$T/events" "$T/signals" "$T/preparing"; }
# _gdbus_saver : the shutdown saver where busctl has no wait verb, so it listens through
# the fake gdbus. Capped at 10 s, so a saver that never exits fails its check instead of
# hanging the run.
_gdbus_saver(){ RZ_FAKE_NO_WAIT=1 timeout 10 bash "$SAVE" --at-shutdown; }

echo "# resurrect-save (the timer's save)"
_reset; bash "$SAVE"; rc=$?
check "with sessions it runs the server's resurrect save script once, quietly" "$rc|$(_saves)" "0|start quiet|end|"
_reset; RZ_FAKE_NO_SERVER=1 bash "$SAVE"; rc=$?
check "with no tmux server it saves nothing"                              "$rc|$(_saves)" "0|"
_reset; RZ_FAKE_NO_SESSIONS=1 bash "$SAVE"; rc=$?
check "with no sessions it saves nothing, so the restore point survives"  "$rc|$(_saves)" "0|"
_reset; RZ_FAKE_NO_RESURRECT=1 bash "$SAVE"; rc=$?
check "without tmux-resurrect loaded it saves nothing"                    "$rc|$(_saves)" "0|"
_reset; RZ_FAKE_SAVE_SECS=1 bash "$SAVE" & RZ_FAKE_SAVE_SECS=1 bash "$SAVE"; wait
check "two saves at once run one after the other"                         "$(_saves)" "start quiet|end|start quiet|end|"

echo "# resurrect-save --at-shutdown, where busctl has the wait verb (systemd 257 and later)"
_reset; echo "ok true" > "$T/events"; bash "$SAVE" --at-shutdown; rc=$?
check "when logind prepares to shut down it saves once and exits 0"       "$rc|$(_saves)" "0|start quiet|end|"
check "it waits for logind's PrepareForShutdown on the system bus"        "$(grep -c -- '^--system wait /org/freedesktop/login1 org.freedesktop.login1.Manager PrepareForShutdown$' "$T/busctl.log")" "1"
check "and starts no gdbus monitor"                                       "$(_monitors)" "0"
_reset; printf 'ok false\nok true\n' > "$T/events"; bash "$SAVE" --at-shutdown; rc=$?
check "a PrepareForShutdown with no shutdown under way is ignored"        "$rc|$(_saves)" "0|start quiet|end|"
check "and it goes back to waiting"                                       "$(_waits)" "2"
_reset; echo "fail false" > "$T/events"; bash "$SAVE" --at-shutdown; rc=$?
check "a failed wait exits non-zero without saving, so systemd restarts it" "$rc|$(_saves)" "1|"
_reset; echo "fail true" > "$T/events"; bash "$SAVE" --at-shutdown; rc=$?
check "a failed wait during a real shutdown still saves"                  "$rc|$(_saves)" "0|start quiet|end|"
_reset; echo "ok true" > "$T/events"; RZ_FAKE_NO_SESSIONS=1 bash "$SAVE" --at-shutdown; rc=$?
check "at shutdown with no sessions it saves nothing and exits 0"         "$rc|$(_saves)" "0|"

echo "# resurrect-save --at-shutdown, where busctl has no wait verb (systemd 255): gdbus monitor"
# What gdbus monitor prints: a header, then one line per signal. For one shutdown, logind
# sends PrepareForShutdownWithMetadata and then PrepareForShutdown.
HDR='Monitoring signals on object /org/freedesktop/login1 owned by org.freedesktop.login1
The name org.freedesktop.login1 is owned by :1.4'
SESS="/org/freedesktop/login1: org.freedesktop.login1.Manager.SessionNew ('c5', objectpath '/org/freedesktop/login1/session/c5')"
PREP_M="/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForShutdownWithMetadata (true, {'type': <'reboot'>})"
PREP_T='/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForShutdown (true,)'
PREP_F='/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForShutdown (false,)'
_reset; printf '%s\n' "$HDR" "$SESS" "$PREP_M" "$PREP_T" > "$T/signals"; echo true > "$T/preparing"
RZ_FAKE_HOLD=1 _gdbus_saver; rc=$?
check "on logind's two shutdown signals it checks once, saves once and exits 0" "$rc|$(_saves)|$(_props)" "0|start quiet|end||1"
check "it never runs busctl wait"                                         "$(_waits)" "0"
check "it watches only logind's signals on the system bus"                "$(cat "$T/gdbus.log")" "monitor --system --dest org.freedesktop.login1 --object-path /org/freedesktop/login1"
check "and it stops its gdbus monitor on the way out"                     "$(_monitor_alive)" "no"
_reset; printf '%s\n' "$PREP_T" "$PREP_T" > "$T/signals"; printf 'false\ntrue\n' > "$T/preparing"
RZ_FAKE_HOLD=1 _gdbus_saver; rc=$?
check "a PrepareForShutdown with no shutdown under way is ignored, and it reads on" "$rc|$(_saves)|$(_props)" "0|start quiet|end||2"
_reset; printf '%s\n' "$PREP_M" > "$T/signals"; echo true > "$T/preparing"
_gdbus_saver; rc=$?
check "the WithMetadata twin alone triggers no check and no save"         "$rc|$(_saves)|$(_props)" "1||0"
_reset; printf '%s\n' "$PREP_F" > "$T/signals"; echo true > "$T/preparing"
_gdbus_saver; rc=$?
check "a cancelled shutdown, PrepareForShutdown (false), triggers no check" "$rc|$(_saves)|$(_props)" "1||0"
_reset; _gdbus_saver; rc=$?
check "a monitor that dies exits 1 without saving, so systemd restarts it" "$rc|$(_saves)|$(_props)" "1||0"
_reset; printf '%s\n' "$PREP_T" "$PREP_T" > "$T/signals"; printf 'false\ntrue\n' > "$T/preparing"
_gdbus_saver; rc=$?
check "signals that a monitor printed before it died are still read"      "$rc|$(_saves)|$(_props)" "0|start quiet|end||2"
_reset; printf '%s\n' "$PREP_T" > "$T/signals"; echo true > "$T/preparing"
RZ_FAKE_HOLD=1 RZ_FAKE_NO_SESSIONS=1 _gdbus_saver; rc=$?
check "at shutdown with no sessions it saves nothing and exits 0"         "$rc|$(_saves)" "0|"

echo "# resurrect-save --at-shutdown with neither listener"
_reset; err="$(RZ_FAKE_NO_WAIT=1 RZ_GDBUS="$T/bin/no-gdbus" bash "$SAVE" --at-shutdown 2>&1 >/dev/null)"; rc=$?
check "with no busctl wait and no gdbus it exits 0 at once, with no restart loop" "$rc|$(_waits)|$(_monitors)" "0|0|0"
check "and says why in the journal"                                       "$err" "neither busctl wait nor gdbus is available; tmux will not be saved at shutdown"

echo "# units and links"
U="$ROOT/systemd"
check "the timer saves every 60 s"                                    "$(grep -c '^OnUnitActiveSec=60s$' "$U/tmux-resurrect-save.timer" 2>/dev/null)" "1"
check "the timed save waits for the boot restore to finish"           "$(grep -c '^After=tmux-resurrect.service$' "$U/tmux-resurrect-save.service" 2>/dev/null)" "1"
check "the shutdown saver holds a logind shutdown delay lock"         "$(grep -c '^ExecStart=/usr/bin/systemd-inhibit --what=shutdown --mode=delay .*/tmux/resurrect-save --at-shutdown$' "$U/tmux-resurrect-shutdown.service" 2>/dev/null)" "1"
check "the shutdown saver stops restarting after 5 starts in 10 min"  "$(sed -n '/^\[Unit\]/,/^\[/p' "$U/tmux-resurrect-shutdown.service" 2>/dev/null | grep -c -e '^StartLimitIntervalSec=10min$' -e '^StartLimitBurst=5$')" "2"
for f in "$U"/tmux-resurrect*.service "$U"/tmux-resurrect*.timer; do
  [ -e "$f" ] || continue
  b="$(basename "$f")"
  check "ubuntu.conf.yaml links $b" "$(grep -c "^ *~/.config/systemd/user/$b: systemd/$b\$" "$ROOT/ubuntu.conf.yaml")" "1"
done

echo "# ---"
echo "# passed $P, failed $F"
[ "$F" -eq 0 ]
