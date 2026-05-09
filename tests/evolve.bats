#!/usr/bin/env bats

# evolve.bats — Full evolve chain test with inline watcher outputs (M2.3)
#
# evolve-synthesize.sh signature:
#   evolve-synthesize.sh <watcher-outputs-dir> <world-model.jsonl> [--market-dir <path>]
#
# The script:
#   1. Discovers .md files in watcher-outputs-dir → dimensions_updated
#   2. Appends delta metadata to world-model.jsonl
#   3. If --market-dir, renders market-data-section.md in parent of watcher-outputs-dir

setup() {
  TEST_DIR=$(mktemp -d)
  export TEST_DIR

  # Add bin/ to PATH so bats can find the scripts
  export PATH="$BATS_TEST_DIRNAME/../bin:$PATH"

  # Create inline watcher outputs as .md (matching what watchers actually produce)
  WATCHER_DIR="$TEST_DIR/run/watchers"
  mkdir -p "$WATCHER_DIR"

  cat > "$WATCHER_DIR/politics.md" << 'EOF'
## Politics Delta

- **us_china_trade**: elevated tensions → escalating - new semiconductor tariffs
  - Trigger: ft-20260505-005
  - Confidence: 0.9
EOF

  cat > "$WATCHER_DIR/econ-finance.md" << 'EOF'
## Econ-Finance Delta

- **fed_rate_stance**: hawkish hold → patient hold, divided committee
  - Trigger: reuters-20260507-001
  - Confidence: 0.85
- **us_labor_market**: cooling → resilient, claims at 6-month low
  - Trigger: cnbc-20260504-007
  - Confidence: 0.8
EOF

  cat > "$WATCHER_DIR/energy-commodity.md" << 'EOF'
## Energy-Commodity Delta

- **oil_supply**: OPEC+ cuts through Q2 → OPEC+ extends cuts through Q3 2026
  - Trigger: reuters-20260506-004
  - Confidence: 0.9
- **gold_safe_haven**: elevated at $2340 → new ATH above $2400 on geopolitical concern
  - Trigger: bloomberg-20260502-010
  - Confidence: 0.85
EOF
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "evolve-synthesize appends delta metadata to world-model.jsonl" {
  touch "$TEST_DIR/world-model.jsonl"

  evolve-synthesize.sh "$TEST_DIR/run/watchers" "$TEST_DIR/world-model.jsonl"

  [ -s "$TEST_DIR/world-model.jsonl" ]

  line=$(tail -1 "$TEST_DIR/world-model.jsonl")
  # Verify it's valid JSON with expected fields
  echo "$line" | jq -e '.run_id' > /dev/null
  echo "$line" | jq -e '.dimensions_updated' > /dev/null
  echo "$line" | jq -e '.watcher_count' > /dev/null
}

@test "evolve-synthesize records correct watcher count" {
  touch "$TEST_DIR/world-model.jsonl"

  evolve-synthesize.sh "$TEST_DIR/run/watchers" "$TEST_DIR/world-model.jsonl"

  watcher_count=$(tail -1 "$TEST_DIR/world-model.jsonl" | jq '.watcher_count')
  [ "$watcher_count" -eq 3 ]
}

@test "evolve-synthesize records correct dimensions" {
  touch "$TEST_DIR/world-model.jsonl"

  evolve-synthesize.sh "$TEST_DIR/run/watchers" "$TEST_DIR/world-model.jsonl"

  dims=$(tail -1 "$TEST_DIR/world-model.jsonl" | jq -r '.dimensions_updated | sort | join(",")')
  [ "$dims" = "econ-finance,energy-commodity,politics" ]
}

@test "evolve-synthesize handles empty watcher dir gracefully" {
  empty_dir=$(mktemp -d)
  touch "$TEST_DIR/world-model.jsonl"

  run evolve-synthesize.sh "$empty_dir" "$TEST_DIR/world-model.jsonl"
  [ "$status" -eq 0 ]

  # Should still append to jsonl (with 0 watchers)
  [ -s "$TEST_DIR/world-model.jsonl" ]
  watcher_count=$(tail -1 "$TEST_DIR/world-model.jsonl" | jq '.watcher_count')
  [ "$watcher_count" -eq 0 ]

  rm -rf "$empty_dir"
}

@test "evolve-synthesize produces market-data-section.md when --market-dir provided" {
  touch "$TEST_DIR/world-model.jsonl"

  # Create inline market data
  MARKET_DIR="$TEST_DIR/market"
  mkdir -p "$MARKET_DIR/earnings"

  cat > "$MARKET_DIR/macro-snapshot.json" << 'EOF'
{"fetched_at":"2026-05-09T12:00:00Z","instruments":{"US3M":{"yield":5.32,"change_1d":"+2bp","trend_1m":"sideways","high_60d":5.4,"low_60d":5.2},"US2Y":{"yield":4.85,"change_1d":"-3bp","trend_1m":"down","high_60d":5.1,"low_60d":4.7},"US5Y":{"yield":4.45,"change_1d":"-2bp","trend_1m":"down","high_60d":4.7,"low_60d":4.3},"US10Y":{"yield":4.35,"change_1d":"-4bp","trend_1m":"down","high_60d":4.6,"low_60d":4.2},"US30Y":{"yield":4.55,"change_1d":"-3bp","trend_1m":"down","high_60d":4.8,"low_60d":4.4},"2s10s_spread":{"value":-0.5,"trend_1m":"narrowing"},"NDX":{"price":18500,"change_1d_pct":"+0.8%","trend_1w":"up","trend_1m":"sideways","high_60d":19000,"low_60d":17500},"SPX":{"price":5200,"change_1d_pct":"+0.5%","trend_1w":"up","trend_1m":"sideways","high_60d":5300,"low_60d":4900},"RUT":{"price":2050,"change_1d_pct":"+0.3%","trend_1w":"sideways","trend_1m":"down","high_60d":2200,"low_60d":1950},"VIX":{"price":15.2,"change_1d_pct":"-2.1%","trend_1w":"down","trend_1m":"down","high_60d":22,"low_60d":14},"DXY":{"price":104.5,"change_1d_pct":"-0.2%","trend_1w":"down","trend_1m":"sideways","high_60d":106,"low_60d":103},"GLD":{"price":2400,"change_1d_pct":"+1.2%","trend_1w":"up","trend_1m":"up","high_60d":2420,"low_60d":2200},"WTI":{"price":78.5,"change_1d_pct":"+0.5%","trend_1w":"sideways","trend_1m":"up","high_60d":82,"low_60d":72},"BTC":{"price":62000,"change_1d_pct":"+1.5%","trend_1w":"up","trend_1m":"sideways","high_60d":65000,"low_60d":55000}},"_stats":{"success":14,"failed":0}}
EOF

  cat > "$MARKET_DIR/watcher-snapshot.json" << 'EOF'
{"fetched_at":"2026-05-09T12:00:00Z","assets":{"MSFT":{"price":420,"change_1d_pct":"+0.8%","high_52w":450,"low_52w":340,"trend_3m":"up","trend_1m":"sideways"},"NVDA":{"price":880,"change_1d_pct":"+2.1%","high_52w":950,"low_52w":450,"trend_3m":"up","trend_1m":"up"}}}
EOF

  evolve-synthesize.sh "$TEST_DIR/run/watchers" "$TEST_DIR/world-model.jsonl" \
    --market-dir "$MARKET_DIR"

  # market-data-section.md should be in the run dir (parent of watchers/)
  [ -f "$TEST_DIR/run/market-data-section.md" ]
  grep -q '## Market Data' "$TEST_DIR/run/market-data-section.md"
  grep -q '### Yield Curve' "$TEST_DIR/run/market-data-section.md"
  grep -q '### Equity Indices' "$TEST_DIR/run/market-data-section.md"
  grep -q '### Tracked Equities' "$TEST_DIR/run/market-data-section.md"
  grep -q 'US10Y' "$TEST_DIR/run/market-data-section.md"
  grep -q 'NVDA' "$TEST_DIR/run/market-data-section.md"
  grep -q 'SPX' "$TEST_DIR/run/market-data-section.md"
}

@test "evolve-synthesize without --market-dir produces empty market-data-section.md" {
  touch "$TEST_DIR/world-model.jsonl"

  evolve-synthesize.sh "$TEST_DIR/run/watchers" "$TEST_DIR/world-model.jsonl"

  # market-data-section.md should exist but be empty (no market dir)
  [ -f "$TEST_DIR/run/market-data-section.md" ]
  # No Market Data header when no market dir provided
  ! grep -q '## Market Data' "$TEST_DIR/run/market-data-section.md"
}

@test "evolve-synthesize generates unique run_id per invocation" {
  touch "$TEST_DIR/world-model.jsonl"

  evolve-synthesize.sh "$TEST_DIR/run/watchers" "$TEST_DIR/world-model.jsonl"
  sleep 1
  evolve-synthesize.sh "$TEST_DIR/run/watchers" "$TEST_DIR/world-model.jsonl"

  run_ids=$(cat "$TEST_DIR/world-model.jsonl" | jq -r '.run_id')
  id1=$(echo "$run_ids" | head -1)
  id2=$(echo "$run_ids" | tail -1)
  [ "$id1" != "$id2" ]
}
