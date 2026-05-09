#!/usr/bin/env bats

# helper-commands.bats — inject-event, dry-run, light mode tests (M3.4)

setup() {
  export OPC_IR_HOME="$(mktemp -d)"
  mkdir -p "$OPC_IR_HOME/events" "$OPC_IR_HOME/logs" "$OPC_IR_HOME/world" "$OPC_IR_HOME/triggers"
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export PATH="$SCRIPT_DIR/bin:$PATH"
}

teardown() {
  rm -rf "$OPC_IR_HOME"
}

@test "inject-event: creates valid event in events.jsonl" {
  run inject-event.sh "Fed raises rates by 50bps" --home "$OPC_IR_HOME"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$OPC_IR_HOME/events/events.jsonl" | tr -d ' ')" -eq 1 ]
  jq -e '.source == "manual"' "$OPC_IR_HOME/events/events.jsonl"
  jq -e '.title == "Fed raises rates by 50bps"' "$OPC_IR_HOME/events/events.jsonl"
}

@test "inject-event: requires title" {
  run inject-event.sh --home "$OPC_IR_HOME"
  [ "$status" -eq 1 ]
}

@test "inject-event: optional summary and url" {
  run inject-event.sh "Test event" \
    --summary "Detailed description of the event" \
    --url "https://example.com/article" \
    --home "$OPC_IR_HOME"
  [ "$status" -eq 0 ]
  jq -e '.summary == "Detailed description of the event"' "$OPC_IR_HOME/events/events.jsonl"
  jq -e '.url == "https://example.com/article"' "$OPC_IR_HOME/events/events.jsonl"
}

@test "inject-event: ID contains manual prefix" {
  inject-event.sh "Test" --home "$OPC_IR_HOME"
  jq -e '.id | startswith("manual-")' "$OPC_IR_HOME/events/events.jsonl"
}

@test "inject-event: successive injections produce unique IDs" {
  inject-event.sh "Event one" --home "$OPC_IR_HOME"
  inject-event.sh "Event two" --home "$OPC_IR_HOME"
  local total
  total=$(wc -l < "$OPC_IR_HOME/events/events.jsonl" | tr -d ' ')
  local unique
  unique=$(jq -r '.id' "$OPC_IR_HOME/events/events.jsonl" | sort -u | wc -l | tr -d ' ')
  [ "$total" -eq 2 ]
  [ "$unique" -eq 2 ]
}

@test "inject-event: does not modify world-model" {
  echo "prior content" > "$OPC_IR_HOME/world/world-model.md"
  local wm_before
  wm_before=$(cat "$OPC_IR_HOME/world/world-model.md")

  inject-event.sh "Fed surprise rate cut" --home "$OPC_IR_HOME"

  local wm_after
  wm_after=$(cat "$OPC_IR_HOME/world/world-model.md")
  [ "$wm_before" = "$wm_after" ]
}

@test "inject-event: does not write trigger files" {
  inject-event.sh "War declared" --home "$OPC_IR_HOME"
  local trigger_count
  trigger_count=$(find "$OPC_IR_HOME/triggers" -name '*.trigger' 2>/dev/null | wc -l | tr -d ' ')
  [ "$trigger_count" -eq 0 ]
}
