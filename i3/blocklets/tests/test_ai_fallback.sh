#!/usr/bin/env bash
DIR=$(dirname "$0"); . "$DIR/assert.sh"; S="$DIR/../ai_usage"
TMP=$(mktemp -d); cp "$DIR/fixtures/claude_ccflare_low.json" "$TMP/claude.json"

# fresh cache -> live color (green), real text
out=$(AIUSAGE_CACHE_DIR="$TMP" BLOCK_INSTANCE=claude bash "$S")
assert_eq       "fresh cache live color" "#00C853"     "$(sed -n 3p <<<"$out")"
assert_contains "fresh cache text"       "CC sl 10/30" "$(sed -n 1p <<<"$out")"

# stale cache + no fetch -> dim (gray) but text preserved
touch -d '1 hour ago' "$TMP/claude.json"
out=$(AIUSAGE_CACHE_DIR="$TMP" AIUSAGE_NO_FETCH=1 BLOCK_INSTANCE=claude bash "$S")
assert_eq       "stale dim color"  "#888888"     "$(sed -n 3p <<<"$out")"
assert_contains "stale text kept"  "CC sl 10/30" "$(sed -n 1p <<<"$out")"

# no cache + no fetch -> "CC ?"
TMP2=$(mktemp -d)
out=$(AIUSAGE_CACHE_DIR="$TMP2" AIUSAGE_NO_FETCH=1 BLOCK_INSTANCE=claude bash "$S")
assert_eq "no-data full"  "CC ?"    "$(sed -n 1p <<<"$out")"
assert_eq "no-data color" "#888888" "$(sed -n 3p <<<"$out")"

rm -rf "$TMP" "$TMP2"
finish
