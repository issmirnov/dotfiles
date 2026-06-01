#!/usr/bin/env bash
DIR=$(dirname "$0"); . "$DIR/assert.sh"; S="$DIR/../ai_usage"
# pace_sym <used> <remaining_seconds> <window_seconds>; window=604800 (7d), tol=5
# ahead: 64% used, ~3.2d remaining -> even pace ~54% -> +10 -> warning
assert_eq "pace ahead"      "⚠️10" "$(bash "$S" __pace 64 277200 604800)"
# behind: 20% used, 1d remaining -> even pace ~85% -> -65 -> sloth
assert_eq "pace behind"     "🦥65" "$(bash "$S" __pace 20 86400 604800)"
# on pace: 50% used exactly halfway through
assert_eq "pace on-pace"    "✅"   "$(bash "$S" __pace 50 302400 604800)"
# within tolerance (delta=3 <= tol=5) -> on pace
assert_eq "pace within tol" "✅"   "$(bash "$S" __pace 53 302400 604800)"
# just over tolerance (delta=6 > 5) -> warning
assert_eq "pace just over"  "⚠️6"  "$(bash "$S" __pace 56 302400 604800)"
# no remaining-time known -> no pace token (empty)
assert_eq "pace no rem"     ""     "$(bash "$S" __pace 50 '' 604800)"
# reset already passed (rem clamped to 0) -> even pace is 100%, 60% reads as behind 40
assert_eq "pace past reset" "🦥40" "$(bash "$S" __pace 60 -100 604800)"
finish
