#!/usr/bin/env bash
DIR=$(dirname "$0"); . "$DIR/assert.sh"; S="$DIR/../ai_usage"
out=$(BLOCK_INSTANCE=claude bash "$S" __render < "$DIR/fixtures/claude_usage.json")
full=$(sed -n 1p <<<"$out"); short=$(sed -n 2p <<<"$out"); color=$(sed -n 3p <<<"$out")
assert_contains     "claude 5h pct shown"          "5h 38%"   "$full"
assert_not_contains "claude 5h has no reset (<50)"  "38% ("    "$full"
assert_contains     "claude 7d pace shown (far-future fixture clamps to ahead)" "7d 60% ⚠️60" "$full"
assert_contains     "claude 7d reset paren follows pace"                        "⚠️60 ("      "$full"
assert_contains "claude 7d pct"            "7d 60%"          "$full"
assert_eq       "claude short"             "CC 38/60"        "$short"
assert_eq       "claude color worst=60"    "#00C853"         "$color"
# high utilization, no resets_at present -> red, no reset paren, no crash
hi=$(BLOCK_INSTANCE=claude bash "$S" __render < "$DIR/fixtures/claude_high.json")
assert_eq           "claude high full"     "CC 5h 95% 7d 20%" "$(sed -n 1p <<<"$hi")"
assert_not_contains "claude high no paren"  "95% ("           "$(sed -n 1p <<<"$hi")"
assert_eq           "claude high color red" "#FF1744"         "$(sed -n 3p <<<"$hi")"
finish
