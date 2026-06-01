#!/usr/bin/env bash
DIR=$(dirname "$0"); . "$DIR/assert.sh"; S="$DIR/../ai_usage"
mapped=$(bash "$S" __maprollout < "$DIR/fixtures/codex_rollout_line.jsonl")
out=$(BLOCK_INSTANCE=codex bash "$S" __render <<<"$mapped")
assert_contains "rollout 5h" "5h 15%" "$(sed -n 1p <<<"$out")"
assert_contains "rollout wk" "wk 6%"  "$(sed -n 1p <<<"$out")"
finish
