#!/usr/bin/env zsh
# run-all.zsh — Run every tests/test-*.zsh in this directory.
#
# Usage: zsh tests/run-all.zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"

failed=()
for t in "$SCRIPT_DIR"/test-*.zsh; do
  [[ -f "$t" ]] || continue
  print "── ${t:t} ───────────────────────────────"
  if zsh "$t"; then
    print
  else
    failed+=("${t:t}")
    print "FAILED: ${t:t}"
    print
  fi
done

if (( ${#failed[@]} > 0 )); then
  print -u2 "Failures (${#failed[@]}): ${failed[*]}"
  exit 1
fi
print "All tests passed."
