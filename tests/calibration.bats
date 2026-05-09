#!/usr/bin/env bats

# calibration.bats — Tests for fetch-prices, ground-truth-linker, calibrate-posteriors (P4.1)

setup() {
  TEST_DIR=$(mktemp -d)
  export OPC_IR_HOME="$TEST_DIR"
  mkdir -p "$TEST_DIR/calibration" "$TEST_DIR/forecast" "$TEST_DIR/verdict" "$TEST_DIR/logs"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── fetch-prices.sh (live API) ──

@test "fetch-prices returns valid JSON with close price from Yahoo" {
  python3 -c "import urllib.request" 2>/dev/null || skip "no network"
  result=$(bin/fetch-prices.sh NDX 2026-05-01)
  echo "$result" | jq -e '.close' >/dev/null
  source=$(echo "$result" | jq -r '.source')
  [ "$source" = "yahoo" ]
}

@test "fetch-prices returns correct date and asset" {
  python3 -c "import urllib.request" 2>/dev/null || skip "no network"
  result=$(bin/fetch-prices.sh SPX 2026-05-01)
  asset=$(echo "$result" | jq -r '.asset')
  date=$(echo "$result" | jq -r '.date')
  [ "$asset" = "SPX" ]
  [ "$date" = "2026-05-01" ]
}

@test "fetch-prices exits 1 for unknown asset" {
  run bin/fetch-prices.sh FAKEASSET 2026-05-01
  [ "$status" -eq 1 ]
}

# ── ground-truth-linker.sh ──

@test "ground-truth-linker produces truth records from forecast" {
  # Create a forecast that matured (date in the past)
  cat > "$TEST_DIR/forecast/forecast.jsonl" << 'EOF'
{"run_id":"r1","ts":"2026-04-01T00:00:00Z","forecasts":{"NDX":{"1w":{"strongly_bearish":0.05,"bearish":0.1,"neutral":0.2,"bullish":0.4,"strongly_bullish":0.25}}}}
EOF

  result=$(bin/ground-truth-linker.sh --home "$TEST_DIR")
  # Should produce at least 1 new record
  [ "$result" -ge 1 ]

  # predictions-vs-truth.jsonl should exist and have content
  [ -s "$TEST_DIR/calibration/predictions-vs-truth.jsonl" ]
}

@test "ground-truth-linker deduplicates on re-run" {
  cat > "$TEST_DIR/forecast/forecast.jsonl" << 'EOF'
{"run_id":"r1","ts":"2026-04-01T00:00:00Z","forecasts":{"NDX":{"1w":{"strongly_bearish":0.05,"bearish":0.1,"neutral":0.2,"bullish":0.4,"strongly_bullish":0.25}}}}
EOF

  bin/ground-truth-linker.sh --home "$TEST_DIR" >/dev/null
  result=$(bin/ground-truth-linker.sh --home "$TEST_DIR")
  # Second run should find 0 new records (all deduped)
  [ "$result" -eq 0 ]
}

@test "ground-truth-linker skips unmatured forecasts" {
  # Future date forecast — should not link
  cat > "$TEST_DIR/forecast/forecast.jsonl" << 'EOF'
{"run_id":"r3","ts":"2099-01-01T00:00:00Z","forecasts":{"NDX":{"1w":{"strongly_bearish":0.2,"bearish":0.2,"neutral":0.2,"bullish":0.2,"strongly_bullish":0.2}}}}
EOF

  result=$(bin/ground-truth-linker.sh --home "$TEST_DIR")
  [ "$result" -eq 0 ]
}

# ── calibrate-posteriors.sh ──

@test "calibrate-posteriors outputs no_data when no truth file" {
  result=$(bin/calibrate-posteriors.sh --home "$TEST_DIR")
  status=$(echo "$result" | jq -r '.status')
  [ "$status" = "no_data" ]
}

@test "calibrate-posteriors produces report from truth records" {
  for i in $(seq 1 5); do
    echo '{"run_id":"r'$i'","asset":"NDX","horizon":"1w","role":"_consensus","predicted_dist":{"strongly_bearish":0.1,"bearish":0.2,"neutral":0.3,"bullish":0.3,"strongly_bullish":0.1},"truth_onehot":[0,0,0,1,0]}' >> "$TEST_DIR/calibration/predictions-vs-truth.jsonl"
  done

  result=$(bin/calibrate-posteriors.sh --home "$TEST_DIR")
  total=$(echo "$result" | jq '.total_records')
  [ "$total" -eq 5 ]
  [ -f "$TEST_DIR/calibration/calibration-report.json" ]
}

@test "calibrate-posteriors cold-starts with n<30" {
  for i in $(seq 1 10); do
    echo '{"run_id":"r'$i'","asset":"NDX","horizon":"1w","role":"fundamental-analyst","predicted_dist":{"strongly_bearish":0.1,"bearish":0.2,"neutral":0.3,"bullish":0.3,"strongly_bullish":0.1},"truth_onehot":[0,0,0,1,0]}' >> "$TEST_DIR/calibration/predictions-vs-truth.jsonl"
  done

  bin/calibrate-posteriors.sh --home "$TEST_DIR" >/dev/null
  reason=$(jq -r '.role_results["fundamental-analyst"].reason' "$TEST_DIR/calibration/calibration-report.json")
  [[ "$reason" == cold_start* ]]
}
