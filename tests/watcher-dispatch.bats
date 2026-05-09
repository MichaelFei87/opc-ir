#!/usr/bin/env bats

# watcher-dispatch.bats — Validate watcher roles and concurrent dispatch (M2.2)

@test "7 watcher roles exist" {
  count=$(find roles/_watchers -name '*-watcher.md' 2>/dev/null | wc -l | tr -d ' ')
  [ "$count" -eq 7 ]
}

@test "watcher role names match spec" {
  for name in politics econ-finance military tech-ai humanities energy-commodity corp-fundamentals; do
    [ -f "roles/_watchers/${name}-watcher.md" ] || { echo "Missing: roles/_watchers/${name}-watcher.md"; return 1; }
  done
}

@test "each watcher has evolve tag" {
  for f in roles/_watchers/*-watcher.md; do
    grep -q 'evolve' "$f" || { echo "FAIL: $f missing evolve tag"; return 1; }
  done
}

@test "each watcher has delta output_format" {
  for f in roles/_watchers/*-watcher.md; do
    grep -q 'delta' "$f" || { echo "FAIL: $f missing delta output_format"; return 1; }
  done
}
