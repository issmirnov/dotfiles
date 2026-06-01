#!/usr/bin/env bash
DIR=$(dirname "$0"); . "$DIR/assert.sh"; S="$DIR/../ai_usage"
assert_eq "color 38 green"  "#00C853" "$(bash "$S" __color 38)"
assert_eq "color 69 green"  "#00C853" "$(bash "$S" __color 69)"
assert_eq "color 70 yellow" "#FFD600" "$(bash "$S" __color 70)"
assert_eq "color 89 yellow" "#FFD600" "$(bash "$S" __color 89)"
assert_eq "color 90 red"    "#FF1744" "$(bash "$S" __color 90)"
assert_eq "reset minutes"   "7m"      "$(bash "$S" __reset 420)"
assert_eq "reset hours"     "4h2m"    "$(bash "$S" __reset 14520)"
assert_eq "reset days"      "3d4h"    "$(bash "$S" __reset 273600)"
finish
