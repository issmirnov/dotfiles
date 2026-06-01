#!/usr/bin/env bash
DIR=$(dirname "$0"); . "$DIR/assert.sh"; S="$DIR/../ai_usage"

# normal: 10% / 8% -> green; wk is on pace (~7% expected) -> ✅; no resets (<50)
out=$(BLOCK_INSTANCE=codex bash "$S" __render < "$DIR/fixtures/codex_wham.json")
assert_eq "codex full"  "CX 5h 10% wk 8% ✅" "$(sed -n 1p <<<"$out")"
assert_eq "codex short" "CX 10/8"         "$(sed -n 2p <<<"$out")"
assert_eq "codex color" "#00C853"         "$(sed -n 3p <<<"$out")"

# high: 92% with 2h reset -> red, reset shown (reset_after_seconds is deterministic)
out=$(BLOCK_INSTANCE=codex bash "$S" __render < "$DIR/fixtures/codex_high.json")
assert_eq "codex high full"  "CX 5h 92% (2h0m) wk 8% ✅" "$(sed -n 1p <<<"$out")"
assert_eq "codex high color" "#FF1744"                "$(sed -n 3p <<<"$out")"
finish
