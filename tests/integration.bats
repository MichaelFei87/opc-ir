#!/usr/bin/env bats

# integration.bats — End-to-end tests: defaults → fetch → triage-ready events

setup() {
  TEST_DIR=$(mktemp -d)
  export OPC_IR_HOME="$TEST_DIR"
  mkdir -p "$TEST_DIR"/{config,events,logs,world,triggers}
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── defaults/sources.yaml compatibility ──

@test "defaults/sources.yaml is valid YAML with sources array" {
  command -v yq >/dev/null 2>&1 || skip "yq not installed"
  count=$(yq e '.sources | length' defaults/sources.yaml)
  [ "$count" -gt 0 ]
}

@test "defaults/sources.yaml: every source has id and url" {
  command -v yq >/dev/null 2>&1 || skip "yq not installed"
  count=$(yq e '.sources | length' defaults/sources.yaml)
  for ((i=0; i<count; i++)); do
    id=$(yq e ".sources[$i].id" defaults/sources.yaml)
    url=$(yq e ".sources[$i].url" defaults/sources.yaml)
    [ "$id" != "null" ] || { echo "source $i missing id"; return 1; }
    [ "$url" != "null" ] || { echo "source $i missing url"; return 1; }
    [[ "$url" == http* ]] || { echo "source $i url not http: $url"; return 1; }
  done
}

@test "fetch-rss: defaults/sources.yaml field names work with fetch-rss.sh" {
  # Use a real feed with 'id' field to match defaults/sources.yaml naming
  cat > "$TEST_DIR/id-sources.yaml" << 'EOF'
sources:
  - id: test-bbc
    url: https://feeds.bbci.co.uk/news/business/rss.xml
    type: rss
EOF

  result=$(bin/fetch-rss.sh --sources "$TEST_DIR/id-sources.yaml" --home "$TEST_DIR")
  [ "$result" -gt 0 ]
  # Verify source names match the 'id' field
  sources=$(jq -r '.source' "$TEST_DIR/events/events.jsonl" | sort -u)
  [[ "$sources" == *"test-bbc"* ]]
}

@test "fetch-rss: fetches >1 event from real RSS sources" {
  cat > "$TEST_DIR/multi-sources.yaml" << 'EOF'
sources:
  - id: bbc-biz
    url: https://feeds.bbci.co.uk/news/business/rss.xml
    type: rss
  - id: ap-biz
    url: https://feeds.apnews.com/rss/business
    type: rss
EOF

  result=$(bin/fetch-rss.sh --sources "$TEST_DIR/multi-sources.yaml" --home "$TEST_DIR")
  [ "$result" -gt 1 ]
  event_count=$(wc -l < "$TEST_DIR/events/events.jsonl" | tr -d ' ')
  [ "$event_count" -gt 1 ]
}

# ── Fetched events are triage-ready ──

@test "fetched events have all fields required by triage-classifier" {
  cat > "$TEST_DIR/test-sources.yaml" << 'EOF'
sources:
  - id: bbc-test
    url: https://feeds.bbci.co.uk/news/business/rss.xml
    type: rss
EOF

  bin/fetch-rss.sh --sources "$TEST_DIR/test-sources.yaml" --home "$TEST_DIR" >/dev/null
  [ -f "$TEST_DIR/events/events.jsonl" ]

  # triage-classifier requires: id, source, published_at, title, summary
  while IFS= read -r line; do
    for key in id source published_at title summary; do
      jq -e "has(\"$key\")" <<< "$line" >/dev/null || {
        echo "Missing field: $key in event: $(echo "$line" | jq -r .id)"
        return 1
      }
    done
    title=$(jq -r '.title' <<< "$line")
    [ -n "$title" ] && [ "$title" != "null" ]
  done < "$TEST_DIR/events/events.jsonl"
}

@test "fetched events have valid ISO timestamps" {
  cat > "$TEST_DIR/test-sources.yaml" << 'EOF'
sources:
  - id: bbc-test
    url: https://feeds.bbci.co.uk/news/business/rss.xml
    type: rss
EOF

  bin/fetch-rss.sh --sources "$TEST_DIR/test-sources.yaml" --home "$TEST_DIR" >/dev/null

  while IFS= read -r line; do
    pub=$(jq -r '.published_at' <<< "$line")
    fetched=$(jq -r '.fetched_at' <<< "$line")
    [[ "$pub" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]] || { echo "Bad published_at: $pub"; return 1; }
    [[ "$fetched" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]] || { echo "Bad fetched_at: $fetched"; return 1; }
  done < "$TEST_DIR/events/events.jsonl"
}

@test "inject-event produces triage-ready event" {
  bin/inject-event.sh "NVIDIA beats Q2 earnings, raises guidance on AI demand" \
    --summary "Revenue up 120% YoY driven by data center GPU sales" \
    --home "$TEST_DIR" >/dev/null

  [ -f "$TEST_DIR/events/events.jsonl" ] || \
    [ -f "$TEST_DIR/events/$(date -u +%Y-%m)-events.jsonl" ]

  EVENTS_FILE="$TEST_DIR/events/events.jsonl"
  [ -f "$EVENTS_FILE" ] || EVENTS_FILE="$TEST_DIR/events/$(date -u +%Y-%m)-events.jsonl"

  event_count=$(wc -l < "$EVENTS_FILE" | tr -d ' ')
  [ "$event_count" -ge 1 ]

  last_event=$(tail -1 "$EVENTS_FILE")
  jq -e '.id and .title and .summary' <<< "$last_event" >/dev/null
  title=$(jq -r '.title' <<< "$last_event")
  [[ "$title" == *"NVIDIA"* ]]
}

@test "triage dimensions cover all 7 required watchers" {
  DIMENSIONS="politics econ-finance military tech-ai humanities energy-commodity corp-fundamentals"
  for dim in $DIMENSIONS; do
    jq -e ".properties.dimension_scores.properties[\"$dim\"]" \
      tests/schemas/triage.schema.json >/dev/null || {
      echo "Triage schema missing dimension: $dim"
      return 1
    }
  done

  for dim in $DIMENSIONS; do
    watcher="roles/_watchers/${dim}-watcher.md"
    [ -f "$watcher" ] || { echo "Missing watcher role: $watcher"; return 1; }
  done
}

@test "hard rules in triage-thresholds.yaml align with classifier agent" {
  command -v yq >/dev/null 2>&1 || skip "yq not installed"
  route_thresh=$(yq e '.watcher_route_threshold' defaults/triage-thresholds.yaml)
  hard_thresh=$(yq e '.hard_rule_verdict_threshold' defaults/triage-thresholds.yaml)
  [ "$route_thresh" = "0.6" ]
  [ "$hard_thresh" = "0.85" ]

  rule_count=$(yq e '.hard_rules | length' defaults/triage-thresholds.yaml)
  [ "$rule_count" -ge 1 ]

  grep -q '0.6' agents/triage-classifier.md
  grep -q 'hard_rule_hit' agents/triage-classifier.md
}

# ── Dedup ──

@test "fetch-rss: full-file dedup prevents re-adding old events" {
  cat > "$TEST_DIR/test-sources.yaml" << 'EOF'
sources:
  - id: bbc-test
    url: https://feeds.bbci.co.uk/news/business/rss.xml
    type: rss
EOF

  bin/fetch-rss.sh --sources "$TEST_DIR/test-sources.yaml" --home "$TEST_DIR" >/dev/null
  count_after_first=$(wc -l < "$TEST_DIR/events/events.jsonl" | tr -d ' ')
  [ "$count_after_first" -gt 0 ]

  # Second fetch — same source, should add 0 new events
  result=$(bin/fetch-rss.sh --sources "$TEST_DIR/test-sources.yaml" --home "$TEST_DIR")
  [ "$result" -eq 0 ]
  count_after_second=$(wc -l < "$TEST_DIR/events/events.jsonl" | tr -d ' ')
  [ "$count_after_first" -eq "$count_after_second" ]
}

@test "fetch-rss: no duplicate IDs after multiple fetches from different sources" {
  cat > "$TEST_DIR/test-sources.yaml" << 'EOF'
sources:
  - id: bbc-test
    url: https://feeds.bbci.co.uk/news/business/rss.xml
    type: rss
  - id: ap-test
    url: https://feeds.apnews.com/rss/business
    type: rss
EOF

  bin/fetch-rss.sh --sources "$TEST_DIR/test-sources.yaml" --home "$TEST_DIR" >/dev/null
  bin/fetch-rss.sh --sources "$TEST_DIR/test-sources.yaml" --home "$TEST_DIR" >/dev/null

  total=$(wc -l < "$TEST_DIR/events/events.jsonl" | tr -d ' ')
  unique=$(jq -r '.id' "$TEST_DIR/events/events.jsonl" | sort -u | wc -l | tr -d ' ')
  [ "$total" -eq "$unique" ]
}
