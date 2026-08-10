#!/usr/bin/env bash
DIR=$(dirname "$0"); . "$DIR/assert.sh"; S="$DIR/../ai_usage"

# --- short account tags (mapping for known accounts, derived fallback) ---
assert_eq "tag smirnovlabs" "sl" "$(bash "$S" __tag claude-smirnovlabs)"
assert_eq "tag isgmirnov"   "ig" "$(bash "$S" __tag claude_isgmirnov)"
assert_eq "tag derived"     "fo" "$(bash "$S" __tag claude-foobar)"

# --- fleet render: worst account first, both windows per account, pace + reset ---
out=$(BLOCK_INSTANCE=claude bash "$S" __render < "$DIR/fixtures/claude_ccflare.json")
full=$(sed -n 1p <<<"$out"); short=$(sed -n 2p <<<"$out"); color=$(sed -n 3p <<<"$out")
assert_contains "worst account (sl) first, 5h/7d shown" "CC sl 0/100"     "$full"
assert_contains "sl weekly pace shown"                  "sl 0/100 ⚠️100"  "$full"
assert_contains "sl reset paren follows pace"           "⚠️100 ("         "$full"
assert_contains "ig second account 5h/7d + pace"        "ig 15/49 ⚠️49"   "$full"
assert_not_contains "ig <50 has no reset paren"         "49 ("            "$full"
assert_not_contains "codex account excluded"            "lena"            "$full"
assert_eq       "short = worst pct"                     "CC 100%"         "$short"
assert_eq       "color worst=100 red"                   "#FF1744"         "$color"

# --- per-account instance (claude:<name>): each account renders + colors solo ---
sl=$(BLOCK_INSTANCE=claude:claude-smirnovlabs bash "$S" __render < "$DIR/fixtures/claude_ccflare.json")
assert_contains     "sl-only shows sl"     "CC sl 0/100" "$(sed -n 1p <<<"$sl")"
assert_not_contains "sl-only excludes ig"  "ig"          "$(sed -n 1p <<<"$sl")"
assert_eq           "sl-only short"        "CC 100%"     "$(sed -n 2p <<<"$sl")"
assert_eq           "sl-only color red"    "#FF1744"     "$(sed -n 3p <<<"$sl")"

ig=$(BLOCK_INSTANCE=claude:claude_isgmirnov bash "$S" __render < "$DIR/fixtures/claude_ccflare.json")
assert_contains     "ig-only shows ig"     "CC ig 15/49" "$(sed -n 1p <<<"$ig")"
assert_not_contains "ig-only excludes sl"  "sl"          "$(sed -n 1p <<<"$ig")"
assert_eq           "ig-only short"        "CC 49%"      "$(sed -n 2p <<<"$ig")"
assert_eq           "ig stays GREEN while sl is maxed" "#00C853" "$(sed -n 3p <<<"$ig")"

# --- high utilization, no resets_at present -> red, no paren, no crash ---
hi=$(BLOCK_INSTANCE=claude bash "$S" __render < "$DIR/fixtures/claude_ccflare_noresets.json")
assert_eq           "high full"      "CC sl 95/20" "$(sed -n 1p <<<"$hi")"
assert_not_contains "high no paren"  "95 ("        "$(sed -n 1p <<<"$hi")"
assert_eq           "high color red" "#FF1744"     "$(sed -n 3p <<<"$hi")"
finish
