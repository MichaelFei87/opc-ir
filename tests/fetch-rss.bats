#!/usr/bin/env bats

# fetch-rss.bats — RSS fetch and dedup tests (M3.1) — uses real RSS feeds

setup() {
  export OPC_IR_HOME="$(mktemp -d)"
  mkdir -p "$OPC_IR_HOME/events" "$OPC_IR_HOME/logs"
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export PATH="$SCRIPT_DIR/bin:$PATH"
}

teardown() {
  rm -rf "$OPC_IR_HOME"
}

@test "fetch-rss: produces valid events from real RSS feed" {
  cat > "$OPC_IR_HOME/test-sources.yaml" << 'EOF'
sources:
  - id: bbc-business
    url: https://feeds.bbci.co.uk/news/business/rss.xml
    type: rss
    enabled: true
EOF

  run fetch-rss.sh --sources "$OPC_IR_HOME/test-sources.yaml" --home "$OPC_IR_HOME"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$OPC_IR_HOME/events/events.jsonl" | tr -d ' ')" -ge 1 ]
  while IFS= read -r line; do
    echo "$line" | jq -e '.id and .source and .title and .url' >/dev/null
  done < "$OPC_IR_HOME/events/events.jsonl"
}

@test "fetch-rss: dedup prevents duplicate events on re-fetch" {
  cat > "$OPC_IR_HOME/test-sources.yaml" << 'EOF'
sources:
  - id: bbc-business
    url: https://feeds.bbci.co.uk/news/business/rss.xml
    type: rss
    enabled: true
EOF

  fetch-rss.sh --sources "$OPC_IR_HOME/test-sources.yaml" --home "$OPC_IR_HOME" >/dev/null
  local count_first
  count_first=$(wc -l < "$OPC_IR_HOME/events/events.jsonl" | tr -d ' ')
  [ "$count_first" -gt 0 ]

  # Second fetch — same source, should add 0 new events
  result=$(fetch-rss.sh --sources "$OPC_IR_HOME/test-sources.yaml" --home "$OPC_IR_HOME")
  [ "$result" -eq 0 ]
}

@test "fetch-rss: disabled source is skipped" {
  cat > "$OPC_IR_HOME/test-sources.yaml" << 'EOF'
sources:
  - id: disabled-feed
    url: https://feeds.bbci.co.uk/news/business/rss.xml
    type: rss
    enabled: false
EOF

  run fetch-rss.sh --sources "$OPC_IR_HOME/test-sources.yaml" --home "$OPC_IR_HOME"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$OPC_IR_HOME/events/events.jsonl" | tr -d ' ')" -eq 0 ]
}

@test "fetch-rss: multiple real sources processed independently" {
  cat > "$OPC_IR_HOME/test-sources.yaml" << 'EOF'
sources:
  - id: bbc-biz
    url: https://feeds.bbci.co.uk/news/business/rss.xml
    type: rss
    enabled: true
  - id: ap-biz
    url: https://feeds.apnews.com/rss/business
    type: rss
    enabled: true
EOF

  run fetch-rss.sh --sources "$OPC_IR_HOME/test-sources.yaml" --home "$OPC_IR_HOME"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$OPC_IR_HOME/events/events.jsonl" | tr -d ' ')" -ge 2 ]
}

@test "fetch-rss: event IDs are globally unique" {
  cat > "$OPC_IR_HOME/test-sources.yaml" << 'EOF'
sources:
  - id: bbc-biz
    url: https://feeds.bbci.co.uk/news/business/rss.xml
    type: rss
    enabled: true
  - id: ap-biz
    url: https://feeds.apnews.com/rss/business
    type: rss
    enabled: true
EOF

  run fetch-rss.sh --sources "$OPC_IR_HOME/test-sources.yaml" --home "$OPC_IR_HOME"
  [ "$status" -eq 0 ]
  local total unique
  total=$(wc -l < "$OPC_IR_HOME/events/events.jsonl" | tr -d ' ')
  unique=$(jq -r '.id' "$OPC_IR_HOME/events/events.jsonl" | sort -u | wc -l | tr -d ' ')
  [ "$total" -eq "$unique" ]
}

@test "fetch-rss: empty sources list returns 0" {
  cat > "$OPC_IR_HOME/test-sources.yaml" << 'EOF'
sources: []
EOF

  run fetch-rss.sh --sources "$OPC_IR_HOME/test-sources.yaml" --home "$OPC_IR_HOME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0"* ]]
}
