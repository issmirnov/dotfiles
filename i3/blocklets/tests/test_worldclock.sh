#!/usr/bin/env bash
DIR=$(dirname "$0"); . "$DIR/assert.sh"; S="$DIR/../worldclock"

# Fixed UTC instants -> deterministic regardless of host TZ.
# Summer: 2026-07-01 12:00 UTC -> London +1 (13:00), Zagreb/Prague/Amsterdam +2 (14:00),
# Kyiv +3 (15:00)
summer=$(date -u -d '2026-07-01 12:00:00' +%s)
out=$(WORLDCLOCK_NOW=$summer bash "$S" __render)
assert_eq "summer full"  "LON 13:00  ZAG·PRG·AMS 14:00  KYV 15:00" "$(sed -n 1p <<<"$out")"
assert_eq "summer short" "13:00 14:00 15:00"                       "$(sed -n 2p <<<"$out")"

# Winter: 2026-01-15 12:00 UTC -> London +0 (12:00), Zagreb/Prague/Amsterdam +1 (13:00),
# Kyiv +2 (14:00). Same UTC instant, different display => DST-aware; the CET cities stay
# collapsed, LON stays -1h and KYV +1h.
winter=$(date -u -d '2026-01-15 12:00:00' +%s)
wout=$(WORLDCLOCK_NOW=$winter bash "$S" __render)
assert_eq "winter full"  "LON 12:00  ZAG·PRG·AMS 13:00  KYV 14:00" "$(sed -n 1p <<<"$wout")"
assert_eq "winter short" "12:00 13:00 14:00"                       "$(sed -n 2p <<<"$wout")"

# Collapse invariant: the three CET cities share one group, exactly three time tokens.
assert_contains "summer collapses ZAG·PRG·AMS" "ZAG·PRG·AMS" "$(sed -n 1p <<<"$out")"
ntok=$(sed -n 2p <<<"$out" | tr ' ' '\n' | grep -c ':')
assert_eq "summer has three time tokens" "3" "$ntok"
finish
