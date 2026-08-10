#!/usr/bin/env bash

if [[ "$(uname -s)" == "Darwin" ]]; then
  echo "SKIP: i3 blocklet tests are Linux-only"
  exit 0
fi

cd "$(dirname "$0")" || exit 1
rc=0
for t in test_*.sh; do
  [ -e "$t" ] || continue
  echo "== $t =="
  bash "$t" || rc=1
done
exit $rc
