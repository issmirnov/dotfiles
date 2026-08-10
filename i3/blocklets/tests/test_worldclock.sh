#!/usr/bin/env bash
DIR=$(dirname "$0"); . "$DIR/assert.sh"; S="$DIR/../worldclock"

# Fixed UTC instants -> deterministic regardless of host TZ.
# Summer: 2026-07-01 12:00 UTC -> Zagreb/Prague +2 (14:00), Kyiv +3 (15:00)
summer=$(date -u -d '2026-07-01 12:00:00' +%s)
out=$(WORLDCLOCK_NOW=$summer bash "$S" __render)
assert_eq "summer full"  "ZAG·PRG 14:00  KYV 15:00" "$(sed -n 1p <<<"$out")"
assert_eq "summer short" "14:00 15:00"              "$(sed -n 2p <<<"$out")"

# Winter: 2026-01-15 12:00 UTC -> Zagreb/Prague +1 (13:00), Kyiv +2 (14:00).
# Same UTC instant, different display => DST-aware; ZAG·PRG stays collapsed, KYV +1h.
winter=$(date -u -d '2026-01-15 12:00:00' +%s)
wout=$(WORLDCLOCK_NOW=$winter bash "$S" __render)
assert_eq "winter full"  "ZAG·PRG 13:00  KYV 14:00" "$(sed -n 1p <<<"$wout")"
assert_eq "winter short" "13:00 14:00"              "$(sed -n 2p <<<"$wout")"

# Collapse invariant: ZAG·PRG share one group, exactly two time tokens.
assert_contains "summer collapses ZAG·PRG" "ZAG·PRG" "$(sed -n 1p <<<"$out")"
ntok=$(sed -n 2p <<<"$out" | tr ' ' '\n' | grep -c ':')
assert_eq "summer has two time tokens" "2" "$ntok"
finish
