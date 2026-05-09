#!/usr/bin/env bash
set -euo pipefail

# trigger-manage.sh — Manage hard-rule trigger marker files
# Usage:
#   trigger-manage.sh create <ticker>     → write trigger file
#   trigger-manage.sh check  <ticker>     → exit 0 if triggerable, exit 1 if cooling
#   trigger-manage.sh consume <ticker>    → delete trigger file
#   trigger-manage.sh list                → list pending triggers (ticker per line)

OPC_IR_HOME="${OPC_IR_HOME:-$HOME/.opc-ir}"
TRIGGER_DIR="$OPC_IR_HOME/triggers"
VERDICTS_FILE="$OPC_IR_HOME/verdict/verdicts.jsonl"
COOLDOWN_SECONDS="${OPC_IR_VERDICT_COOLDOWN:-21600}"  # 6 hours

mkdir -p "$TRIGGER_DIR"

ACTION="${1:-list}"
TICKER="${2:-}"

# Validate ticker format (alphanumeric, dots, underscores, dashes only)
validate_ticker() {
  [[ -z "$1" ]] && { echo "ERROR: ticker required" >&2; exit 1; }
  [[ "$1" =~ ^[A-Z0-9._-]+$ ]] || { echo "ERROR: invalid ticker format: $1" >&2; exit 1; }
}

case "$ACTION" in
  create)
    validate_ticker "$TICKER"
    echo "{\"ticker\":\"$TICKER\",\"created_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
      > "$TRIGGER_DIR/${TICKER}.trigger"
    echo "Trigger created for $TICKER"
    ;;

  check)
    validate_ticker "$TICKER"
    if [[ -f "$VERDICTS_FILE" ]]; then
      # Find last verdict timestamp for this ticker using python (macOS compat)
      # Pass values via env vars to avoid code injection
      ELAPSED=$(VERDICTS_FILE="$VERDICTS_FILE" TICKER="$TICKER" python3 -c "
import json, sys, time, os
from datetime import datetime
verdicts_file = os.environ['VERDICTS_FILE']
ticker = os.environ['TICKER']
last_ts = None
try:
    for line in open(verdicts_file):
        line = line.strip()
        if not line: continue
        obj = json.loads(line)
        if obj.get('ticker') == ticker:
            ts = obj.get('ts') or obj.get('timestamp', '')
            if ts: last_ts = ts
except: pass
if last_ts:
    try:
        dt = datetime.fromisoformat(last_ts.replace('Z', '+00:00'))
        elapsed = time.time() - dt.timestamp()
        print(int(elapsed))
    except:
        print(-1)
else:
    print(-1)
" 2>/dev/null || echo "-1")

      if [[ "$ELAPSED" -ge 0 ]] && [[ "$ELAPSED" -lt "$COOLDOWN_SECONDS" ]]; then
        REMAINING=$(( (COOLDOWN_SECONDS - ELAPSED) / 60 ))
        echo "COOLING: $TICKER last verdict ${ELAPSED}s ago, ${REMAINING}m remaining"
        exit 1
      fi
    fi
    echo "READY: $TICKER"
    exit 0
    ;;

  consume)
    validate_ticker "$TICKER"
    rm -f "$TRIGGER_DIR/${TICKER}.trigger"
    echo "Trigger consumed for $TICKER"
    ;;

  list)
    for f in "$TRIGGER_DIR"/*.trigger; do
      [[ -f "$f" ]] || continue
      basename "$f" .trigger
    done
    ;;

  *)
    echo "Usage: trigger-manage.sh {create|check|consume|list} [ticker]" >&2
    exit 1
    ;;
esac
