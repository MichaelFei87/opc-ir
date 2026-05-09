#!/usr/bin/env bats

# trigger-consume.bats — Trigger lifecycle tests (M3.3)

setup() {
  export OPC_IR_HOME="$(mktemp -d)"
  mkdir -p "$OPC_IR_HOME/triggers" "$OPC_IR_HOME/verdict" "$OPC_IR_HOME/logs"
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export PATH="$SCRIPT_DIR/bin:$PATH"
}

teardown() {
  rm -rf "$OPC_IR_HOME"
}

@test "trigger-manage: create writes marker file" {
  run trigger-manage.sh create NDX
  [ "$status" -eq 0 ]
  [ -f "$OPC_IR_HOME/triggers/NDX.trigger" ]
  jq -e '.ticker == "NDX"' "$OPC_IR_HOME/triggers/NDX.trigger"
}

@test "trigger-manage: list returns pending triggers" {
  trigger-manage.sh create NDX
  trigger-manage.sh create SPX
  run trigger-manage.sh list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "NDX"
  echo "$output" | grep -q "SPX"
}

@test "trigger-manage: consume deletes marker" {
  trigger-manage.sh create NDX
  [ -f "$OPC_IR_HOME/triggers/NDX.trigger" ]
  trigger-manage.sh consume NDX
  [ ! -f "$OPC_IR_HOME/triggers/NDX.trigger" ]
}

@test "trigger-manage: check passes with no prior verdict" {
  run trigger-manage.sh check NDX
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "READY"
}

@test "trigger-manage: check fails during cool-down" {
  NOW_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "{\"ticker\":\"NDX\",\"ts\":\"$NOW_TS\",\"consensus\":{\"direction\":\"long\"}}" \
    > "$OPC_IR_HOME/verdict/verdicts.jsonl"

  export OPC_IR_VERDICT_COOLDOWN=21600
  run trigger-manage.sh check NDX
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "COOLING"
}

@test "trigger-manage: different tickers have independent cool-downs" {
  NOW_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "{\"ticker\":\"NDX\",\"ts\":\"$NOW_TS\",\"consensus\":{}}" \
    > "$OPC_IR_HOME/verdict/verdicts.jsonl"

  export OPC_IR_VERDICT_COOLDOWN=21600
  run trigger-manage.sh check NDX
  [ "$status" -eq 1 ]
  run trigger-manage.sh check SPX
  [ "$status" -eq 0 ]
}

@test "trigger consumption: always consumed even on cool-down skip" {
  NOW_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "{\"ticker\":\"NDX\",\"ts\":\"$NOW_TS\",\"consensus\":{}}" \
    > "$OPC_IR_HOME/verdict/verdicts.jsonl"

  trigger-manage.sh create NDX
  [ -f "$OPC_IR_HOME/triggers/NDX.trigger" ]

  export OPC_IR_VERDICT_COOLDOWN=21600
  if ! trigger-manage.sh check NDX; then
    trigger-manage.sh consume NDX
  fi
  [ ! -f "$OPC_IR_HOME/triggers/NDX.trigger" ]
}
