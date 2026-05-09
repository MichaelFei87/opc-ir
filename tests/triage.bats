#!/usr/bin/env bats

# triage.bats — Validate triage schema and classifier alignment (M2.1)

@test "triage schema has all 7 dimensions" {
  for dim in politics econ-finance military tech-ai humanities energy-commodity corp-fundamentals; do
    jq -e ".properties.dimension_scores.properties[\"$dim\"]" tests/schemas/triage.schema.json > /dev/null || {
      echo "Missing dimension: $dim"
      return 1
    }
  done
}

@test "triage schema requires hard_rule_hit boolean" {
  type=$(jq -r '.properties.hard_rule_hit.type' tests/schemas/triage.schema.json)
  [ "$type" = "boolean" ]
}

@test "triage-classifier agent file exists with scoring instructions" {
  [ -f agents/triage-classifier.md ]
  grep -q 'dimension_scores' agents/triage-classifier.md
  grep -q 'hard_rule_hit' agents/triage-classifier.md
}
