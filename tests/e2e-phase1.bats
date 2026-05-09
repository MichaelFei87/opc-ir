#!/usr/bin/env bats

# e2e-phase1.bats — End-to-end Phase 1 acceptance test

setup() {
  TEST_HOME=$(mktemp -d)
  export TEST_HOME
}

teardown() {
  rm -rf "$TEST_HOME"
}

@test "e2e: forecast flow produces forecast.md with ASCII bars" {
  mkdir -p "$TEST_HOME/forecast"

  # Inline strategist votes
  cat > "$TEST_HOME/votes.json" << 'EOF'
[
  {"role":"macro-strategist","distribution":{"strongly_bearish":0.05,"bearish":0.15,"neutral":0.40,"bullish":0.30,"strongly_bullish":0.10},"prior_weight":1.0,"invalidator":"If Fed raises rates above 5.5% before Q4 2026"},
  {"role":"regime-detector","distribution":{"strongly_bearish":0.03,"bearish":0.12,"neutral":0.45,"bullish":0.30,"strongly_bullish":0.10},"prior_weight":1.0,"invalidator":"If VIX closes above 25 for 3 consecutive days before July 2026"},
  {"role":"contrarian-strategist","distribution":{"strongly_bearish":0.15,"bearish":0.30,"neutral":0.25,"bullish":0.20,"strongly_bullish":0.10},"prior_weight":1.0,"invalidator":"If NDX breaks above 22000 by Q3 2026"}
]
EOF

  bin/vote-aggregate.sh "$TEST_HOME/votes.json" "$TEST_HOME/aggregated.json"

  python3 << PYEOF
import json
with open("$TEST_HOME/aggregated.json") as f:
    agg = json.load(f)
forecast = {
    "run_id": "e2e-test-001",
    "timestamp": "2026-05-08T12:00:00Z",
    "world_model_ref": "wm-sample",
    "regime_marker": None,
    "forecasts": {"NDX": {"1w": agg["aggregated"]}},
    "strategist_dissent": agg.get("dissent", []),
    "invalidators": {"NDX": {"1w": "If NDX falls below 18000 within 7 days of this forecast"}}
}
with open("$TEST_HOME/forecast/forecast.jsonl", "w") as f:
    f.write(json.dumps(forecast) + "\n")
PYEOF

  bin/forecast-render.sh "$TEST_HOME"

  [ -f "$TEST_HOME/forecast/forecast.md" ]
  grep -q 'NDX' "$TEST_HOME/forecast/forecast.md"
  grep -q '▓' "$TEST_HOME/forecast/forecast.md"
}

@test "e2e: verdict flow produces digest.md with disclaimer" {
  mkdir -p "$TEST_HOME/verdict"

  cat > "$TEST_HOME/votes.json" << 'EOF'
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

  bin/verdict-aggregate.sh "$TEST_HOME/votes.json" "$TEST_HOME/verdict-result.json"

  python3 << PYEOF
import json
with open("$TEST_HOME/verdict-result.json") as f:
    result = json.load(f)
verdict = {
    "run_id": "e2e-test-v001",
    "timestamp": "2026-05-08T12:00:00Z",
    "ticker": "NDX",
    "world_model_ref": "wm-sample",
    "forecast_ref": "fc-e2e-001",
    "regime_marker": None,
    "consensus": result["consensus"],
    "votes": result["votes"],
    "preserved_dissent": result["preserved_dissent"],
    "falsifiers": result["falsifiers"]
}
with open("$TEST_HOME/verdict/verdicts.jsonl", "w") as f:
    f.write(json.dumps(verdict) + "\n")
PYEOF

  bin/verdict-render-digest.sh "$TEST_HOME"

  [ -f "$TEST_HOME/verdict/digest.md" ]
  grep -qi "research analysis, not investment advice" "$TEST_HOME/verdict/digest.md"
  grep -q 'NDX' "$TEST_HOME/verdict/digest.md"
}

@test "e2e: invalidator-lint positive and negative cases" {
  run bin/invalidator-lint.sh "If SPX drops below 4200 by Q3 2026"
  [ "$status" -eq 0 ]

  run bin/invalidator-lint.sh "Things might change"
  [ "$status" -eq 1 ]
}

@test "e2e: falsifier-lint positive and negative cases" {
  run bin/falsifier-lint.sh "If NDX P/E exceeds 35 by June 2026"
  [ "$status" -eq 0 ]

  run bin/falsifier-lint.sh "Markets could go either way"
  [ "$status" -eq 1 ]
}

@test "e2e: all test suites pass" {
  bats tests/scaffold.bats tests/roles.bats tests/forked-meta.bats tests/invalidator-lint.bats tests/forecast.bats tests/verdict.bats tests/falsifier-lint.bats tests/mitigations.bats
}
