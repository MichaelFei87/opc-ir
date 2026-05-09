#!/usr/bin/env bash
set -euo pipefail

# events-migrate.sh — Migrate monolithic events.jsonl to monthly files
# Usage: events-migrate.sh [--home <path>]
# Idempotent: skips if events.jsonl is already a symlink

OPC_IR_HOME="${OPC_IR_HOME:-$HOME/.opc-ir}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --home) OPC_IR_HOME="$2"; shift 2 ;;
    *) shift ;;
  esac
done

EVENTS_DIR="$OPC_IR_HOME/events"
EVENTS_FILE="$EVENTS_DIR/events.jsonl"

# Skip if already migrated (symlink) or doesn't exist
if [[ -L "$EVENTS_FILE" ]] || [[ ! -f "$EVENTS_FILE" ]]; then
  echo "0"
  exit 0
fi

# Split into monthly files using python (macOS compat)
MIGRATED=$(OPC_IR_HOME="$OPC_IR_HOME" python3 << 'PYEOF'
import json, os

events_dir = os.path.join(os.environ["OPC_IR_HOME"], "events")
events_file = os.path.join(events_dir, "events.jsonl")

migrated = 0
with open(events_file) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
            ts = obj.get("published_at", obj.get("fetched_at", ""))
            month = ts[:7] if len(ts) >= 7 else "unknown"
            if month == "unknown":
                continue
            monthly_file = os.path.join(events_dir, f"{month}-events.jsonl")
            with open(monthly_file, "a") as out:
                out.write(line + "\n")
            migrated += 1
        except:
            pass

print(migrated)
PYEOF
)

# Backup and replace with symlink
CURRENT_MONTH=$(date +%Y-%m)
touch "$EVENTS_DIR/${CURRENT_MONTH}-events.jsonl"
mv "$EVENTS_FILE" "${EVENTS_FILE}.bak"
ln -sf "${CURRENT_MONTH}-events.jsonl" "$EVENTS_FILE"

echo "$MIGRATED"
