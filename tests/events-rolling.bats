#!/usr/bin/env bats

# events-rolling.bats — Tests for events-grep.sh and events-migrate.sh (M4.5)

setup() {
  TEST_DIR=$(mktemp -d)
  export OPC_IR_HOME="$TEST_DIR"
  mkdir -p "$TEST_DIR/events" "$TEST_DIR/logs"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "events-migrate splits monolithic events.jsonl into monthly files" {
  # Create a monolithic events.jsonl with events from 2 months
  cat > "$TEST_DIR/events/events.jsonl" << 'EOF'
{"id":"e1","published_at":"2026-04-15T10:00:00Z","title":"April event"}
{"id":"e2","published_at":"2026-05-01T08:00:00Z","title":"May event"}
{"id":"e3","published_at":"2026-04-20T12:00:00Z","title":"Another April event"}
EOF

  result=$(bin/events-migrate.sh --home "$TEST_DIR")
  [ "$result" -eq 3 ]

  # Monthly files should exist
  [ -f "$TEST_DIR/events/2026-04-events.jsonl" ]
  [ -f "$TEST_DIR/events/2026-05-events.jsonl" ]

  # April should have 2 events
  april_count=$(wc -l < "$TEST_DIR/events/2026-04-events.jsonl" | tr -d ' ')
  [ "$april_count" -eq 2 ]

  # events.jsonl should now be a symlink
  [ -L "$TEST_DIR/events/events.jsonl" ]

  # Backup should exist
  [ -f "$TEST_DIR/events/events.jsonl.bak" ]
}

@test "events-migrate is idempotent (skips if already symlink)" {
  # Create symlink
  touch "$TEST_DIR/events/2026-05-events.jsonl"
  ln -sf "2026-05-events.jsonl" "$TEST_DIR/events/events.jsonl"

  result=$(bin/events-migrate.sh --home "$TEST_DIR")
  [ "$result" -eq 0 ]
}

@test "events-grep returns events from plain events.jsonl (fallback)" {
  echo '{"id":"e1","published_at":"2026-05-01T10:00:00Z","title":"Test"}' > "$TEST_DIR/events/events.jsonl"

  count=$(bin/events-grep.sh --home "$TEST_DIR" | wc -l | tr -d ' ')
  [ "$count" -eq 1 ]
}

@test "events-grep filters by --after date" {
  cat > "$TEST_DIR/events/events.jsonl" << 'EOF'
{"id":"e1","published_at":"2026-04-01T10:00:00Z","title":"Old"}
{"id":"e2","published_at":"2026-05-01T10:00:00Z","title":"New"}
EOF

  count=$(bin/events-grep.sh --home "$TEST_DIR" --after "2026-04-15" | wc -l | tr -d ' ')
  [ "$count" -eq 1 ]
}

@test "events-grep filters by --before date" {
  cat > "$TEST_DIR/events/events.jsonl" << 'EOF'
{"id":"e1","published_at":"2026-04-01T10:00:00Z","title":"Old"}
{"id":"e2","published_at":"2026-05-01T10:00:00Z","title":"New"}
EOF

  count=$(bin/events-grep.sh --home "$TEST_DIR" --before "2026-04-15" | wc -l | tr -d ' ')
  [ "$count" -eq 1 ]
}

@test "events-grep spans monthly files after migration" {
  # Create monthly files directly
  echo '{"id":"e1","published_at":"2026-04-15T10:00:00Z","title":"April"}' > "$TEST_DIR/events/2026-04-events.jsonl"
  echo '{"id":"e2","published_at":"2026-05-01T10:00:00Z","title":"May"}' > "$TEST_DIR/events/2026-05-events.jsonl"
  ln -sf "2026-05-events.jsonl" "$TEST_DIR/events/events.jsonl"

  count=$(bin/events-grep.sh --home "$TEST_DIR" --after "2026-04-01" --before "2026-05-31" | wc -l | tr -d ' ')
  [ "$count" -eq 2 ]
}

@test "events-grep returns empty for no matching files" {
  count=$(bin/events-grep.sh --home "$TEST_DIR" --after "2099-01-01" | wc -l | tr -d ' ')
  [ "$count" -eq 0 ]
}
