#!/usr/bin/env bash
set -euo pipefail

# events-grep.sh — Search across monthly events files
# Usage: events-grep.sh [--after YYYY-MM-DD] [--before YYYY-MM-DD] [--months N] [--jq FILTER]
# Default: last 3 months. Output: JSONL to stdout.

OPC_IR_HOME="${OPC_IR_HOME:-$HOME/.opc-ir}"
EVENTS_DIR="$OPC_IR_HOME/events"
AFTER=""
BEFORE=""
MONTHS=3
JQ_FILTER="."

while [[ $# -gt 0 ]]; do
  case "$1" in
    --after)  AFTER="$2"; shift 2 ;;
    --before) BEFORE="$2"; shift 2 ;;
    --months) MONTHS="$2"; shift 2 ;;
    --jq)     JQ_FILTER="$2"; shift 2 ;;
    --home)   OPC_IR_HOME="$2"; EVENTS_DIR="$OPC_IR_HOME/events"; shift 2 ;;
    *)        echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

# Collect matching files
FILES=()

if [[ -n "$AFTER" || -n "$BEFORE" ]]; then
  # Date range mode
  for f in "$EVENTS_DIR"/*-events.jsonl; do
    [[ -f "$f" ]] || continue
    month=$(basename "$f" | grep -oE '^[0-9]{4}-[0-9]{2}' || true)
    [[ -z "$month" ]] && continue
    month_start="${month}-01"
    if [[ -n "$BEFORE" && "$month_start" > "$BEFORE" ]]; then continue; fi
    if [[ -n "$AFTER" ]]; then
      month_end="${month}-31"
      [[ "$month_end" < "$AFTER" ]] && continue
    fi
    FILES+=("$f")
  done
else
  # Last N months — use python for macOS date compat
  MONTHS_LIST=$(MONTHS="$MONTHS" python3 -c "
import os
from datetime import datetime, timedelta
months = int(os.environ['MONTHS'])
now = datetime.now()
for i in range(months):
    d = now.replace(day=1) - timedelta(days=30*i)
    print(d.strftime('%Y-%m'))
" 2>/dev/null)
  for month in $MONTHS_LIST; do
    f="$EVENTS_DIR/${month}-events.jsonl"
    [[ -f "$f" ]] && FILES+=("$f")
  done
fi

# Also check plain events.jsonl (non-monthly mode) as fallback
if [[ ${#FILES[@]} -eq 0 && -f "$EVENTS_DIR/events.jsonl" ]]; then
  FILES=("$EVENTS_DIR/events.jsonl")
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  exit 0
fi

# Concatenate, apply jq filter, then date filters
cat "${FILES[@]}" 2>/dev/null | jq -c "$JQ_FILTER" 2>/dev/null | \
  if [[ -n "$AFTER" ]]; then
    jq -c --arg after "$AFTER" 'select((.published_at // .fetched_at // "")[0:10] >= $after)'
  else
    cat
  fi | \
  if [[ -n "$BEFORE" ]]; then
    jq -c --arg before "$BEFORE" 'select((.published_at // .fetched_at // "")[0:10] <= $before)'
  else
    cat
  fi
