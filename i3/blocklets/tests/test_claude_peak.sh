#!/usr/bin/env bash
DIR=$(dirname "$0"); . "$DIR/assert.sh"; S="$DIR/../claude_peak"

# Run the blocklet at a fixed UTC instant -> deterministic regardless of host TZ.
peak_at() { CLAUDE_PEAK_NOW=$(date -u -d "$1" +%s) bash "$S"; }
nth() { sed -n "${1}p" <<<"$2"; }   # line N of an output: 1 full, 2 short, 3 color

# PDT (UTC-7): peak is 12:00-18:00 UTC on Thu 2026-10-29.
out=$(peak_at '2026-10-29 17:11:00')                                  # 10:11 PDT
assert_eq "pdt peak full"  "⚡ peak 49m" "$(nth 1 "$out")"
assert_eq "pdt peak short" "peak 49m"    "$(nth 2 "$out")"
assert_eq "pdt peak color" "#f0c489"     "$(nth 3 "$out")"
assert_eq "pdt start is inclusive" "⚡ peak 6h0m" "$(nth 1 "$(peak_at '2026-10-29 12:00:00')")"
assert_eq "pdt last seconds"       "⚡ peak <1m"  "$(nth 1 "$(peak_at '2026-10-29 17:59:30')")"
assert_eq "pdt end is exclusive"   ""             "$(nth 1 "$(peak_at '2026-10-29 18:00:00')")"
# 11:11 PDT: ccflare's fixed 13:00-19:00 UTC flag still says peak here.
assert_eq "pdt 11:11 is off-peak"  ""             "$(nth 1 "$(peak_at '2026-10-29 18:11:00')")"

out=$(peak_at '2026-10-29 11:15:00')                                  # 04:15 PDT
assert_eq "pdt heads-up full"     "peak in 45m" "$(nth 1 "$out")"
assert_eq "pdt heads-up short"    "peak in 45m" "$(nth 2 "$out")"
assert_eq "pdt heads-up no color" ""            "$(nth 3 "$out")"
assert_eq "pdt heads-up opens at 1h" "peak in 1h0m" "$(nth 1 "$(peak_at '2026-10-29 11:00:00')")"
assert_eq "pdt before the heads-up"  ""             "$(nth 1 "$(peak_at '2026-10-29 10:59:00')")"

# PST (UTC-8): peak is 13:00-19:00 UTC on Thu 2026-01-15.
assert_eq "pst start"    "⚡ peak 6h0m" "$(nth 1 "$(peak_at '2026-01-15 13:00:00')")"
assert_eq "pst heads-up" "peak in 30m"  "$(nth 1 "$(peak_at '2026-01-15 12:30:00')")"
assert_eq "pst end"      ""             "$(nth 1 "$(peak_at '2026-01-15 19:00:00')")"

# Weekends: never. DST ends 2026-11-01 at 09:00 UTC.
assert_eq "saturday" "" "$(nth 1 "$(peak_at '2026-10-31 16:00:00')")"   # 09:00 PDT
assert_eq "sunday"   "" "$(nth 1 "$(peak_at '2026-11-01 16:00:00')")"   # 08:00 PST

# The first weekday after the DST change.
assert_eq "monday heads-up" "peak in 45m" "$(nth 1 "$(peak_at '2026-11-02 12:15:00')")"   # 04:15 PST
assert_eq "monday peak"     "⚡ peak 6h0m" "$(nth 1 "$(peak_at '2026-11-02 13:00:00')")"  # 05:00 PST

# The host TZ must not leak in. 17:11 UTC is already Friday 02:11 in Tokyo.
t=$(date -u -d '2026-10-29 17:11:00' +%s)
assert_eq "host TZ does not leak" "$(CLAUDE_PEAK_NOW=$t bash "$S")" "$(TZ=Asia/Tokyo CLAUDE_PEAK_NOW=$t bash "$S")"

# Without the seam it reads the clock and still exits 0.
bash "$S" >/dev/null; assert_eq "live run exits 0" "0" "$?"
finish
