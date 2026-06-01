#!/usr/bin/env bash
DIR=$(dirname "$0"); . "$DIR/assert.sh"; S="$DIR/../ai_usage"
out=$(BLOCK_INSTANCE=claude bash "$S" __render < "$DIR/fixtures/claude_usage.json")
full=$(sed -n 1p <<<"$out"); short=$(sed -n 2p <<<"$out"); color=$(sed -n 3p <<<"$out")
assert_contains "claude 5h no reset (<50)" "5h 38% 7d 60% (" "$full"
assert_contains "claude 7d pct"            "7d 60%"          "$full"
assert_eq       "claude short"             "CC 38/60"        "$short"
assert_eq       "claude color worst=60"    "#00C853"         "$color"
finish
