#!/bin/bash
# Concurrent callers of acquire_lock: exactly one proceeds, lockdir is removed on exit.
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
LIB="$(cd "$(dirname "$0")/.." && pwd)/lock.sh"
for i in 1 2 3 4 5; do
  ( source "$LIB"; acquire_lock "$T/lock"; echo got >> "$T/out"; sleep 1 ) &
done
wait
n=$(wc -l < "$T/out" 2>/dev/null | tr -d ' ')
[ "$n" = 1 ] || { echo "FAIL: $n callers got the lock"; exit 1; }
[ ! -e "$T/lock" ] || { echo "FAIL: lockdir left behind"; exit 1; }
echo PASS
