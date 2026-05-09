#!/usr/bin/env bats

# forked-meta.bats — Validate OPC-forked files carry lineage frontmatter (M1.2)

FORKED_FILES=(
  "pipeline/gate-protocol.md"
)

@test "forked files have forked-from frontmatter" {
  for f in "${FORKED_FILES[@]}"; do
    [ -f "$f" ] || { echo "Missing: $f"; return 1; }
    grep -q 'forked-from:' "$f" || { echo "FAIL: $f missing forked-from"; return 1; }
  done
}

@test "forked files have forked-at: 2026-05-08" {
  for f in "${FORKED_FILES[@]}"; do
    grep -q 'forked-at:.*2026-05-08' "$f" || { echo "FAIL: $f missing forked-at date"; return 1; }
  done
}

@test "forked files have modifications: list" {
  for f in "${FORKED_FILES[@]}"; do
    grep -q 'modifications:' "$f" || { echo "FAIL: $f missing modifications list"; return 1; }
  done
}

@test "native pipeline files do NOT have forked-from" {
  NATIVE_FILES=(
    "pipeline/forecast-protocol.md"
    "pipeline/vote-protocol.md"
    "pipeline/verdict-protocol.md"
    "pipeline/invalidator-lint.md"
  )
  for f in "${NATIVE_FILES[@]}"; do
    if [ -f "$f" ]; then
      ! grep -q 'forked-from:' "$f" || { echo "FAIL: native file $f should not have forked-from"; return 1; }
    fi
  done
}
