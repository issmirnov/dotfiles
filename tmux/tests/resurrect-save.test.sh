#!/bin/bash
# Tests for tmux/resurrect-save, which saves the tmux environment from
# tmux-resurrect-save.timer (every 60 s) and tmux-resurrect-shutdown.service (once, when
# logind announces a shutdown). Fakes tmux, busctl and resurrect's save script. Also
# checks the units and their links in ubuntu.conf.yaml.
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
# event left, the wait fails. --help lists the wait verb unless RZ_FAKE_NO_WAIT.
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
  *" get-property "*) echo "b \$(cat "$T/preparing" 2>/dev/null || echo false)" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$T/bin/tmux" "$T/save.sh" "$T/bin/busctl"
export RZ_TMUX="$T/bin/tmux" RZ_BUSCTL="$T/bin/busctl" RZ_LOCK="$T/save.lock"
_saves(){ [ -f "$T/saves.log" ] && tr '\n' '|' < "$T/saves.log"; }   # the save log on one line
_waits(){ grep -c ' wait ' "$T/busctl.log" 2>/dev/null; }             # how many times it waited
_reset(){ rm -f "$T/saves.log" "$T/busctl.log" "$T/events" "$T/preparing"; }

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

echo "# resurrect-save --at-shutdown (the shutdown saver)"
_reset; echo "ok true" > "$T/events"; bash "$SAVE" --at-shutdown; rc=$?
check "when logind prepares to shut down it saves once and exits 0"       "$rc|$(_saves)" "0|start quiet|end|"
check "it waits for logind's PrepareForShutdown on the system bus"        "$(grep -c -- '^--system wait /org/freedesktop/login1 org.freedesktop.login1.Manager PrepareForShutdown$' "$T/busctl.log")" "1"
_reset; printf 'ok false\nok true\n' > "$T/events"; bash "$SAVE" --at-shutdown; rc=$?
check "a PrepareForShutdown with no shutdown under way is ignored"        "$rc|$(_saves)" "0|start quiet|end|"
check "and it goes back to waiting"                                       "$(_waits)" "2"
_reset; echo "fail false" > "$T/events"; bash "$SAVE" --at-shutdown; rc=$?
check "a failed wait exits non-zero without saving, so systemd restarts it" "$rc|$(_saves)" "1|"
_reset; echo "fail true" > "$T/events"; bash "$SAVE" --at-shutdown; rc=$?
check "a failed wait during a real shutdown still saves"                  "$rc|$(_saves)" "0|start quiet|end|"
_reset; echo "ok true" > "$T/events"; RZ_FAKE_NO_SESSIONS=1 bash "$SAVE" --at-shutdown; rc=$?
check "at shutdown with no sessions it saves nothing and exits 0"         "$rc|$(_saves)" "0|"
_reset; err="$(RZ_FAKE_NO_WAIT=1 bash "$SAVE" --at-shutdown 2>&1 >/dev/null)"; rc=$?
check "a busctl with no wait verb exits 0 at once, with no restart loop"  "$rc|$(_waits)" "0|0"
check "and says why in the journal"                                       "$err" "busctl has no wait verb; tmux will not be saved at shutdown"

echo "# units and links"
U="$ROOT/systemd"
check "the timer saves every 60 s"                                    "$(grep -c '^OnUnitActiveSec=60s$' "$U/tmux-resurrect-save.timer" 2>/dev/null)" "1"
check "the timed save waits for the boot restore to finish"           "$(grep -c '^After=tmux-resurrect.service$' "$U/tmux-resurrect-save.service" 2>/dev/null)" "1"
check "the shutdown saver holds a logind shutdown delay lock"         "$(grep -c '^ExecStart=/usr/bin/systemd-inhibit --what=shutdown --mode=delay .*/tmux/resurrect-save --at-shutdown$' "$U/tmux-resurrect-shutdown.service" 2>/dev/null)" "1"
for f in "$U"/tmux-resurrect*.service "$U"/tmux-resurrect*.timer; do
  [ -e "$f" ] || continue
  b="$(basename "$f")"
  check "ubuntu.conf.yaml links $b" "$(grep -c "^ *~/.config/systemd/user/$b: systemd/$b\$" "$ROOT/ubuntu.conf.yaml")" "1"
done

echo "# ---"
echo "# passed $P, failed $F"
[ "$F" -eq 0 ]
