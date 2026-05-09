#!/usr/bin/env bats

# phase5.bats — Tests for Phase 5: scheduler, tokens, integrity

setup() {
  TEST_DIR=$(mktemp -d)
  export OPC_IR_HOME="$TEST_DIR"
  mkdir -p "$TEST_DIR/scheduler" "$TEST_DIR/logs/tokens" "$TEST_DIR/config"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── Scheduler ──

@test "scheduler-loop: register creates state file" {
  bin/scheduler-loop.sh register evolve /opc-ir-evolve 1h >/dev/null
  [ -f "$TEST_DIR/scheduler/loop.json" ]
  cmd=$(jq -r '.schedules.evolve.command' "$TEST_DIR/scheduler/loop.json")
  [ "$cmd" = "/opc-ir-evolve" ]
}

@test "scheduler-loop: list shows registered schedule" {
  bin/scheduler-loop.sh register evolve /opc-ir-evolve 1h >/dev/null
  result=$(bin/scheduler-loop.sh list)
  [[ "$result" == *"evolve"* ]]
}

@test "scheduler-loop: unregister removes schedule" {
  bin/scheduler-loop.sh register evolve /opc-ir-evolve 1h >/dev/null
  bin/scheduler-loop.sh unregister evolve >/dev/null
  count=$(jq '.schedules | length' "$TEST_DIR/scheduler/loop.json")
  [ "$count" -eq 0 ]
}

@test "scheduler-loop: record-run updates last_run" {
  bin/scheduler-loop.sh register evolve /opc-ir-evolve 1h >/dev/null
  bin/scheduler-loop.sh record-run evolve 0
  last_run=$(jq -r '.schedules.evolve.last_run' "$TEST_DIR/scheduler/loop.json")
  [ "$last_run" != "null" ]
  exit_code=$(jq '.schedules.evolve.last_exit_code' "$TEST_DIR/scheduler/loop.json")
  [ "$exit_code" -eq 0 ]
}

@test "scheduler-loop: status shows expiry" {
  bin/scheduler-loop.sh register evolve /opc-ir-evolve 1h >/dev/null
  result=$(bin/scheduler-loop.sh status evolve)
  [[ "$result" == *"Expires in"* ]]
}

@test "scheduler-dispatch routes to loop backend" {
  echo "loop" > "$TEST_DIR/scheduler/active-backend"
  bin/scheduler-loop.sh register test /opc-ir-evolve 1h >/dev/null
  result=$(bin/scheduler-dispatch.sh list)
  [[ "$result" == *"test"* ]]
}

# ── Token Tracker ──

@test "token-tracker: record creates daily log" {
  bin/token-tracker.sh record evolve run-1 5000 2000
  DATE=$(date -u +"%Y-%m-%d")
  [ -f "$TEST_DIR/logs/tokens/$DATE.jsonl" ]
  total=$(jq '.total' "$TEST_DIR/logs/tokens/$DATE.jsonl")
  [ "$total" -eq 7000 ]
}

@test "token-tracker: summary shows totals" {
  bin/token-tracker.sh record evolve run-1 5000 2000
  bin/token-tracker.sh record forecast run-2 3000 1000
  result=$(bin/token-tracker.sh summary 1)
  [[ "$result" == *"11000"* ]]
}

# ── Integrity ──

@test "integrity: lock creates install.lock and manifest" {
  bin/integrity.sh lock
  [ -f "$TEST_DIR/install.lock" ]
  [ -f "$TEST_DIR/install.manifest" ]
  master=$(jq -r '.master_hash' "$TEST_DIR/install.lock")
  [ ${#master} -eq 64 ]  # SHA256 hex length
}

@test "integrity: verify passes on clean install" {
  bin/integrity.sh lock
  run bin/integrity.sh verify
  [ "$status" -eq 0 ]
  [[ "$output" == *"INTEGRITY OK"* ]]
}

@test "integrity: verify detects modification" {
  bin/integrity.sh lock
  # Use a temp copy to avoid modifying the actual script
  ORIG_HASH=$(python3 -c "import hashlib; print(hashlib.sha256(open('bin/integrity.sh','rb').read()).hexdigest())")
  echo "# tampered" >> bin/integrity.sh
  run bin/integrity.sh verify
  [ "$status" -eq 2 ]
  [[ "$output" == *"MISMATCH"* ]]
  # Restore by removing tampered line
  sed -i '' '/^# tampered$/d' bin/integrity.sh
  # Verify restore worked
  RESTORED_HASH=$(python3 -c "import hashlib; print(hashlib.sha256(open('bin/integrity.sh','rb').read()).hexdigest())")
  [ "$ORIG_HASH" = "$RESTORED_HASH" ]
}

# ── Schedules (removed — schedules.yaml deleted, scheduler manages own state) ──
