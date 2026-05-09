#!/usr/bin/env bats

# mitigations.bats — Validate all Phase 1 mandatory risk mitigations (M1.5)

@test "M3: vote-aggregate clamps posterior 5.0 to 1.5" {
  tmp_dir=$(mktemp -d)
  cat > "$tmp_dir/votes.json" << 'EOF'
[
  {
    "role": "test-role",
    "distribution": {"strongly_bearish": 0.1, "bearish": 0.2, "neutral": 0.4, "bullish": 0.2, "strongly_bullish": 0.1},
    "prior_weight": 1.0,
    "posterior_weight": 5.0
  }
]
EOF

  bin/vote-aggregate.sh "$tmp_dir/votes.json" "$tmp_dir/output.json"

  clamped=$(jq '.weights_used[0].posterior_clamped' "$tmp_dir/output.json")
  [ "$clamped" = "1.5" ]

  rm -rf "$tmp_dir"
}

@test "M3: vote-aggregate clamps posterior 0.0 to 0.5" {
  tmp_dir=$(mktemp -d)
  cat > "$tmp_dir/votes.json" << 'EOF'
[
  {
    "role": "test-role",
    "distribution": {"strongly_bearish": 0.1, "bearish": 0.2, "neutral": 0.4, "bullish": 0.2, "strongly_bullish": 0.1},
    "prior_weight": 1.0,
    "posterior_weight": 0.0
  }
]
EOF

  bin/vote-aggregate.sh "$tmp_dir/votes.json" "$tmp_dir/output.json"
  clamped=$(jq '.weights_used[0].posterior_clamped' "$tmp_dir/output.json")
  [ "$clamped" = "0.5" ]

  rm -rf "$tmp_dir"
}

@test "M4: invalidator-lint requires specificity (numeric+temporal+asset)" {
  # Good: passes
  run bin/invalidator-lint.sh "If SPX drops below 4200 by Q3 2026"
  [ "$status" -eq 0 ]

  # Bad: fails
  run bin/invalidator-lint.sh "If market conditions significantly change"
  [ "$status" -eq 1 ]
}

@test "P1: disclaimer present in verdict-protocol template" {
  grep -qi "research analysis, not investment advice" pipeline/verdict-protocol.md
}

@test "P2: regime_marker field in forecast schema" {
  jq '.properties.regime_marker' tests/schemas/forecast.schema.json | grep -q 'string'
}

@test "P2: regime_marker field in verdict schema" {
  jq '.properties.regime_marker' tests/schemas/verdict.schema.json | grep -q 'string'
}

@test "D2: README has Limitations section" {
  grep -q '## Limitations' README.md
}

@test "ARCHITECTURE.md has mitigation cross-reference" {
  grep -q 'M3' docs/ARCHITECTURE.md
  grep -q 'M4' docs/ARCHITECTURE.md
  grep -q 'P1' docs/ARCHITECTURE.md
  grep -q 'P2' docs/ARCHITECTURE.md
  grep -q 'D2' docs/ARCHITECTURE.md
}
