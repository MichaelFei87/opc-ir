#!/usr/bin/env bash
set -euo pipefail

# token-tracker.sh — per-run token logging and accumulated visibility
# Usage: token-tracker.sh <record|summary> [args...]

OPC_IR_HOME="${OPC_IR_HOME:-$HOME/.opc-ir}"
TOKEN_DIR="$OPC_IR_HOME/logs/tokens"
mkdir -p "$TOKEN_DIR"

case "${1:-help}" in
  record)
    COMMAND="$2"
    RUN_ID="$3"
    INPUT_TOKENS="$4"
    OUTPUT_TOKENS="$5"

    # Validate inputs are integers
    printf '%d' "$INPUT_TOKENS" >/dev/null 2>&1 || { echo "ERROR: input_tokens must be integer" >&2; exit 1; }
    printf '%d' "$OUTPUT_TOKENS" >/dev/null 2>&1 || { echo "ERROR: output_tokens must be integer" >&2; exit 1; }

    TOTAL=$(( INPUT_TOKENS + OUTPUT_TOKENS ))
    NOW_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    DATE=$(date -u +"%Y-%m-%d")

    # Use jq for safe JSON construction (never string interpolation)
    jq -n --arg ts "$NOW_ISO" \
          --arg command "$COMMAND" \
          --arg run_id "$RUN_ID" \
          --argjson input_tokens "$INPUT_TOKENS" \
          --argjson output_tokens "$OUTPUT_TOKENS" \
          --argjson total "$TOTAL" \
          -c '{ts:$ts,command:$command,run_id:$run_id,input_tokens:$input_tokens,output_tokens:$output_tokens,total:$total}' \
      >> "$TOKEN_DIR/$DATE.jsonl"
    ;;

  summary)
    DAYS="${2:-7}"
    echo "=== Token Usage (last ${DAYS} days) ==="
    echo ""

    GRAND_TOTAL=0

    for i in $(seq 0 $((DAYS - 1))); do
      # macOS compat: use python for date math, pass $i via env var
      DATE=$(OPC_DAYS="$i" python3 -c "
import os
from datetime import datetime, timedelta, timezone
d = datetime.now(timezone.utc) - timedelta(days=int(os.environ['OPC_DAYS']))
print(d.strftime('%Y-%m-%d'))
")
      FILE="$TOKEN_DIR/$DATE.jsonl"
      if [[ -f "$FILE" ]]; then
        # Use jq for accumulation (returns integer, avoids bash float parsing)
        DAY_TOTAL=$(jq -s '[.[].total] | add // 0 | floor' "$FILE")
        DAY_RUNS=$(wc -l < "$FILE" | tr -d ' ')
        echo "$DATE: ${DAY_RUNS} runs, ${DAY_TOTAL} tokens"
        GRAND_TOTAL=$((GRAND_TOTAL + DAY_TOTAL))
      fi
    done

    echo ""
    echo "Total: ${GRAND_TOTAL} tokens"
    if [[ "$DAYS" -gt 0 ]]; then
      AVG=$((GRAND_TOTAL / DAYS))
      PROJECTED=$((AVG * 30))
      echo "Daily avg: ${AVG} tokens"
      echo "Projected: ${PROJECTED} tokens/month"
    fi
    ;;

  *)
    echo "Usage: token-tracker.sh <record|summary> [args...]"
    exit 1
    ;;
esac
