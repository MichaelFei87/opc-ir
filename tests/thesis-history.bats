#!/usr/bin/env bats

# thesis-history.bats — Validate thesis persistence and history (M2.4)

setup() {
  TEST_DIR=$(mktemp -d)
  export TEST_DIR
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "thesis-update creates thesis file from verdict" {
  VERDICT=$(mktemp)
  echo '{"ticker":"NDX","timestamp":"2026-05-07T10:00:00Z","consensus":{"direction":"long","conviction":0.72,"horizon":"1m","weighted_score":0.65},"votes":[{"role":"fundamental-analyst","direction":"long"}],"preserved_dissent":[{"role":"bear-advocate","direction":"short","reasoning_summary":"Overvalued on forward PE"}],"falsifiers":[{"role":"fundamental-analyst","condition":"If NDX drops below 18500 by 2026-06-07"}]}' > "$VERDICT"

  bin/thesis-update.sh "$TEST_DIR" NDX "$VERDICT"
  rm "$VERDICT"

  [ -f "$TEST_DIR/theses/NDX.md" ]
  grep -q 'NDX' "$TEST_DIR/theses/NDX.md"
  grep -q 'LONG' "$TEST_DIR/theses/NDX.md"
}

@test "thesis-update preserves direction and conviction" {
  VERDICT=$(mktemp)
  echo '{"ticker":"NDX","timestamp":"2026-05-07T10:00:00Z","consensus":{"direction":"long","conviction":0.72,"horizon":"1m","weighted_score":0.65},"votes":[{"role":"fundamental-analyst","direction":"long"}],"preserved_dissent":[{"role":"bear-advocate","direction":"short","reasoning_summary":"Overvalued on forward PE"}],"falsifiers":[{"role":"fundamental-analyst","condition":"If NDX drops below 18500 by 2026-06-07"}]}' > "$VERDICT"

  bin/thesis-update.sh "$TEST_DIR" NDX "$VERDICT"
  rm "$VERDICT"

  grep -q 'Direction:.*LONG' "$TEST_DIR/theses/NDX.md"
  grep -q 'Conviction:.*72%' "$TEST_DIR/theses/NDX.md"
  grep -q 'Horizon:.*1m' "$TEST_DIR/theses/NDX.md"
}

@test "thesis-update includes falsifiers" {
  VERDICT=$(mktemp)
  echo '{"ticker":"NDX","timestamp":"2026-05-07T10:00:00Z","consensus":{"direction":"long","conviction":0.72,"horizon":"1m","weighted_score":0.65},"votes":[{"role":"fundamental-analyst","direction":"long"}],"preserved_dissent":[],"falsifiers":[{"role":"fundamental-analyst","condition":"If NDX drops below 18500 by 2026-06-07"}]}' > "$VERDICT"

  bin/thesis-update.sh "$TEST_DIR" NDX "$VERDICT"
  rm "$VERDICT"

  grep -q 'Active Falsifiers' "$TEST_DIR/theses/NDX.md"
  grep -q 'fundamental-analyst' "$TEST_DIR/theses/NDX.md"
}

@test "second verdict creates History section with prior stance" {
  V1=$(mktemp)
  V2=$(mktemp)
  echo '{"ticker":"NDX","timestamp":"2026-05-07T10:00:00Z","consensus":{"direction":"long","conviction":0.72,"horizon":"1m","weighted_score":0.65},"votes":[{"role":"fundamental-analyst","direction":"long"}],"preserved_dissent":[{"role":"bear-advocate","direction":"short","reasoning_summary":"Overvalued on forward PE"}],"falsifiers":[{"role":"fundamental-analyst","condition":"If NDX drops below 18500 by 2026-06-07"}]}' > "$V1"
  echo '{"ticker":"NDX","timestamp":"2026-05-08T14:00:00Z","consensus":{"direction":"neutral","conviction":0.55,"horizon":"1w","weighted_score":0.05},"votes":[{"role":"fundamental-analyst","direction":"neutral"}],"preserved_dissent":[{"role":"bear-advocate","direction":"short","reasoning_summary":"Overvalued on forward PE"}],"falsifiers":[{"role":"fundamental-analyst","condition":"If NDX drops below 18000 by 2026-06-01"}]}' > "$V2"

  bin/thesis-update.sh "$TEST_DIR" NDX "$V1"
  bin/thesis-update.sh "$TEST_DIR" NDX "$V2"
  rm "$V1" "$V2"

  grep -q 'History' "$TEST_DIR/theses/NDX.md"
  grep -A5 'History' "$TEST_DIR/theses/NDX.md" | grep -qi 'long'
}

@test "second verdict updates direction to new stance" {
  V1=$(mktemp)
  V2=$(mktemp)
  echo '{"ticker":"NDX","timestamp":"2026-05-07T10:00:00Z","consensus":{"direction":"long","conviction":0.72,"horizon":"1m","weighted_score":0.65},"votes":[{"role":"fundamental-analyst","direction":"long"}],"preserved_dissent":[],"falsifiers":[{"role":"fundamental-analyst","condition":"If NDX drops below 18500 by 2026-06-07"}]}' > "$V1"
  echo '{"ticker":"NDX","timestamp":"2026-05-08T14:00:00Z","consensus":{"direction":"neutral","conviction":0.55,"horizon":"1w","weighted_score":0.05},"votes":[{"role":"fundamental-analyst","direction":"neutral"}],"preserved_dissent":[],"falsifiers":[{"role":"fundamental-analyst","condition":"If NDX drops below 18000 by 2026-06-01"}]}' > "$V2"

  bin/thesis-update.sh "$TEST_DIR" NDX "$V1"
  bin/thesis-update.sh "$TEST_DIR" NDX "$V2"
  rm "$V1" "$V2"

  grep -q 'direction: neutral' "$TEST_DIR/theses/NDX.md"
}

@test "third verdict preserves full history chain" {
  V1=$(mktemp)
  V2=$(mktemp)
  V3=$(mktemp)
  echo '{"ticker":"NDX","timestamp":"2026-05-07T10:00:00Z","consensus":{"direction":"long","conviction":0.72,"horizon":"1m","weighted_score":0.65},"votes":[],"preserved_dissent":[],"falsifiers":[{"role":"fundamental-analyst","condition":"If NDX drops below 18500 by 2026-06-07"}]}' > "$V1"
  echo '{"ticker":"NDX","timestamp":"2026-05-08T14:00:00Z","consensus":{"direction":"neutral","conviction":0.55,"horizon":"1w","weighted_score":0.05},"votes":[],"preserved_dissent":[],"falsifiers":[{"role":"fundamental-analyst","condition":"If NDX drops below 18000 by 2026-06-01"}]}' > "$V2"
  echo '{"ticker":"NDX","timestamp":"2026-05-09T10:00:00Z","consensus":{"direction":"short","conviction":0.68,"horizon":"1w","weighted_score":-0.45},"votes":[],"preserved_dissent":[],"falsifiers":[{"role":"technical-analyst","condition":"If NDX bounces above 19000 by 2026-05-16"}]}' > "$V3"

  bin/thesis-update.sh "$TEST_DIR" NDX "$V1"
  bin/thesis-update.sh "$TEST_DIR" NDX "$V2"
  bin/thesis-update.sh "$TEST_DIR" NDX "$V3"
  rm "$V1" "$V2" "$V3"

  grep -q 'direction: short' "$TEST_DIR/theses/NDX.md"
  HISTORY=$(grep -A10 '## History' "$TEST_DIR/theses/NDX.md")
  echo "$HISTORY" | grep -qi 'neutral'
  echo "$HISTORY" | grep -qi 'long'
}
