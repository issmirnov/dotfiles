#!/usr/bin/env bash
cd "$(dirname "$0")" || exit 1
rc=0
for t in test_*.sh; do
  [ -e "$t" ] || continue
  echo "== $t =="
  bash "$t" || rc=1
done
exit $rc
