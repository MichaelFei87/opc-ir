#!/usr/bin/env bash
set -euo pipefail

# opc-ir-status.sh — system health dashboard
# Usage: opc-ir-status.sh

OPC_IR_HOME="${OPC_IR_HOME:-$HOME/.opc-ir}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Section 1: Plugin Info ──
echo "=== OPC-IR Status ==="
PLUGIN_VERSION=$(jq -r '.version // "unknown"' "$PLUGIN_ROOT/plugin.json" 2>/dev/null || echo "unknown")
echo "Plugin: v${PLUGIN_VERSION}"
echo ""

# ── Section 2: Integrity ──
if "$SCRIPT_DIR/integrity.sh" verify >/dev/null 2>&1; then
  MASTER=$(jq -r '.master_hash' "$OPC_IR_HOME/install.lock" 2>/dev/null || echo "unknown")
  echo "Integrity: OK (SHA: ${MASTER:0:12})"
elif [[ -f "$OPC_IR_HOME/install.lock" ]]; then
  echo "Integrity: MISMATCH — run /opc-ir-init to re-lock"
else
  echo "Integrity: Not locked — run /opc-ir-init"
fi
echo ""

# ── Section 3: Scheduler ──
echo "=== Scheduler ==="
BACKEND=$(cat "$OPC_IR_HOME/scheduler/active-backend" 2>/dev/null || echo "loop")
echo "Backend: $BACKEND"
"$SCRIPT_DIR/scheduler-dispatch.sh" list 2>/dev/null || echo "(no schedules registered)"
echo ""

# ── Section 4: Streams ──
echo "=== Streams ==="
NOW=$(date +%s)

report_stream() {
  local label="$1" filepath="$2" stale_hours="${3:-0}"
  if [[ -f "$filepath" ]]; then
    local mtime mtime_fmt age_h warn=""
    mtime=$(stat -f "%m" "$filepath" 2>/dev/null || stat -c "%Y" "$filepath" 2>/dev/null)
    mtime_fmt=$(date -r "$mtime" "+%Y-%m-%d %H:%M" 2>/dev/null || date -d "@$mtime" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "unknown")
    age_h=$(( (NOW - mtime) / 3600 ))
    if [[ "$stale_hours" -gt 0 && "$age_h" -gt "$stale_hours" ]]; then
      warn=" ⚠️  Stale (${age_h}h, threshold ${stale_hours}h)"
    fi
    printf "  %-16s %s (%dh ago)%s\n" "$label:" "$mtime_fmt" "$age_h" "$warn"
  else
    printf "  %-16s never\n" "$label:"
  fi
}

report_stream "World-Model" "$OPC_IR_HOME/world/world-model.md" 24
report_stream "Forecast"    "$OPC_IR_HOME/forecast/forecast.md"  16
report_stream "Digest"      "$OPC_IR_HOME/verdict/digest.md"     0

# Calibration
if [[ -f "$OPC_IR_HOME/calibration/calibration-report.json" ]]; then
  TOTAL=$(jq -r '.total_records // "?"' "$OPC_IR_HOME/calibration/calibration-report.json" 2>/dev/null || echo "?")
  REGIME=$(jq -r '.regime_warning // empty' "$OPC_IR_HOME/calibration/calibration-report.json" 2>/dev/null || true)
  echo "  Calibration:     ${TOTAL} records${REGIME:+ — $REGIME}"
else
  echo "  Calibration:     no report yet"
fi
echo ""

# ── Section 5: Data Sources ──
echo "=== Data Sources ==="
SOURCES_FILE="$PLUGIN_ROOT/defaults/sources.yaml"
if [[ -f "$SOURCES_FILE" ]]; then
  RSS_COUNT=$(grep -c '^\s*type: rss' "$SOURCES_FILE" 2>/dev/null || echo 0)
  API_COUNT=$(grep -c '^\s*type: api' "$SOURCES_FILE" 2>/dev/null || echo 0)
  SCRAPE_COUNT=$(grep -c '^\s*type: scrape' "$SOURCES_FILE" 2>/dev/null || echo 0)
  echo "  RSS: $RSS_COUNT  |  API: $API_COUNT  |  Scrape: $SCRAPE_COUNT"
else
  echo "  (sources.yaml not found)"
fi
echo ""

# ── Section 6: Events Dedup ──
# Uses same title_key logic as fetch-rss.sh: lowercase, strip non-alnum, first 80 chars
EVENTS_FILE="$OPC_IR_HOME/events/events.jsonl"
if [[ -f "$EVENTS_FILE" ]]; then
  BEFORE=$(wc -l < "$EVENTS_FILE" | tr -d ' ')
  python3 -c "
import json, sys

def title_key(t):
    return ''.join(c for c in t.lower() if c.isalnum())[:80]

seen_ids = set()
seen_urls = set()
seen_titles = set()
kept = []

with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if not line: continue
        try:
            obj = json.loads(line)
        except Exception:
            kept.append(line)
            continue
        eid = obj.get('id', '')
        url = obj.get('url', '')
        title = obj.get('title', '')
        tk = title_key(title) if title else ''
        if (eid and eid in seen_ids) or (url and url in seen_urls) or (tk and tk in seen_titles):
            continue
        if eid: seen_ids.add(eid)
        if url: seen_urls.add(url)
        if tk: seen_titles.add(tk)
        kept.append(line)

with open(sys.argv[1], 'w') as f:
    f.write('\n'.join(kept) + '\n' if kept else '')
" "$EVENTS_FILE" >/dev/null
  AFTER=$(wc -l < "$EVENTS_FILE" | tr -d ' ')
  REMOVED=$((BEFORE - AFTER))
  if [[ "$REMOVED" -gt 0 ]]; then
    echo "=== Events Dedup ==="
    echo "  Removed $REMOVED duplicate events ($BEFORE → $AFTER)"
    echo ""
  fi
fi

# ── Section 7: Quick Stats ──
echo "=== Quick Stats ==="
EV_COUNT=$(cat "$OPC_IR_HOME/events/"*.jsonl 2>/dev/null | wc -l | tr -d ' ' || echo 0)
THESIS_COUNT=$(find "$OPC_IR_HOME/verdict/theses" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')

echo "  Events:           $EV_COUNT"
echo "  Verdict theses:   $THESIS_COUNT"
echo ""

# ── Section 8: Pending Triggers ──
TRIGGER_FILES=()
while IFS= read -r f; do
  TRIGGER_FILES+=("$f")
done < <(find "$OPC_IR_HOME/triggers" -name "*.trigger" 2>/dev/null | sort)

if [[ ${#TRIGGER_FILES[@]} -gt 0 ]]; then
  echo "=== Pending Triggers (${#TRIGGER_FILES[@]}) ==="
  for tf in "${TRIGGER_FILES[@]}"; do
    TICKER=$(jq -r '.ticker // empty' "$tf" 2>/dev/null || basename "$tf" .trigger)
    DESC=$(jq -r '.description // empty' "$tf" 2>/dev/null)
    if [[ -n "$DESC" ]]; then
      printf "  %-24s %s\n" "$TICKER" "$DESC"
    else
      printf "  %s\n" "$TICKER"
    fi
  done
fi
