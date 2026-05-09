#!/usr/bin/env bash
set -euo pipefail

# fetch-rss.sh — Fetch RSS feeds, dedup, append to events.jsonl
# Usage: fetch-rss.sh [--sources <path>] [--home <path>]
# Exit 0 always (per-source failures logged, never abort).
# Stdout: count of new events appended.

OPC_IR_HOME="${OPC_IR_HOME:-$HOME/.opc-ir}"
SOURCES_FILE=""
FETCH_TIMEOUT="${OPC_IR_RSS_TIMEOUT:-10}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sources) SOURCES_FILE="$2"; shift 2 ;;
    --home)    OPC_IR_HOME="$2"; shift 2 ;;
    *)         shift ;;
  esac
done

EVENTS_FILE="$OPC_IR_HOME/events/events.jsonl"
LOG_DIR="$OPC_IR_HOME/logs"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).log"
mkdir -p "$OPC_IR_HOME/events" "$LOG_DIR"

# If events.jsonl is a symlink (post-migration), ensure it points to current month
if [[ -L "$EVENTS_FILE" ]]; then
  CURRENT_MONTH=$(date +%Y-%m)
  CURRENT_MONTHLY="$OPC_IR_HOME/events/${CURRENT_MONTH}-events.jsonl"
  touch "$CURRENT_MONTHLY"
  ln -sf "${CURRENT_MONTH}-events.jsonl" "$EVENTS_FILE"
fi

touch "$EVENTS_FILE"

# Resolve sources file
if [[ -z "$SOURCES_FILE" ]]; then
  USER_SOURCES="$OPC_IR_HOME/config/local.yaml"
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  DEFAULT_SOURCES="$SCRIPT_DIR/defaults/sources.yaml"
  if [[ -f "$USER_SOURCES" ]] && [[ "$(yq e '.sources | length' "$USER_SOURCES" 2>/dev/null)" -gt 0 ]]; then
    SOURCES_FILE="$USER_SOURCES"
  else
    SOURCES_FILE="$DEFAULT_SOURCES"
  fi
fi

log_msg() {
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "[$ts] fetch-rss: $1" >> "$LOG_FILE"
}

NEW_COUNT=0

# Get source count from YAML
source_count=$(yq e '.sources | length' "$SOURCES_FILE" 2>/dev/null || echo 0)
if [[ "$source_count" -eq 0 ]]; then
  log_msg "No sources configured"
  echo "0"
  exit 0
fi

for ((i=0; i<source_count; i++)); do
  name=$(yq e ".sources[$i].id // .sources[$i].name // \"source-$i\"" "$SOURCES_FILE")
  url=$(yq e ".sources[$i].url" "$SOURCES_FILE")
  enabled=$(yq e ".sources[$i].enabled" "$SOURCES_FILE")
  [[ "$enabled" == "null" ]] && enabled="true"
  source_type=$(yq e ".sources[$i].type // \"rss\"" "$SOURCES_FILE")

  [[ "$enabled" != "true" ]] && continue
  [[ "$source_type" != "rss" ]] && continue

  log_msg "Fetching $name from $url"

  # Fetch content (support file:// for testing)
  xml_content=""
  if [[ "$url" == file://* ]]; then
    local_path="${url#file://}"
    if [[ -f "$local_path" ]]; then
      xml_content=$(cat "$local_path" 2>/dev/null) || { log_msg "WARN: read failed for $name"; continue; }
    else
      log_msg "WARN: file not found for $name: $local_path"
      continue
    fi
  else
    xml_content=$(curl -sS --max-time "$FETCH_TIMEOUT" -L "$url" 2>>"$LOG_FILE") || {
      log_msg "WARN: fetch failed for $name (timeout or network error), skipping"
      continue
    }
  fi

  # Parse RSS and dedup using python (macOS bash 3.x compatible — no associative arrays)
  # Write XML to temp file since heredoc occupies stdin
  XML_TMP=$(mktemp)
  trap 'rm -f "$XML_TMP"' EXIT
  printf '%s\n' "$xml_content" > "$XML_TMP"

  NEW_EVENTS=$(EVENTS_FILE="$EVENTS_FILE" \
    SOURCE_NAME="$name" XML_FILE="$XML_TMP" python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import json, hashlib, os, sys
from datetime import datetime, timezone, timedelta

source_name = os.environ["SOURCE_NAME"]
events_file = os.environ["EVENTS_FILE"]

with open(os.environ["XML_FILE"]) as f:
    xml_input = f.read()

# Full-file dedup: scan ALL existing events by id, url, and title
seen_ids = set()
seen_urls = set()
seen_titles = set()

def title_key(t):
    return ''.join(c for c in t.lower() if c.isalnum())[:80]

try:
    with open(events_file) as f:
        for line in f:
            line = line.strip()
            if not line: continue
            try:
                obj = json.loads(line)
                if obj.get('id'): seen_ids.add(obj['id'])
                if obj.get('url'): seen_urls.add(obj['url'])
                if obj.get('title'): seen_titles.add(title_key(obj['title']))
            except Exception: pass
except FileNotFoundError:
    pass

# Parse RSS XML
now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
new_events = []

try:
    root = ET.fromstring(xml_input)
except ET.ParseError:
    sys.exit(0)  # malformed XML — skip silently

for item in root.iter('item'):
    title_el = item.find('title')
    link_el = item.find('link')
    desc_el = item.find('description')
    pubdate_el = item.find('pubDate')

    title = (title_el.text or '').strip() if title_el is not None else ''
    link = (link_el.text or '').strip() if link_el is not None else ''
    desc = (desc_el.text or '').strip() if desc_el is not None else ''
    pubdate = (pubdate_el.text or '').strip() if pubdate_el is not None else ''

    if not title and not link:
        continue

    # Truncate description
    desc = desc[:2000]

    # Generate deterministic ID
    hash_input = f"{source_name}-{link}-{title}"
    hash_val = hashlib.md5(hash_input.encode()).hexdigest()[:12]

    # Parse pubDate (best effort)
    pub_utc = now
    if pubdate:
        try:
            from email.utils import parsedate_to_datetime
            dt = parsedate_to_datetime(pubdate)
            pub_utc = dt.strftime('%Y-%m-%dT%H:%M:%SZ')
        except Exception:
            pass

    # Skip events older than 6 months
    try:
        pub_dt = datetime.strptime(pub_utc, '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)
        cutoff = datetime.now(timezone.utc) - timedelta(days=180)
        if pub_dt < cutoff:
            continue
    except Exception:
        pass

    event_id = f"{source_name}-{pub_utc}-{hash_val}"

    # Dedup
    if event_id in seen_ids: continue
    if link and link in seen_urls: continue
    tk = title_key(title)
    if tk and tk in seen_titles: continue

    event = {
        "id": event_id,
        "source": source_name,
        "fetched_at": now,
        "published_at": pub_utc,
        "title": title,
        "summary": desc,
        "url": link,
        "raw_text": desc
    }
    new_events.append(json.dumps(event))
    seen_ids.add(event_id)
    if link: seen_urls.add(link)
    if tk: seen_titles.add(tk)

for ev in new_events:
    print(ev)
PYEOF
  ) || {
    log_msg "WARN: parse failed for $name, skipping"
    rm -f "$XML_TMP"
    continue
  }

  rm -f "$XML_TMP"

  if [[ -n "$NEW_EVENTS" ]]; then
    echo "$NEW_EVENTS" >> "$EVENTS_FILE"
    count=$(echo "$NEW_EVENTS" | wc -l | tr -d ' ')
    NEW_COUNT=$((NEW_COUNT + count))
    log_msg "OK $name: $count new events"
  else
    log_msg "OK $name: 0 new events (all deduped)"
  fi
done

log_msg "fetch-rss complete: $NEW_COUNT new events total"
echo "$NEW_COUNT"
exit 0
