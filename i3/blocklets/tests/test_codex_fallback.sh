#!/usr/bin/env bash
DIR=$(dirname "$0"); . "$DIR/assert.sh"; S="$DIR/../ai_usage"
TMP=$(mktemp -d)
# no cache, no network, but a rollout file is available -> gray render from rollout
out=$(AIUSAGE_CACHE_DIR="$TMP" AIUSAGE_NO_FETCH=1 \
      AIUSAGE_ROLLOUT_FILE="$DIR/fixtures/codex_rollout_line.jsonl" \
      BLOCK_INSTANCE=codex bash "$S")
assert_contains "codex rollout fallback text" "5h 15%" "$(sed -n 1p <<<"$out")"
assert_eq       "codex rollout fallback gray" "#888888" "$(sed -n 3p <<<"$out")"
rm -rf "$TMP"
finish
