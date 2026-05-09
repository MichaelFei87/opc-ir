#!/usr/bin/env bash
set -euo pipefail

# inject-event.sh — Insert a manual event into events.jsonl
# Usage: inject-event.sh <title> [--summary <text>] [--url <url>] [--home <path>]

OPC_IR_HOME="${OPC_IR_HOME:-$HOME/.opc-ir}"
TITLE=""
SUMMARY=""
URL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --summary) SUMMARY="$2"; shift 2 ;;
    --url)     URL="$2"; shift 2 ;;
    --home)    OPC_IR_HOME="$2"; shift 2 ;;
    *)         [[ -z "$TITLE" ]] && TITLE="$1"; shift ;;
  esac
done

[[ -z "$TITLE" ]] && { echo "ERROR: event title required" >&2; exit 1; }

EVENTS_FILE="$OPC_IR_HOME/events/events.jsonl"
mkdir -p "$(dirname "$EVENTS_FILE")"
touch "$EVENTS_FILE"

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
HASH=$(echo -n "manual-${TITLE}-${NOW}" | md5 2>/dev/null | cut -c1-12 || echo -n "manual-${TITLE}-${NOW}" | md5sum | cut -c1-12)
EVENT_ID="manual-${NOW}-${HASH}"

[[ -z "$SUMMARY" ]] && SUMMARY="$TITLE"
[[ -z "$URL" ]] && URL="manual://injected"

jq -cn \
  --arg id "$EVENT_ID" \
  --arg source "manual" \
  --arg fetched_at "$NOW" \
  --arg published_at "$NOW" \
  --arg title "$TITLE" \
  --arg summary "$SUMMARY" \
  --arg url "$URL" \
  --arg raw_text "$SUMMARY" \
  '{id:$id, source:$source, fetched_at:$fetched_at, published_at:$published_at, title:$title, summary:$summary, url:$url, raw_text:$raw_text}' \
  >> "$EVENTS_FILE"

echo "1"
