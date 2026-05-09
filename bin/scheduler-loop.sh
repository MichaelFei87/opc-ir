#!/usr/bin/env bash
set -euo pipefail

# scheduler-loop.sh — /loop backend for OPC-IR scheduler
# Usage: scheduler-loop.sh <register|unregister|list|status|record-run> [args...]

OPC_IR_HOME="${OPC_IR_HOME:-$HOME/.opc-ir}"
SCHEDULER_DIR="$OPC_IR_HOME/scheduler"
STATE_FILE="$SCHEDULER_DIR/loop.json"
mkdir -p "$SCHEDULER_DIR"

if [[ ! -f "$STATE_FILE" ]]; then
  echo '{"backend":"loop","registered_at":null,"schedules":{}}' > "$STATE_FILE"
fi

case "${1:-help}" in
  register)
    SCHEDULE_NAME="$2"
    COMMAND="$3"
    INTERVAL="$4"
    NOW_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    # 7-day expiry — use python for macOS compat
    EXPIRY_ISO=$(python3 -c "
from datetime import datetime, timedelta, timezone
exp = datetime.now(timezone.utc) + timedelta(days=7)
print(exp.strftime('%Y-%m-%dT%H:%M:%SZ'))
")

    jq --arg name "$SCHEDULE_NAME" \
       --arg cmd "$COMMAND" \
       --arg int "$INTERVAL" \
       --arg now "$NOW_ISO" \
       --arg exp "$EXPIRY_ISO" \
       '.registered_at //= $now |
        .schedules[$name] = {
          command: $cmd,
          interval: $int,
          registered_at: $now,
          expires_at: $exp,
          last_run: null,
          last_exit_code: null
        }' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

    echo "Schedule '$SCHEDULE_NAME' registered."
    echo ""
    echo ">>> Run this in Claude Code to activate:"
    echo ">>>   /loop $INTERVAL $COMMAND"
    echo ""
    echo "WARNING: /loop expires in 7 days ($EXPIRY_ISO)."
    ;;

  unregister)
    SCHEDULE_NAME="$2"
    jq --arg name "$SCHEDULE_NAME" 'del(.schedules[$name])' \
       "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
    echo "Schedule '$SCHEDULE_NAME' unregistered."
    ;;

  list)
    jq -r '.schedules | to_entries[] |
      "\(.key)\t\(.value.command)\t\(.value.interval)\t\(.value.expires_at // "n/a")\t\(.value.last_exit_code // "pending")"' \
      "$STATE_FILE" 2>/dev/null || echo "(no schedules)"
    ;;

  status)
    SCHEDULE_NAME="$2"
    ENTRY=$(jq -r --arg name "$SCHEDULE_NAME" '.schedules[$name] // empty' "$STATE_FILE")
    if [[ -z "$ENTRY" ]]; then
      echo "Schedule '$SCHEDULE_NAME' not found."
      exit 1
    fi
    echo "$ENTRY" | jq .

    # Compute expiry countdown using python (macOS compat)
    EXPIRES_AT=$(echo "$ENTRY" | jq -r '.expires_at // empty')
    if [[ -n "$EXPIRES_AT" ]]; then
      EXPIRES_AT="$EXPIRES_AT" python3 -c "
import os, sys
from datetime import datetime, timezone
exp = datetime.fromisoformat(os.environ['EXPIRES_AT'].replace('Z', '+00:00'))
now = datetime.now(timezone.utc)
remaining = (exp - now).total_seconds()
if remaining <= 0:
    print('EXPIRED — /loop needs renewal.')
else:
    days = int(remaining // 86400)
    hours = int((remaining % 86400) // 3600)
    print(f'Expires in: {days}d {hours}h')
    if remaining <= 86400:
        print('WARNING: Less than 24 hours until /loop expiry!')
"
    fi
    ;;

  record-run)
    SCHEDULE_NAME="$2"
    EXIT_CODE="$3"
    NOW_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq --arg name "$SCHEDULE_NAME" \
       --arg now "$NOW_ISO" \
       --argjson code "$EXIT_CODE" \
       '.schedules[$name].last_run = $now |
        .schedules[$name].last_exit_code = $code' \
       "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
    ;;

  *)
    echo "Usage: scheduler-loop.sh <register|unregister|list|status|record-run> [args...]"
    exit 1
    ;;
esac
