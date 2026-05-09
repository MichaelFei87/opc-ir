#!/usr/bin/env bats

# invalidator-lint.bats — Validate invalidator specificity check (M1.3 + M4 mitigation)

@test "good invalidator passes: specific with number, date, asset" {
  run bin/invalidator-lint.sh "If SPX drops below 4200 by Q3 2026, this forecast is invalidated"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "good invalidator passes: Fed rate cut" {
  run bin/invalidator-lint.sh "Invalidated if Fed cuts rates by more than 50bps before December 2026"
  [ "$status" -eq 0 ]
}

@test "bad invalidator fails: vague 'if X significantly changes'" {
  run bin/invalidator-lint.sh "If market conditions significantly change"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL"* ]]
}

@test "bad invalidator fails: missing numeric threshold" {
  run bin/invalidator-lint.sh "If SPX drops significantly by Q three next year"
  [ "$status" -eq 1 ]
  [[ "$output" == *"numeric"* ]]
}

@test "bad invalidator fails: missing temporal" {
  run bin/invalidator-lint.sh "If SPX drops below 4200"
  [ "$status" -eq 1 ]
  [[ "$output" == *"temporal"* ]]
}

@test "bad invalidator fails: missing asset" {
  run bin/invalidator-lint.sh "If the index drops below 4200 by Q3 2026"
  [ "$status" -eq 1 ]
  [[ "$output" == *"asset"* ]]
}

@test "good invalidator from file" {
  tmp=$(mktemp)
  echo "NDX falls below 18000 within 30 days of this forecast" > "$tmp"
  run bin/invalidator-lint.sh "$tmp"
  [ "$status" -eq 0 ]
  rm -f "$tmp"
}
