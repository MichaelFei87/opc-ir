#!/usr/bin/env bats

# fetch-earnings.bats — Earnings fetch tests using live yfinance API

setup() {
  python3 -c "import yfinance" 2>/dev/null || skip "yfinance not installed"
  export OPC_IR_HOME="$(mktemp -d)"
  mkdir -p "$OPC_IR_HOME/market-data/earnings" "$OPC_IR_HOME/logs"
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export PATH="$SCRIPT_DIR/bin:$PATH"
}

teardown() {
  rm -rf "$OPC_IR_HOME"
}

# ── Live API tests ──

@test "fetch-earnings: fetches earnings for MSFT" {
  run fetch-earnings.sh MSFT --home "$OPC_IR_HOME" --assets "$SCRIPT_DIR/defaults/watch-assets.yaml"
  [ "$status" -eq 0 ]

  result=$(echo "$output" | tail -1)
  fetched=$(echo "$result" | jq '.fetched')
  skipped=$(echo "$result" | jq '.skipped')
  # Either fetched or skipped (already exists)
  [ "$((fetched + skipped))" -ge 1 ]
}

@test "fetch-earnings: earnings file has required fields" {
  fetch-earnings.sh MSFT --home "$OPC_IR_HOME" --assets "$SCRIPT_DIR/defaults/watch-assets.yaml" >/dev/null

  local f
  f=$(ls "$OPC_IR_HOME/market-data/earnings/MSFT-"*.json 2>/dev/null | head -1)
  [ -n "$f" ] || skip "no earnings file produced (may be skipped)"

  jq -e '.symbol and .quarter and .earnings_date and .fetched_at' "$f" >/dev/null
}

@test "fetch-earnings: quarter label format is YYYYQN" {
  fetch-earnings.sh MSFT --home "$OPC_IR_HOME" --assets "$SCRIPT_DIR/defaults/watch-assets.yaml" >/dev/null

  local f
  f=$(ls "$OPC_IR_HOME/market-data/earnings/MSFT-"*.json 2>/dev/null | head -1)
  [ -n "$f" ] || skip "no earnings file produced"

  local quarter
  quarter=$(jq -r '.quarter' "$f")
  [[ "$quarter" =~ ^[0-9]{4}Q[1-4]$ ]]
}

@test "fetch-earnings: eps fields are numeric when present" {
  fetch-earnings.sh MSFT --home "$OPC_IR_HOME" --assets "$SCRIPT_DIR/defaults/watch-assets.yaml" >/dev/null

  local f
  f=$(ls "$OPC_IR_HOME/market-data/earnings/MSFT-"*.json 2>/dev/null | head -1)
  [ -n "$f" ] || skip "no earnings file produced"

  # eps should be a number if present
  local eps
  eps=$(jq '.eps' "$f")
  [ "$eps" = "null" ] || [[ "$eps" =~ ^-?[0-9] ]]
}

@test "fetch-earnings: dedup skips on re-run" {
  fetch-earnings.sh MSFT --home "$OPC_IR_HOME" --assets "$SCRIPT_DIR/defaults/watch-assets.yaml" >/dev/null

  # Second run should skip
  result=$(fetch-earnings.sh MSFT --home "$OPC_IR_HOME" --assets "$SCRIPT_DIR/defaults/watch-assets.yaml")
  skipped=$(echo "$result" | jq '.skipped')
  [ "$skipped" -ge 1 ]
}

@test "fetch-earnings: summary field is null (pre-LLM)" {
  fetch-earnings.sh MSFT --home "$OPC_IR_HOME" --assets "$SCRIPT_DIR/defaults/watch-assets.yaml" >/dev/null

  local f
  f=$(ls "$OPC_IR_HOME/market-data/earnings/MSFT-"*.json 2>/dev/null | head -1)
  [ -n "$f" ] || skip "no earnings file produced"

  local summary
  summary=$(jq '.summary' "$f")
  [ "$summary" = "null" ]
}
