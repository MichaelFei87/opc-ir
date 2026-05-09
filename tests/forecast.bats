#!/usr/bin/env bats

# forecast.bats — End-to-end forecast flow test (M1.3)
# vote-aggregate.sh supports two modes:
#   Batch:  vote-aggregate.sh <strat-dir> <weights.yaml> <output-dir>
#   Single: vote-aggregate.sh <strat-dir> <asset> <horizon> <weights.yaml> <output.json>

setup() {
  TEST_DIR=$(mktemp -d)
  export TEST_DIR
  mkdir -p "$TEST_DIR/strategist-outputs"
  mkdir -p "$TEST_DIR/aggregated"
  cat > "$TEST_DIR/role-weights.yaml" << 'EOF'
forecast:
  macro-strategist:
    prior_weight: 1.0
  cross-asset-allocator:
    prior_weight: 1.0
  regime-detector:
    prior_weight: 1.0
  historical-analogist:
    prior_weight: 1.0
  contrarian-strategist:
    prior_weight: 1.0
EOF
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Helper: write a strategist JSON file with entries for given asset/horizon pairs
# Usage: write_strategist <role> <asset> <horizon> <sb> <b> <n> <bu> <sbu> <invalidator>
write_strategist() {
  local role="$1" asset="$2" horizon="$3" sb="$4" b="$5" n="$6" bu="$7" sbu="$8" invalidator="$9"
  local fpath="$TEST_DIR/strategist-outputs/${role}.json"
  local entry="{\"asset\":\"${asset}\",\"horizon\":\"${horizon}\",\"distribution\":{\"strongly_bearish\":${sb},\"bearish\":${b},\"neutral\":${n},\"bullish\":${bu},\"strongly_bullish\":${sbu}},\"invalidator\":\"${invalidator}\",\"confidence_note\":\"test\"}"

  if [[ -f "$fpath" ]]; then
    # Append to existing array
    local existing
    existing=$(cat "$fpath")
    echo "$existing" | jq ". += [${entry}]" > "$fpath"
  else
    echo "[${entry}]" > "$fpath"
  fi
}

# --- Single mode tests ---

@test "single: produces valid output from 5 strategist votes" {
  write_strategist macro-strategist      NDX 1w 0.05 0.15 0.40 0.30 0.10 "Fed raises rates above 5.5% before Q4 2026"
  write_strategist cross-asset-allocator NDX 1w 0.08 0.22 0.35 0.25 0.10 "DXY exceeds 110 within 30 days"
  write_strategist regime-detector       NDX 1w 0.03 0.12 0.45 0.30 0.10 "VIX closes above 25 before July 2026"
  write_strategist historical-analogist  NDX 1w 0.10 0.25 0.30 0.25 0.10 "SPX drops below 4800 by June 2026"
  write_strategist contrarian-strategist NDX 1w 0.15 0.30 0.25 0.20 0.10 "NDX breaks above 22000 by Q3 2026"

  bin/vote-aggregate.sh "$TEST_DIR/strategist-outputs" NDX 1w "$TEST_DIR/role-weights.yaml" "$TEST_DIR/aggregated/NDX_1w.json"

  [ -f "$TEST_DIR/aggregated/NDX_1w.json" ]
  jq -e '.aggregated' "$TEST_DIR/aggregated/NDX_1w.json" > /dev/null
  [ "$(jq -r '.asset' "$TEST_DIR/aggregated/NDX_1w.json")" = "NDX" ]
  [ "$(jq -r '.horizon' "$TEST_DIR/aggregated/NDX_1w.json")" = "1w" ]
}

@test "single: distribution sums to ~1.0" {
  write_strategist macro-strategist NDX 1w 0.05 0.15 0.40 0.30 0.10 "Fed raises rates above 5.5% before Q4 2026"
  write_strategist regime-detector  NDX 1w 0.03 0.12 0.45 0.30 0.10 "VIX closes above 25 before July 2026"

  bin/vote-aggregate.sh "$TEST_DIR/strategist-outputs" NDX 1w "$TEST_DIR/role-weights.yaml" "$TEST_DIR/aggregated/NDX_1w.json"

  sum=$(jq '[.aggregated[]] | add' "$TEST_DIR/aggregated/NDX_1w.json")
  python3 -c "assert abs($sum - 1.0) < 0.01, f'Sum {$sum} not close to 1.0'"
}

@test "single: detects dissent (L1 > 0.3)" {
  write_strategist macro-strategist      NDX 1w 0.05 0.10 0.50 0.25 0.10 "Fed raises rates above 5.5% before Q4 2026"
  write_strategist contrarian-strategist NDX 1w 0.30 0.35 0.15 0.15 0.05 "NDX breaks above 22000 by Q3 2026"

  bin/vote-aggregate.sh "$TEST_DIR/strategist-outputs" NDX 1w "$TEST_DIR/role-weights.yaml" "$TEST_DIR/aggregated/NDX_1w.json"

  dissent_count=$(jq '.dissent | length' "$TEST_DIR/aggregated/NDX_1w.json")
  [ "$dissent_count" -ge 1 ]
}

@test "single: normalizes bad distribution" {
  # Distribution sums to 0.8
  cat > "$TEST_DIR/strategist-outputs/macro-strategist.json" << 'EOF'
[{"asset":"NDX","horizon":"1w","distribution":{"strongly_bearish":0.04,"bearish":0.12,"neutral":0.32,"bullish":0.24,"strongly_bullish":0.08},"invalidator":"Fed raises rates above 5.5% before Q4 2026","confidence_note":"test"}]
EOF
  write_strategist regime-detector NDX 1w 0.03 0.12 0.45 0.30 0.10 "VIX closes above 25 before July 2026"

  bin/vote-aggregate.sh "$TEST_DIR/strategist-outputs" NDX 1w "$TEST_DIR/role-weights.yaml" "$TEST_DIR/aggregated/NDX_1w.json"

  sum=$(jq '[.aggregated[]] | add' "$TEST_DIR/aggregated/NDX_1w.json")
  python3 -c "assert abs($sum - 1.0) < 0.01, f'Sum {$sum} not close to 1.0 after normalization'"
}

@test "single: fails when no votes match" {
  cat > "$TEST_DIR/strategist-outputs/macro-strategist.json" << 'EOF'
[{"asset":"SPX","horizon":"1w","distribution":{"strongly_bearish":0.05,"bearish":0.15,"neutral":0.40,"bullish":0.30,"strongly_bullish":0.10},"invalidator":"SPX drops below 7000 within 30 days","confidence_note":"test"}]
EOF

  run bin/vote-aggregate.sh "$TEST_DIR/strategist-outputs" NDX 1w "$TEST_DIR/role-weights.yaml" "$TEST_DIR/aggregated/NDX_1w.json"
  [ "$status" -ne 0 ]
}

# --- Batch mode tests ---

@test "batch: aggregates multiple asset/horizon pairs" {
  write_strategist macro-strategist NDX 1w 0.05 0.15 0.40 0.30 0.10 "Fed raises rates above 5.5% before Q4 2026"
  write_strategist macro-strategist NDX 1m 0.10 0.20 0.35 0.25 0.10 "Fed raises rates above 5.5% before Q4 2026"
  write_strategist macro-strategist SPX 1w 0.03 0.12 0.45 0.30 0.10 "SPX drops below 7000 within 30 days"
  write_strategist regime-detector  NDX 1w 0.03 0.12 0.45 0.30 0.10 "VIX closes above 25 before July 2026"
  write_strategist regime-detector  NDX 1m 0.08 0.18 0.40 0.24 0.10 "VIX closes above 25 before July 2026"
  write_strategist regime-detector  SPX 1w 0.05 0.15 0.40 0.30 0.10 "VIX closes above 25 before July 2026"

  bin/vote-aggregate.sh "$TEST_DIR/strategist-outputs" "$TEST_DIR/role-weights.yaml" "$TEST_DIR/aggregated"

  # Should produce 3 files: NDX_1w, NDX_1m, SPX_1w
  [ -f "$TEST_DIR/aggregated/NDX_1w.json" ]
  [ -f "$TEST_DIR/aggregated/NDX_1m.json" ]
  [ -f "$TEST_DIR/aggregated/SPX_1w.json" ]

  # Verify content
  [ "$(jq -r '.asset' "$TEST_DIR/aggregated/NDX_1w.json")" = "NDX" ]
  [ "$(jq -r '.horizon' "$TEST_DIR/aggregated/SPX_1w.json")" = "1w" ]
}

@test "batch: each output sums to ~1.0" {
  write_strategist macro-strategist NDX 1w 0.05 0.15 0.40 0.30 0.10 "Fed raises rates above 5.5% before Q4 2026"
  write_strategist macro-strategist SPX 1d 0.10 0.20 0.35 0.25 0.10 "SPX drops below 7000 within 30 days"
  write_strategist regime-detector  NDX 1w 0.03 0.12 0.45 0.30 0.10 "VIX closes above 25 before July 2026"
  write_strategist regime-detector  SPX 1d 0.05 0.15 0.40 0.30 0.10 "VIX closes above 25 before July 2026"

  bin/vote-aggregate.sh "$TEST_DIR/strategist-outputs" "$TEST_DIR/role-weights.yaml" "$TEST_DIR/aggregated"

  for f in "$TEST_DIR/aggregated/"*.json; do
    sum=$(jq '[.aggregated[]] | add' "$f")
    python3 -c "assert abs($sum - 1.0) < 0.01, f'$(basename "$f"): sum {$sum} not ~1.0'"
  done
}

@test "batch: prints summary with counts" {
  write_strategist macro-strategist NDX 1w 0.05 0.15 0.40 0.30 0.10 "Fed raises rates above 5.5% before Q4 2026"

  run bin/vote-aggregate.sh "$TEST_DIR/strategist-outputs" "$TEST_DIR/role-weights.yaml" "$TEST_DIR/aggregated"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Aggregated 1 pairs"
}

# --- Render & lint tests ---

@test "forecast-render produces markdown with ASCII bars" {
  mkdir -p "$TEST_DIR/forecast"
  cat > "$TEST_DIR/forecast/forecast.jsonl" << 'EOF'
{"run_id":"test-001","timestamp":"2026-05-08T12:00:00Z","world_model_ref":"wm-sample","regime_marker":null,"forecasts":{"NDX":{"1w":{"strongly_bearish":0.05,"bearish":0.15,"neutral":0.40,"bullish":0.30,"strongly_bullish":0.10}}},"strategist_dissent":[],"invalidators":{"NDX":{"1w":"If NDX falls below 18000 within 7 days"}}}
EOF

  bin/forecast-render.sh "$TEST_DIR"

  [ -f "$TEST_DIR/forecast/forecast.md" ]
  grep -q 'NDX' "$TEST_DIR/forecast/forecast.md"
  grep -q '▓' "$TEST_DIR/forecast/forecast.md"
}

@test "forecast schema validates sample forecast" {
  cat > "$TEST_DIR/sample-forecast.json" << 'EOF'
{"run_id":"test-001","timestamp":"2026-05-08T12:00:00Z","world_model_ref":"wm-sample","regime_marker":null,"forecasts":{"NDX":{"1w":{"strongly_bearish":0.05,"bearish":0.15,"neutral":0.40,"bullish":0.30,"strongly_bullish":0.10}}},"strategist_dissent":[],"invalidators":{"NDX":{"1w":"If NDX falls below 18000 within 7 days of this forecast generation"}}}
EOF

  for key in run_id timestamp world_model_ref forecasts strategist_dissent invalidators regime_marker; do
    jq "has(\"$key\")" "$TEST_DIR/sample-forecast.json" | grep -q 'true' || {
      echo "Missing required key: $key"
      return 1
    }
  done
}

@test "forecast-assemble produces valid forecast.jsonl line" {
  # Setup: create a mini forecast run with aggregated + strategist-outputs
  FRUN="$TEST_DIR/run-test"
  mkdir -p "$FRUN/aggregated" "$FRUN/strategist-outputs" "$TEST_DIR/forecast" "$TEST_DIR/world"

  # Write a world-model stub
  cat > "$TEST_DIR/world/world-model.md" << 'WM'
---
updated: 2026-05-08
---
# World Model
WM

  # Write one aggregated file
  cat > "$FRUN/aggregated/NDX_1w.json" << 'EOF'
{"asset":"NDX","horizon":"1w","aggregated":{"strongly_bearish":0.05,"bearish":0.15,"neutral":0.40,"bullish":0.30,"strongly_bullish":0.10},"dissent":[],"weights_used":[],"total_weight":5.0}
EOF

  # Write one strategist output (for invalidator extraction)
  cat > "$FRUN/strategist-outputs/macro-strategist.json" << 'EOF'
[{"asset":"NDX","horizon":"1w","distribution":{"strongly_bearish":0.05,"bearish":0.15,"neutral":0.40,"bullish":0.30,"strongly_bullish":0.10},"invalidator":"NDX drops below 28000 within 7 days","confidence_note":"test"}]
EOF

  bin/forecast-assemble.sh "$FRUN" "$TEST_DIR"

  [ -f "$TEST_DIR/forecast/forecast.jsonl" ]
  # Should have one line
  line_count=$(wc -l < "$TEST_DIR/forecast/forecast.jsonl" | tr -d ' ')
  [ "$line_count" -ge 1 ]
  # Should be valid JSON with required keys
  tail -1 "$TEST_DIR/forecast/forecast.jsonl" | jq -e '.forecasts.NDX["1w"]' > /dev/null
  tail -1 "$TEST_DIR/forecast/forecast.jsonl" | jq -e '.invalidators.NDX' > /dev/null
}

@test "invalidator-lint passes good inline text" {
  run bin/invalidator-lint.sh "If SPX drops below 4200 by Q3 2026"
  [ "$status" -eq 0 ]
}

@test "invalidator-lint rejects bad inline text" {
  run bin/invalidator-lint.sh "Things might change"
  [ "$status" -eq 1 ]
}
