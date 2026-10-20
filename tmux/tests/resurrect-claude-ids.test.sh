#!/bin/bash
# Tests for tmux-resurrect boot restore:
#   - tmux/resurrect-claude-ids, the post-save hook that records each Claude pane's
#     session ID (fake tmux, ps, /proc and registry);
#   - the @resurrect-processes entries in tmux/tmux.conf, run through tmux-resurrect's
#     own matching code (the submodule must be checked out);
#   - systemd/enable-tmux-resurrect (fake systemctl and HOME).
#
#   bash tmux/tests/resurrect-claude-ids.test.sh
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
HOOK="$ROOT/tmux/resurrect-claude-ids"
ENABLE="$ROOT/systemd/enable-tmux-resurrect"
RES="${RZ_RESURRECT_DIR:-$ROOT/tmux/plugins/tmux-resurrect}"
P=0; F=0
ok(){ P=$((P+1)); echo "ok $((P+F)) - $1"; }
no(){ F=$((F+1)); echo "NOT OK $((P+F)) - $1"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$3', got '$2')"; fi; }   # check <name> <got> <want>

T="$(mktemp -d)"; trap 'rm -rf -- "${T:?}"' EXIT
A=aaaaaaaa-0000-0000-0000-00000000000a   # work:1.0   live claude, registry entry
S=0ccf0000-1111-2222-3333-444444444444   # work:2.0   restored by sesh-local, then /resume switched it to L
L=11111111-0000-0000-0000-000000000001   # work:2.0   the conversation it runs now (registry)
R=22222222-0000-0000-0000-000000000002   # work:2.1   restored by sesh-local, claude not started yet
B=bbbbbbbb-0000-0000-0000-00000000000b   # other:1.1  a non-interactive session
C=cccccccc-0000-0000-0000-00000000000c   # other:2.0  a stale entry whose PID was reused

# Seven panes. The process tree under each pane shell:
#   work:1.0   100 zsh -> 101 claude                 registry: A, procStart matches
#   work:1.1   110 zsh                               no claude
#   work:2.0   120 zsh -> 121 bash -> 122 claude     registry: L; the saved command still has --sid S
#   work:2.1   125 zsh -> 126 bash                   no claude yet; the saved command has --sid R
#   other:1.0  130 zsh -> 131 claude                 registry ID is not a UUID
#   other:1.1  140 zsh -> 141 claude                 registry kind sdk-cli
#   other:2.0  150 zsh -> 151 claude                 registry procStart 99, process started at 7
mkdir -p "$T/bin" "$T/sessions" "$T/proc/101" "$T/proc/151"
cat > "$T/bin/tmux" <<'EOF'
#!/bin/bash
[ "${1:-}" = list-panes ] || exit 1
[ -n "${RZ_FAKE_TMUX_DOWN:-}" ] && exit 1
printf 'work\t1\t0\t100\nwork\t1\t1\t110\nwork\t2\t0\t120\nwork\t2\t1\t125\nother\t1\t0\t130\nother\t1\t1\t140\nother\t2\t0\t150\n'
EOF
cat > "$T/bin/ps" <<'EOF'
#!/bin/bash
printf '%s\n' '100 1 zsh' '101 100 claude' '110 1 zsh' '120 1 zsh' '121 120 bash' '122 121 claude' '125 1 zsh' '126 125 bash' \
  '130 1 zsh' '131 130 claude' '140 1 zsh' '141 140 claude' '150 1 zsh' '151 150 claude'
EOF
chmod +x "$T/bin/tmux" "$T/bin/ps"
printf '{"pid":101,"sessionId":"%s","kind":"interactive","procStart":"5"}\n' "$A" > "$T/sessions/101.json"
printf '{"pid":122,"sessionId":"%s","kind":"interactive"}\n' "$L"                     > "$T/sessions/122.json"
printf '{"pid":131,"sessionId":"x; rm -rf ~","kind":"interactive"}\n'          > "$T/sessions/131.json"
printf '{"pid":141,"sessionId":"%s","kind":"sdk-cli"}\n' "$B"                    > "$T/sessions/141.json"
printf '{"pid":151,"sessionId":"%s","kind":"interactive","procStart":"99"}\n' "$C" > "$T/sessions/151.json"
printf '101 (claude) S 100 0 0 0 0 0 0 0 0 0 0 0 0 0 20 0 1 0 5 0 0\n' > "$T/proc/101/stat"
printf '151 (claude) S 150 0 0 0 0 0 0 0 0 0 0 0 0 0 20 0 1 0 7 0 0\n' > "$T/proc/151/stat"
export RZ_TMUX="$T/bin/tmux" RZ_PS="$T/bin/ps" RZ_PROC="$T/proc" RZ_SESSIONS="$T/sessions"

# _state : a resurrect state file for the seven panes, plus a window and a state line.
_state(){ local t=$'\t'
  printf '%s\n' \
    "pane${t}work${t}1${t}1${t}:*${t}0${t}t${t}:/w/a${t}1${t}claude${t}:/home/u/.local/bin/claude --dangerously-skip-permissions" \
    "pane${t}work${t}1${t}1${t}:*${t}1${t}t${t}:/w/b${t}0${t}zsh${t}:" \
    "pane${t}work${t}2${t}0${t}:-${t}0${t}t${t}:/w/c${t}1${t}bash${t}:/bin/bash /home/u/.dotfiles/sesh/sesh-local --sid $S" \
    "pane${t}work${t}2${t}0${t}:-${t}1${t}t${t}:/w/c${t}0${t}bash${t}:/bin/bash /home/u/.dotfiles/sesh/sesh-local --sid $R" \
    "pane${t}other${t}1${t}1${t}:*${t}0${t}t${t}:/w/d${t}1${t}claude${t}:/home/u/.local/bin/claude" \
    "pane${t}other${t}1${t}1${t}:*${t}1${t}t${t}:/w/e${t}0${t}claude${t}:/home/u/.local/bin/claude -p hi" \
    "pane${t}other${t}2${t}0${t}:-${t}0${t}t${t}:/w/f${t}1${t}claude${t}:/home/u/.local/bin/claude" \
    "window${t}work${t}1${t}:w1${t}1${t}:*${t}layout${t}:" \
    "state${t}work${t}other"
}
# _cmd <file> <session> <window> <pane> : that pane's saved command (field 11).
_cmd(){ awk -F'\t' -v s="$2" -v w="$3" -v p="$4" '$1 == "pane" && $2 == s && $3 == w && $6 == p { print $11 }' "$1"; }

echo "# resurrect-claude-ids (post-save hook)"
_state > "$T/save.txt"; cp "$T/save.txt" "$T/before.txt"
bash "$HOOK" "$T/save.txt"
check "a live claude pane is saved with its session ID"           "$(_cmd "$T/save.txt" work 1 0)"  ":sesh-local --sid $A"
check "a pane with no claude keeps its command"                   "$(_cmd "$T/save.txt" work 1 1)"  ":"
check "a live claude two levels down wins over the saved --sid"   "$(_cmd "$T/save.txt" work 2 0)"  ":sesh-local --sid $L"
check "a restored pane with no claude yet keeps its saved --sid"  "$(_cmd "$T/save.txt" work 2 1)"  ":sesh-local --sid $R"
check "a registry ID that is not a UUID is ignored"               "$(_cmd "$T/save.txt" other 1 0)" ":/home/u/.local/bin/claude"
check "a non-interactive session is ignored"                      "$(_cmd "$T/save.txt" other 1 1)" ":/home/u/.local/bin/claude -p hi"
check "an entry whose procStart does not match is ignored"        "$(_cmd "$T/save.txt" other 2 0)" ":/home/u/.local/bin/claude"
check "window and state lines are unchanged"                      "$(grep -v '^pane' "$T/save.txt")" "$(grep -v '^pane' "$T/before.txt")"
check "every pane line keeps 11 fields"                           "$(awk -F'\t' '$1 == "pane" && NF != 11' "$T/save.txt" | wc -l | tr -d ' ')" "0"
cp "$T/save.txt" "$T/once.txt"; bash "$HOOK" "$T/save.txt"
check "a second run changes nothing"                              "$(cat "$T/save.txt")" "$(cat "$T/once.txt")"
_state > "$T/down.txt"; RZ_FAKE_TMUX_DOWN=1 bash "$HOOK" "$T/down.txt"
check "with tmux unreachable the file is left as resurrect wrote it" "$(cat "$T/down.txt")" "$(cat "$T/before.txt")"
bash "$HOOK" "$T/missing.txt"; rc=$?
check "a missing state file is not an error"                      "$rc" "0"
check "no temp files are left behind"                             "$(ls "$T" | grep -c 'claude-ids')" "0"

echo "# @resurrect-processes in tmux.conf (tmux-resurrect's matching)"
PROCS="$(grep '^set -g @resurrect-processes ' "$ROOT/tmux/tmux.conf" | sed "s/^set -g @resurrect-processes '//; s/'\$//")"
# _typed <full command> : what tmux-resurrect types into the pane for that saved command.
_typed(){ ( set +u; PATH="$T/bin:$PATH"
  . "$RES/scripts/variables.sh"; . "$RES/scripts/helpers.sh"; . "$RES/scripts/process_restore_helpers.sh"
  get_tmux_option(){ if [ "$1" = "$restore_processes_option" ]; then printf '%s' "$PROCS"; else printf '%s' "${2:-}"; fi; }
  _get_inline_strategy "$1" ) }
# _restored <full command> : does tmux-resurrect restore a process for it at all?
_restored(){ ( set +u; PATH="$T/bin:$PATH"
  . "$RES/scripts/variables.sh"; . "$RES/scripts/helpers.sh"; . "$RES/scripts/process_restore_helpers.sh"
  get_tmux_option(){ if [ "$1" = "$restore_processes_option" ]; then printf '%s' "$PROCS"; else printf '%s' "${2:-}"; fi; }
  _process_on_the_restore_list "$1" ) && echo yes || echo no; }
if [ -f "$RES/scripts/process_restore_helpers.sh" ]; then
  check "an ID pane is restored as sesh-local --sid, once (the ID holds 'ccf')" "$(_typed "sesh-local --sid $S")" "~/.dotfiles/sesh/sesh-local --sid $S"
  check "an ID pane is on the restore list"                        "$(_restored "sesh-local --sid $S")" "yes"
  check "a pane without an ID falls back to --continue, once"       "$(_typed "/home/u/.local/bin/claude --dangerously-skip-permissions")" "~/.dotfiles/sesh/sesh-local . continue --continue"
  check "a bare shell is not restored"                              "$(_restored "zsh")" "no"
else
  no "tmux-resurrect is not checked out at $RES (git submodule update --init tmux/plugins/tmux-resurrect)"
fi

echo "# enable-tmux-resurrect"
H="$T/home"; U="$H/.config/systemd/user"
mkdir -p "$U/default.target.wants"
cat > "$T/bin/systemctl" <<EOF
#!/bin/bash
echo "\$*" >> "$T/systemctl.log"
[ "\$*" = "--user show-environment" ] && [ -n "\${RZ_FAKE_NO_BUS:-}" ] && exit 1
exit 0
EOF
chmod +x "$T/bin/systemctl"
ln -s "$T/gone/systemd/tmux.service" "$U/tmux.service"
ln -s "$T/gone/systemd/tmux.service" "$U/default.target.wants/tmux.service"
out="$(HOME="$H" RZ_SYSTEMCTL="$T/bin/systemctl" RZ_FAKE_NO_BUS=1 bash "$ENABLE")"; rc=$?
check "without a systemd --user bus it skips"                    "$rc|$(printf '%s' "$out" | grep -c skipping)" "0|1"
check "and leaves the old links alone"                           "$(ls -A "$U" | tr '\n' ' ')" "default.target.wants tmux.service "
rm -f "$T/systemctl.log"
HOME="$H" RZ_SYSTEMCTL="$T/bin/systemctl" bash "$ENABLE" >/dev/null
check "the dangling old unit link is removed"                    "$( [ -L "$U/tmux.service" ] && echo kept || echo removed)" "removed"
check "the dangling old enable link is removed"                  "$( [ -L "$U/default.target.wants/tmux.service" ] && echo kept || echo removed)" "removed"
check "it reloads and enables tmux-resurrect.service, and starts or stops nothing" "$(tr '\n' '|' < "$T/systemctl.log")" "--user show-environment|--user daemon-reload|--user enable tmux-resurrect.service|"
touch "$T/live.service"; ln -s "$T/live.service" "$U/tmux.service"
HOME="$H" RZ_SYSTEMCTL="$T/bin/systemctl" bash "$ENABLE" >/dev/null
check "a tmux.service link that still resolves is kept"          "$( [ -L "$U/tmux.service" ] && echo kept || echo removed)" "kept"

echo "# ---"
echo "# passed $P, failed $F"
[ "$F" -eq 0 ]
