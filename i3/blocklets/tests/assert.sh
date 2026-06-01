#!/usr/bin/env bash
# Minimal dependency-free assertion helpers. Source this from test_*.sh.
pass=0; fail=0
assert_eq() { # $1 desc  $2 expected  $3 actual
  if [ "$2" = "$3" ]; then pass=$((pass+1));
  else fail=$((fail+1)); printf 'FAIL - %s\n  expected: %q\n  actual:   %q\n' "$1" "$2" "$3"; fi
}
assert_contains() { # $1 desc  $2 needle  $3 haystack
  case "$3" in
    *"$2"*) pass=$((pass+1));;
    *) fail=$((fail+1)); printf 'FAIL - %s\n  needle: %q\n  in:     %q\n' "$1" "$2" "$3";;
  esac
}
assert_not_contains() { # $1 desc  $2 needle  $3 haystack
  case "$3" in
    *"$2"*) fail=$((fail+1)); printf 'FAIL - %s\n  unexpected: %q\n  in: %q\n' "$1" "$2" "$3";;
    *) pass=$((pass+1));;
  esac
}
finish() { printf '%d passed, %d failed\n' "$pass" "$fail"; [ "$fail" -eq 0 ]; }
