#!/usr/bin/env bats

# falsifier-lint.bats — Validate falsifier specificity check (M1.4)

@test "good falsifier passes" {
  run bin/falsifier-lint.sh "If NDX P/E exceeds 35 by June 2026 without earnings growth acceleration"
  [ "$status" -eq 0 ]
}

@test "bad falsifier fails" {
  run bin/falsifier-lint.sh "If market conditions change significantly"
  [ "$status" -eq 1 ]
}

@test "falsifier-lint with retry counter: first failure returns 1" {
  tmp_counter=$(mktemp)
  rm -f "$tmp_counter"

  run bin/falsifier-lint.sh "Vague without specifics" --retry-counter "$tmp_counter"
  [ "$status" -eq 1 ]
  [ -f "$tmp_counter" ]
  count=$(cat "$tmp_counter")
  [ "$count" = "1" ]

  rm -f "$tmp_counter"
}

@test "falsifier-lint with retry counter: second failure returns 2 (fatal)" {
  tmp_counter=$(mktemp)
  echo "1" > "$tmp_counter"

  run bin/falsifier-lint.sh "Still vague and unspecific" --retry-counter "$tmp_counter"
  [ "$status" -eq 2 ]

  rm -f "$tmp_counter"
}

@test "falsifier-lint passes good inline text" {
  run bin/falsifier-lint.sh "If SPX drops below 4200 by Q3 2026 without recovery above 4500"
  [ "$status" -eq 0 ]
}

@test "falsifier-lint rejects bad inline text" {
  run bin/falsifier-lint.sh "Markets could go either way"
  [ "$status" -eq 1 ]
}
