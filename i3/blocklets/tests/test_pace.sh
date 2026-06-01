#!/usr/bin/env bash
DIR=$(dirname "$0"); . "$DIR/assert.sh"; S="$DIR/../ai_usage"
# claude_pace <used> <reset_epoch> <now> <week_seconds>; week=604800 (7d)
# ahead: 64% used, but half-week+ remaining puts even pace at ~54% -> +10
assert_eq "pace ahead"     "↑10" "$(bash "$S" __pace 64 277200 0 604800)"
# behind: 20% used with only 1 day left, even pace would be ~85% -> -65
assert_eq "pace behind"    "↓65" "$(bash "$S" __pace 20 86400 0 604800)"
# on pace: 50% used exactly halfway through the window
assert_eq "pace on-pace"   "="   "$(bash "$S" __pace 50 302400 0 604800)"
# boundary: 1 point over even pace still reads as ahead
assert_eq "pace just ahead" "↑1" "$(bash "$S" __pace 51 302400 0 604800)"
# no reset time -> no pace token (empty output)
assert_eq "pace no reset"  ""    "$(bash "$S" __pace 50 '' 0 604800)"
# reset already passed (rem clamped to 0) -> even pace is 100%, so 60% reads as behind 40
assert_eq "pace past reset" "↓40" "$(bash "$S" __pace 60 -100 0 604800)"
finish
