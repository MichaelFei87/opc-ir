#!/usr/bin/env bats

# verdict.bats — End-to-end verdict flow test (M1.4)

setup() {
  TEST_DIR=$(mktemp -d)
  export TEST_DIR
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "verdict-aggregate produces valid output from 7 votes" {
  cat > "$TEST_DIR/votes.json" << 'EOF'
[
  {"role":"fundamental-analyst","direction":"long","weight":1.0,"horizon":"1m","thesis":"Strong earnings","falsifier":"If NDX P/E exceeds 35 by June 2026 without earnings growth acceleration above 20% YoY"},
  {"role":"technical-analyst","direction":"long","weight":1.0,"horizon":"1m","thesis":"Bullish breakout","falsifier":"If NDX breaks below 18500 support level within 2 weeks"},
  {"role":"macro-economist","direction":"neutral","weight":1.0,"horizon":"1m","thesis":"Mixed signals","falsifier":"If Fed signals emergency rate change before July 2026 FOMC meeting"},
  {"role":"quant-modeler","direction":"long","weight":1.0,"horizon":"1m","thesis":"Momentum aligned","falsifier":"If realized volatility exceeds 25% annualized for NDX within 30 days"},
  {"role":"behavioral-analyst","direction":"long","weight":1.0,"horizon":"1m","thesis":"Sentiment not euphoric","falsifier":"If AAII bullish sentiment exceeds 55% for 3 consecutive weeks before August 2026"},
  {"role":"bull-advocate","direction":"long","weight":0.5,"horizon":"1m","thesis":"AI capex tailwind","falsifier":"If top-5 NDX companies collectively cut capex guidance by more than 10% in Q2 2026"},
  {"role":"bear-advocate","direction":"short","weight":0.5,"horizon":"1m","thesis":"Valuation stretched","falsifier":"If NDX earnings growth accelerates above 25% YoY in next quarter"}
]
EOF

  bin/verdict-aggregate.sh "$TEST_DIR/votes.json" "$TEST_DIR/verdict.json"

  [ -f "$TEST_DIR/verdict.json" ]
  jq -e '.consensus' "$TEST_DIR/verdict.json" > /dev/null
  jq -e '.votes' "$TEST_DIR/verdict.json" > /dev/null
  jq -e '.falsifiers' "$TEST_DIR/verdict.json" > /dev/null
}

@test "verdict-aggregate consensus direction is long (5 long, 1 neutral, 1 short)" {
  cat > "$TEST_DIR/votes.json" << 'EOF'
[
  {"role":"fundamental-analyst","direction":"long","weight":1.0,"horizon":"1m","thesis":"Strong earnings","falsifier":"If NDX P/E exceeds 35 by June 2026"},
  {"role":"technical-analyst","direction":"long","weight":1.0,"horizon":"1m","thesis":"Bullish breakout","falsifier":"If NDX breaks below 18500 within 2 weeks"},
  {"role":"macro-economist","direction":"neutral","weight":1.0,"horizon":"1m","thesis":"Mixed signals","falsifier":"If Fed signals emergency rate change before July 2026"},
  {"role":"quant-modeler","direction":"long","weight":1.0,"horizon":"1m","thesis":"Momentum aligned","falsifier":"If realized volatility exceeds 25% for NDX within 30 days"},
  {"role":"behavioral-analyst","direction":"long","weight":1.0,"horizon":"1m","thesis":"Sentiment not euphoric","falsifier":"If AAII bullish sentiment exceeds 55% for 3 weeks"},
  {"role":"bull-advocate","direction":"long","weight":0.5,"horizon":"1m","thesis":"AI capex tailwind","falsifier":"If top-5 NDX companies cut capex guidance by 10% in Q2 2026"},
  {"role":"bear-advocate","direction":"short","weight":0.5,"horizon":"1m","thesis":"Valuation stretched","falsifier":"If NDX earnings growth accelerates above 25% YoY next quarter"}
]
EOF

  bin/verdict-aggregate.sh "$TEST_DIR/votes.json" "$TEST_DIR/verdict.json"
  direction=$(jq -r '.consensus.direction' "$TEST_DIR/verdict.json")
  [ "$direction" = "long" ]
}

@test "verdict-aggregate preserves dissent for bear-advocate" {
  cat > "$TEST_DIR/votes.json" << 'EOF'
[
  {"role":"fundamental-analyst","direction":"long","weight":1.0,"horizon":"1m","thesis":"Strong earnings","falsifier":"If NDX P/E exceeds 35 by June 2026"},
  {"role":"technical-analyst","direction":"long","weight":1.0,"horizon":"1m","thesis":"Bullish breakout","falsifier":"If NDX breaks below 18500 within 2 weeks"},
  {"role":"macro-economist","direction":"neutral","weight":1.0,"horizon":"1m","thesis":"Mixed signals","falsifier":"If Fed signals emergency rate change before July 2026"},
  {"role":"quant-modeler","direction":"long","weight":1.0,"horizon":"1m","thesis":"Momentum aligned","falsifier":"If realized volatility exceeds 25% for NDX within 30 days"},
  {"role":"behavioral-analyst","direction":"long","weight":1.0,"horizon":"1m","thesis":"Sentiment not euphoric","falsifier":"If AAII bullish sentiment exceeds 55% for 3 weeks"},
  {"role":"bull-advocate","direction":"long","weight":0.5,"horizon":"1m","thesis":"AI capex tailwind","falsifier":"If top-5 NDX companies cut capex guidance by 10% in Q2 2026"},
  {"role":"bear-advocate","direction":"short","weight":0.5,"horizon":"1m","thesis":"Valuation stretched","falsifier":"If NDX earnings growth accelerates above 25% YoY next quarter"}
]
EOF

  bin/verdict-aggregate.sh "$TEST_DIR/votes.json" "$TEST_DIR/verdict.json"
  dissent_count=$(jq '.preserved_dissent | length' "$TEST_DIR/verdict.json")
  [ "$dissent_count" -ge 1 ]
  jq -e '.preserved_dissent[] | select(.role == "bear-advocate")' "$TEST_DIR/verdict.json" > /dev/null
}

@test "verdict-aggregate collects falsifiers from all roles" {
  cat > "$TEST_DIR/votes.json" << 'EOF'
[
  {"role":"fundamental-analyst","direction":"long","weight":1.0,"horizon":"1m","thesis":"Strong earnings","falsifier":"If NDX P/E exceeds 35 by June 2026"},
  {"role":"technical-analyst","direction":"long","weight":1.0,"horizon":"1m","thesis":"Bullish breakout","falsifier":"If NDX breaks below 18500 within 2 weeks"},
  {"role":"macro-economist","direction":"neutral","weight":1.0,"horizon":"1m","thesis":"Mixed signals","falsifier":"If Fed signals emergency rate change before July 2026"},
  {"role":"quant-modeler","direction":"long","weight":1.0,"horizon":"1m","thesis":"Momentum aligned","falsifier":"If realized volatility exceeds 25% for NDX within 30 days"},
  {"role":"behavioral-analyst","direction":"long","weight":1.0,"horizon":"1m","thesis":"Sentiment not euphoric","falsifier":"If AAII bullish sentiment exceeds 55% for 3 weeks"},
  {"role":"bull-advocate","direction":"long","weight":0.5,"horizon":"1m","thesis":"AI capex tailwind","falsifier":"If top-5 NDX companies cut capex guidance by 10% in Q2 2026"},
  {"role":"bear-advocate","direction":"short","weight":0.5,"horizon":"1m","thesis":"Valuation stretched","falsifier":"If NDX earnings growth accelerates above 25% YoY next quarter"}
]
EOF

  bin/verdict-aggregate.sh "$TEST_DIR/votes.json" "$TEST_DIR/verdict.json"
  falsifier_count=$(jq '.falsifiers | length' "$TEST_DIR/verdict.json")
  [ "$falsifier_count" -eq 7 ]
}

@test "verdict-render-digest produces markdown with disclaimer" {
  mkdir -p "$TEST_DIR/verdict"
  cat > "$TEST_DIR/verdict/verdicts.jsonl" << 'EOF'
{"run_id":"test-v001","timestamp":"2026-05-08T12:00:00Z","ticker":"NDX","world_model_ref":"wm-sample","forecast_ref":"fc-001","regime_marker":null,"consensus":{"direction":"long","conviction":0.65,"horizon":"1m"},"votes":[],"preserved_dissent":[],"falsifiers":[{"role":"fundamental-analyst","condition":"If NDX P/E exceeds 35 by June 2026 without earnings growth"}]}
EOF

  bin/verdict-render-digest.sh "$TEST_DIR"

  [ -f "$TEST_DIR/verdict/digest.md" ]
  grep -qi "research analysis, not investment advice" "$TEST_DIR/verdict/digest.md"
  grep -q "NDX" "$TEST_DIR/verdict/digest.md"
  grep -q "LONG" "$TEST_DIR/verdict/digest.md"
}

@test "verdict-render-digest shows split warning for split verdict" {
  mkdir -p "$TEST_DIR/verdict"
  cat > "$TEST_DIR/verdict/verdicts.jsonl" << 'EOF'
{"run_id":"test-v002","timestamp":"2026-05-08T12:00:00Z","ticker":"SPX","world_model_ref":"wm-sample","forecast_ref":"fc-001","regime_marker":null,"consensus":{"direction":"split","conviction":0.05,"horizon":"1m"},"votes":[],"preserved_dissent":[],"falsifiers":[{"role":"test","condition":"If SPX drops below 4500 by Q3 2026 this verdict is wrong"}]}
EOF

  bin/verdict-render-digest.sh "$TEST_DIR"
  grep -q "Split verdict" "$TEST_DIR/verdict/digest.md"
}
