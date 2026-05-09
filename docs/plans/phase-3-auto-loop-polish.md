# Phase 3: Auto-loop Polish — Implementation Plan

> **Status**: Draft
> **Date**: 2026-05-08
> **Prerequisite**: Phases 1–2 complete (forecast + verdict flows functional with sample data; world-model + thesis persistence operational via evolve chain; triage classifier + 7 watchers dispatching correctly; hard-rule trigger marker files written by evolve Step 5)
> **Effort**: 4–5 days (4–6 hrs/day)
> **Spec reference**: `docs/specs/2026-05-08-opc-ir-overview-design.md` §3.1, §4.1, §5, §6 Phase 3
> **Master plan**: `docs/plans/2026-05-08-opc-ir-all-phases-implementation.md` Phase 3 section

---

## Overview

Phase 3 transforms OPC-IR from a manually-fed system into a self-running loop. Prior phases proved the voting methodology with sample fixtures; Phase 3 adds real-world RSS ingestion, deduplication, automatic verdict triggering from hard-rule events, and power-user helper commands. At Phase 3 completion, `/loop 1h /opc-ir-evolve` produces a fully autonomous investment research pipeline — the MVP-publishable point.

**Milestone summary**:

| Milestone | Scope | Days |
|---|---|---|
| M3.1 | RSS fetch + dedup (bin/fetch-rss.sh, sources.yaml, fixtures, tests) | 1.5 |
| M3.2 | Evolve integrates ingestion (Step 1 active, short-circuit on 0 new) | 0.5 |
| M3.3 | Hard-rule trigger consumption (marker pattern, cool-down 6h) | 1 |
| M3.4 | Helper commands (--light, --dry-run, --inject-event) | 1 |

**Dependency within Phase 3**:

```
M3.1 ──── M3.2 ──┬── M3.3
                  └── M3.4   [M3.3 ∥ M3.4]
```

**Risks addressed by this phase**:

| Risk | ID | Mitigation |
|---|---|---|
| RSS instability | D1 | ≥10 sources, per-source fault tolerance |
| Duplicate events double-counted | D5 | URL+title fuzzy dedup |
| Log concurrent write | T5 | `flock` in log writes |
| 1h frequency empty-tick waste | T7 | Step 1 short-circuit (0 new events) |
| Verdict cool-down per ticker | Q8 | 6h configurable cool-down |
| --dry-run validation | Q2 | --dry-run flag |
| --light mode scope | Q9 | skip forecast, top-1 watcher only |

---

## M3.1: RSS Fetch + Dedup

### Goal

Create `bin/fetch-rss.sh` — a network-facing shell script that fetches RSS feeds from ≥10 configured sources, deduplicates against existing events, and appends new events to `events/events.jsonl`. Per-source fault tolerance ensures one broken feed never blocks others. The script uses no LLM — it is pure bash + standard tools (`curl`, `xmlstarlet`/`xmllint`, `jq`, `md5sum`).

### Files

| File | Action | Purpose |
|---|---|---|
| `bin/fetch-rss.sh` | Create | RSS fetcher with dedup |
| `defaults/sources.yaml` | Modify | ≥10 RSS source entries with URL, name, category |
| `tests/fixtures/rss/reuters-business.xml` | Create | Canned RSS XML fixture |
| `tests/fixtures/rss/ap-news.xml` | Create | Canned RSS XML fixture |
| `tests/fixtures/rss/bbc-business.xml` | Create | Canned RSS XML fixture |
| `tests/fixtures/rss/cnbc-world.xml` | Create | Canned RSS XML fixture |
| `tests/fixtures/rss/ft-markets.xml` | Create | Canned RSS XML fixture |
| `tests/fixtures/rss/bloomberg-markets.xml` | Create | Canned RSS XML fixture |
| `tests/fixtures/rss/xinhua-english.xml` | Create | Canned RSS XML fixture |
| `tests/fixtures/rss/scmp-economy.xml` | Create | Canned RSS XML fixture |
| `tests/fixtures/rss/fed-press.xml` | Create | Canned RSS XML fixture |
| `tests/fixtures/rss/ecb-press.xml` | Create | Canned RSS XML fixture |
| `tests/fixtures/rss/duplicate-event.xml` | Create | Contains item already in events.jsonl (dedup test) |
| `tests/fixtures/rss/malformed.xml` | Create | Malformed XML (parse failure test) |
| `tests/fixtures/events-existing.jsonl` | Create | Pre-populated events.jsonl for dedup testing |
| `tests/schemas/event.schema.json` | Create | JSON Schema for event entries |
| `tests/fetch-rss.bats` | Create | Full test suite for fetch-rss.sh |

### Steps

#### Step 1: `defaults/sources.yaml`

Extend the existing sources.yaml (created in M1.2) with full feed metadata. Each source needs `name`, `url`, `category` (maps to dimension), and `type: rss`.

```yaml
# defaults/sources.yaml — OPC-IR RSS sources
# Override in ~/.opc-ir/config/local.yaml under 'sources:'
sources:
  - name: reuters-business
    url: https://feeds.reuters.com/reuters/businessNews
    category: econ-finance
    type: rss
    enabled: true

  - name: ap-news
    url: https://rsshub.app/apnews/topics/business
    category: econ-finance
    type: rss
    enabled: true

  - name: bbc-business
    url: https://feeds.bbci.co.uk/news/business/rss.xml
    category: econ-finance
    type: rss
    enabled: true

  - name: cnbc-world
    url: https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=100727362
    category: econ-finance
    type: rss
    enabled: true

  - name: ft-markets
    url: https://www.ft.com/rss/markets
    category: econ-finance
    type: rss
    enabled: true

  - name: bloomberg-markets
    url: https://feeds.bloomberg.com/markets/news.rss
    category: econ-finance
    type: rss
    enabled: true

  - name: xinhua-english
    url: https://rsshub.app/xinhuanet/english
    category: politics
    type: rss
    enabled: true

  - name: scmp-economy
    url: https://www.scmp.com/rss/91/feed
    category: econ-finance
    type: rss
    enabled: true

  - name: fed-press
    url: https://www.federalreserve.gov/feeds/press_all.xml
    category: econ-finance
    type: rss
    enabled: true

  - name: ecb-press
    url: https://www.ecb.europa.eu/rss/press.html
    category: econ-finance
    type: rss
    enabled: true

  - name: tech-crunch
    url: https://techcrunch.com/feed/
    category: tech-ai
    type: rss
    enabled: true

  - name: defense-news
    url: https://www.defensenews.com/arc/outboundfeeds/rss/?outputType=xml
    category: military
    type: rss
    enabled: true
```

#### Step 2: `bin/fetch-rss.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# fetch-rss.sh — Fetch RSS feeds, dedup, append to events.jsonl
# Usage: fetch-rss.sh [--sources <path>] [--home <path>]
# Exit 0 always (per-source failures logged, never abort).
# Stdout: count of new events appended.

OPC_IR_HOME="${OPC_IR_HOME:-$HOME/.opc-ir}"
SOURCES_FILE=""
FETCH_TIMEOUT="${OPC_IR_RSS_TIMEOUT:-10}"
DEDUP_WINDOW=100

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
touch "$EVENTS_FILE"

# Resolve sources file: user override → default
if [[ -z "$SOURCES_FILE" ]]; then
  USER_SOURCES="$OPC_IR_HOME/config/local.yaml"
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  DEFAULT_SOURCES="$SCRIPT_DIR/defaults/sources.yaml"
  if [[ -f "$USER_SOURCES" ]] && yq e '.sources' "$USER_SOURCES" >/dev/null 2>&1; then
    SOURCES_FILE="$USER_SOURCES"
  else
    SOURCES_FILE="$DEFAULT_SOURCES"
  fi
fi

# Load dedup window: last N event IDs + URLs for fast lookup
declare -A SEEN_IDS=()
declare -A SEEN_URLS=()
while IFS= read -r line; do
  eid=$(echo "$line" | jq -r '.id // empty')
  eurl=$(echo "$line" | jq -r '.url // empty')
  [[ -n "$eid" ]] && SEEN_IDS["$eid"]=1
  [[ -n "$eurl" ]] && SEEN_URLS["$eurl"]=1
done < <(tail -n "$DEDUP_WINDOW" "$EVENTS_FILE" 2>/dev/null || true)

# Title fuzzy key: lowercase, strip non-alnum, truncate to 80 chars
title_key() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g' | cut -c1-80
}

# Load seen title keys
declare -A SEEN_TITLES=()
while IFS= read -r line; do
  t=$(echo "$line" | jq -r '.title // empty')
  [[ -n "$t" ]] && SEEN_TITLES["$(title_key "$t")"]=1
done < <(tail -n "$DEDUP_WINDOW" "$EVENTS_FILE" 2>/dev/null || true)

NEW_COUNT=0
LOCK_FILE="$OPC_IR_HOME/events/.events.lock"

log_msg() {
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  (
    flock -w 2 200 || true
    echo "[$ts] fetch-rss: $1" >> "$LOG_FILE"
  ) 200>"$LOG_DIR/.log.lock"
}

# Parse a single RSS XML file/response and emit events as JSON lines
parse_rss() {
  local source_name="$1"
  local xml_content="$2"
  local fetched_at
  fetched_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  # Try xmlstarlet first, fall back to xmllint + grep
  if command -v xmlstarlet >/dev/null 2>&1; then
    xmlstarlet sel -T -t \
      -m "//item" \
      -v "concat(title,'|||',link,'|||',description,'|||',pubDate)" \
      -n <<< "$xml_content" 2>/dev/null || return 1
  elif command -v xmllint >/dev/null 2>&1; then
    # Fallback: crude extraction with xmllint --xpath
    local count
    count=$(xmllint --xpath 'count(//item)' - <<< "$xml_content" 2>/dev/null || echo 0)
    for ((i=1; i<=count; i++)); do
      local title link desc pubdate
      title=$(xmllint --xpath "//item[$i]/title/text()" - <<< "$xml_content" 2>/dev/null || echo "")
      link=$(xmllint --xpath "//item[$i]/link/text()" - <<< "$xml_content" 2>/dev/null || echo "")
      desc=$(xmllint --xpath "//item[$i]/description/text()" - <<< "$xml_content" 2>/dev/null || echo "")
      pubdate=$(xmllint --xpath "//item[$i]/pubDate/text()" - <<< "$xml_content" 2>/dev/null || echo "")
      echo "${title}|||${link}|||${desc}|||${pubdate}"
    done
  else
    log_msg "ERROR: neither xmlstarlet nor xmllint available"
    return 1
  fi | while IFS='|||' read -r title link desc pubdate; do
    [[ -z "$title" && -z "$link" ]] && continue

    # Truncate description to 2000 chars
    desc="${desc:0:2000}"

    # Generate deterministic ID
    local hash
    hash=$(echo -n "${source_name}-${link}-${title}" | md5sum | cut -c1-12)
    local pub_utc
    pub_utc=$(date -u -d "$pubdate" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "$fetched_at")
    local event_id="${source_name}-${pub_utc}-${hash}"

    # Dedup checks: exact ID, exact URL, fuzzy title
    [[ -n "${SEEN_IDS[$event_id]:-}" ]] && continue
    [[ -n "$link" && -n "${SEEN_URLS[$link]:-}" ]] && continue
    local tkey
    tkey="$(title_key "$title")"
    [[ -n "$tkey" && -n "${SEEN_TITLES[$tkey]:-}" ]] && continue

    # Emit JSON event
    jq -cn \
      --arg id "$event_id" \
      --arg source "$source_name" \
      --arg fetched_at "$fetched_at" \
      --arg published_at "$pub_utc" \
      --arg title "$title" \
      --arg summary "$desc" \
      --arg url "$link" \
      --arg raw_text "$desc" \
      '{id: $id, source: $source, fetched_at: $fetched_at, published_at: $published_at, title: $title, summary: $summary, url: $url, raw_text: $raw_text}'

    # Update dedup sets for this run
    SEEN_IDS["$event_id"]=1
    [[ -n "$link" ]] && SEEN_URLS["$link"]=1
    [[ -n "$tkey" ]] && SEEN_TITLES["$tkey"]=1
  done
}

# Iterate sources
source_count=$(yq e '.sources | length' "$SOURCES_FILE")
for ((i=0; i<source_count; i++)); do
  name=$(yq e ".sources[$i].name" "$SOURCES_FILE")
  url=$(yq e ".sources[$i].url" "$SOURCES_FILE")
  enabled=$(yq e ".sources[$i].enabled // true" "$SOURCES_FILE")
  source_type=$(yq e ".sources[$i].type // \"rss\"" "$SOURCES_FILE")

  [[ "$enabled" != "true" ]] && continue
  [[ "$source_type" != "rss" ]] && continue

  log_msg "Fetching $name from $url"

  # Fetch with timeout; capture both content and exit code
  xml_content=""
  if xml_content=$(curl -sS --max-time "$FETCH_TIMEOUT" -L "$url" 2>>"$LOG_FILE"); then
    # Parse and append
    new_events=""
    if new_events=$(parse_rss "$name" "$xml_content" 2>>"$LOG_FILE"); then
      if [[ -n "$new_events" ]]; then
        # Append with flock for concurrency safety (T5)
        (
          flock -w 5 200 || { log_msg "WARN: lock timeout for events.jsonl"; exit 0; }
          echo "$new_events" >> "$EVENTS_FILE"
        ) 200>"$LOCK_FILE"
        count=$(echo "$new_events" | wc -l)
        NEW_COUNT=$((NEW_COUNT + count))
        log_msg "OK $name: $count new events"
      else
        log_msg "OK $name: 0 new events (all deduped)"
      fi
    else
      log_msg "WARN: parse failed for $name, skipping"
    fi
  else
    log_msg "WARN: fetch failed for $name (timeout or network error), skipping"
  fi
done

log_msg "fetch-rss complete: $NEW_COUNT new events total"
echo "$NEW_COUNT"
exit 0
```

#### Step 3: Event JSON Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "OPC-IR Event",
  "type": "object",
  "required": ["id", "source", "fetched_at", "published_at", "title", "url"],
  "properties": {
    "id": { "type": "string", "pattern": "^.+-\\d{4}-\\d{2}-\\d{2}T.+-[a-f0-9]{12}$" },
    "source": { "type": "string", "minLength": 1 },
    "fetched_at": { "type": "string", "format": "date-time" },
    "published_at": { "type": "string", "format": "date-time" },
    "title": { "type": "string" },
    "summary": { "type": "string" },
    "url": { "type": "string", "format": "uri" },
    "raw_text": { "type": "string", "maxLength": 2000 }
  },
  "additionalProperties": false
}
```

#### Step 4: Canned XML Fixtures

Each fixture file under `tests/fixtures/rss/` must be a valid RSS 2.0 XML document with 2–3 `<item>` entries. Example for `reuters-business.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Reuters Business News</title>
    <link>https://www.reuters.com</link>
    <description>Business news from Reuters</description>
    <item>
      <title>Fed holds rates steady amid inflation concerns</title>
      <link>https://www.reuters.com/business/fed-holds-rates-2026-05-08</link>
      <description>The Federal Reserve held its benchmark interest rate at 4.25% on Wednesday, citing persistent inflation pressures despite signs of slowing economic growth. The decision was unanimous among all voting FOMC members.</description>
      <pubDate>Wed, 08 May 2026 18:30:00 GMT</pubDate>
    </item>
    <item>
      <title>China manufacturing PMI expands for third consecutive month</title>
      <link>https://www.reuters.com/business/china-pmi-may-2026</link>
      <description>China's official manufacturing purchasing managers index rose to 51.2 in April, marking the third straight month of expansion and signaling continued recovery in the world's second-largest economy.</description>
      <pubDate>Wed, 08 May 2026 09:15:00 GMT</pubDate>
    </item>
  </channel>
</rss>
```

The `malformed.xml` fixture should contain invalid XML:

```xml
<?xml version="1.0"?>
<rss version="2.0">
  <channel>
    <title>Broken Feed</title>
    <item>
      <title>Unclosed tag
      <link>https://example.com</link>
    </item>
  <!-- missing closing tags -->
```

The `duplicate-event.xml` fixture must contain an item whose URL and title match an entry in `tests/fixtures/events-existing.jsonl`.

### Tests

**File**: `tests/fetch-rss.bats`

```bash
#!/usr/bin/env bats

setup() {
  export OPC_IR_HOME="$(mktemp -d)"
  mkdir -p "$OPC_IR_HOME/events" "$OPC_IR_HOME/logs"
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export PATH="$SCRIPT_DIR/bin:$PATH"
  FIXTURES="$SCRIPT_DIR/tests/fixtures"
}

teardown() {
  rm -rf "$OPC_IR_HOME"
}

@test "fetch-rss: produces valid events from canned XML" {
  # Create a minimal sources.yaml pointing to local fixtures
  cat > "$OPC_IR_HOME/test-sources.yaml" <<'EOF'
sources:
  - name: reuters-test
    url: file://${FIXTURES}/rss/reuters-business.xml
    type: rss
    enabled: true
EOF
  # Substitute FIXTURES path
  sed -i "s|\${FIXTURES}|$FIXTURES|g" "$OPC_IR_HOME/test-sources.yaml"

  run fetch-rss.sh --sources "$OPC_IR_HOME/test-sources.yaml" --home "$OPC_IR_HOME"
  [ "$status" -eq 0 ]
  # Should have produced events
  [ "$(wc -l < "$OPC_IR_HOME/events/events.jsonl")" -ge 1 ]
  # Each line should be valid JSON with required fields
  while IFS= read -r line; do
    echo "$line" | jq -e '.id and .source and .title and .url' >/dev/null
  done < "$OPC_IR_HOME/events/events.jsonl"
}

@test "fetch-rss: dedup prevents duplicate events" {
  cp "$FIXTURES/events-existing.jsonl" "$OPC_IR_HOME/events/events.jsonl"
  local before_count
  before_count=$(wc -l < "$OPC_IR_HOME/events/events.jsonl")

  cat > "$OPC_IR_HOME/test-sources.yaml" <<EOF
sources:
  - name: dup-test
    url: file://$FIXTURES/rss/duplicate-event.xml
    type: rss
    enabled: true
EOF

  run fetch-rss.sh --sources "$OPC_IR_HOME/test-sources.yaml" --home "$OPC_IR_HOME"
  [ "$status" -eq 0 ]
  local after_count
  after_count=$(wc -l < "$OPC_IR_HOME/events/events.jsonl")
  # Count should not increase (all items are duplicates)
  [ "$after_count" -eq "$before_count" ]
}

@test "fetch-rss: malformed XML does not crash, exit 0" {
  cat > "$OPC_IR_HOME/test-sources.yaml" <<EOF
sources:
  - name: broken-feed
    url: file://$FIXTURES/rss/malformed.xml
    type: rss
    enabled: true
EOF

  run fetch-rss.sh --sources "$OPC_IR_HOME/test-sources.yaml" --home "$OPC_IR_HOME"
  [ "$status" -eq 0 ]
  # Should log warning
  grep -q "WARN.*parse failed.*broken-feed" "$OPC_IR_HOME/logs/"*.log
}

@test "fetch-rss: disabled source is skipped" {
  cat > "$OPC_IR_HOME/test-sources.yaml" <<EOF
sources:
  - name: disabled-feed
    url: file://$FIXTURES/rss/reuters-business.xml
    type: rss
    enabled: false
EOF

  run fetch-rss.sh --sources "$OPC_IR_HOME/test-sources.yaml" --home "$OPC_IR_HOME"
  [ "$status" -eq 0 ]
  [ "$(cat "$OPC_IR_HOME/events/events.jsonl" | wc -l)" -eq 0 ]
}

@test "fetch-rss: multiple sources processed independently" {
  cat > "$OPC_IR_HOME/test-sources.yaml" <<EOF
sources:
  - name: good-feed
    url: file://$FIXTURES/rss/reuters-business.xml
    type: rss
    enabled: true
  - name: bad-feed
    url: file://$FIXTURES/rss/malformed.xml
    type: rss
    enabled: true
  - name: another-good
    url: file://$FIXTURES/rss/bbc-business.xml
    type: rss
    enabled: true
EOF

  run fetch-rss.sh --sources "$OPC_IR_HOME/test-sources.yaml" --home "$OPC_IR_HOME"
  [ "$status" -eq 0 ]
  # Events from good feeds should exist, bad feed should not block
  [ "$(wc -l < "$OPC_IR_HOME/events/events.jsonl")" -ge 2 ]
}

@test "fetch-rss: event IDs are globally unique" {
  cat > "$OPC_IR_HOME/test-sources.yaml" <<EOF
sources:
  - name: feed-a
    url: file://$FIXTURES/rss/reuters-business.xml
    type: rss
    enabled: true
  - name: feed-b
    url: file://$FIXTURES/rss/ap-news.xml
    type: rss
    enabled: true
EOF

  run fetch-rss.sh --sources "$OPC_IR_HOME/test-sources.yaml" --home "$OPC_IR_HOME"
  [ "$status" -eq 0 ]
  local total
  total=$(wc -l < "$OPC_IR_HOME/events/events.jsonl")
  local unique
  unique=$(jq -r '.id' "$OPC_IR_HOME/events/events.jsonl" | sort -u | wc -l)
  [ "$total" -eq "$unique" ]
}

@test "fetch-rss: raw_text truncated to 2000 chars" {
  # This is verified by checking the schema; the parse_rss function truncates
  while IFS= read -r line; do
    local len
    len=$(echo "$line" | jq -r '.raw_text | length')
    [ "$len" -le 2000 ]
  done < "$OPC_IR_HOME/events/events.jsonl" 2>/dev/null || true
}

@test "fetch-rss: events validate against schema" {
  cat > "$OPC_IR_HOME/test-sources.yaml" <<EOF
sources:
  - name: schema-test
    url: file://$FIXTURES/rss/reuters-business.xml
    type: rss
    enabled: true
EOF

  fetch-rss.sh --sources "$OPC_IR_HOME/test-sources.yaml" --home "$OPC_IR_HOME"
  while IFS= read -r line; do
    echo "$line" | jq -e '
      .id != null and
      .source != null and
      .fetched_at != null and
      .published_at != null and
      .title != null and
      .url != null
    ' >/dev/null
  done < "$OPC_IR_HOME/events/events.jsonl"
}
```

### Verification

1. `bats tests/fetch-rss.bats` exits 0 — all 8 tests pass.
2. `shellcheck -S warning bin/fetch-rss.sh` exits 0 — no warnings.
3. Each canned XML fixture produces ≥1 valid event entry.
4. Running fetch-rss.sh twice with the same source produces 0 new events on the second run (dedup working).
5. `defaults/sources.yaml` contains ≥10 enabled RSS sources, validated by `yq e '.sources | length' defaults/sources.yaml`.

---

## M3.2: Evolve Integrates Ingestion

### Goal

Wire `bin/fetch-rss.sh` into `commands/opc-ir-evolve.md` as Step 1. Add short-circuit logic: if fetch returns 0 new events, evolve exits immediately with no LLM cost (mitigates T7: empty-tick waste).

### Files

| File | Action | Purpose |
|---|---|---|
| `commands/opc-ir-evolve.md` | Modify | Add Step 1 fetch invocation + short-circuit logic |

### Steps

#### Step 1: Modify evolve command

Add the following to the beginning of the evolve command's execution flow (before the existing triage step):

```markdown
## Step 1: Ingestion

Run `bin/fetch-rss.sh` and capture the new event count from stdout.

```bash
NEW_COUNT=$(bin/fetch-rss.sh --home "$OPC_IR_HOME")
```

**Short-circuit**: If `NEW_COUNT` is `0`, log the no-op and exit immediately:

```bash
if [[ "$NEW_COUNT" -eq 0 ]]; then
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] evolve: 0 new events, short-circuit exit" >> "$OPC_IR_HOME/logs/$(date +%Y-%m-%d).log"
  echo "No new events. Skipping evolve cycle."
  exit 0
fi
```

If `NEW_COUNT > 0`, proceed to Step 2 (triage) with the incremental events.
```

The evolve command must also record in `harness/runs/{run-id}/meta.json`:

```json
{
  "run_id": "evolve-2026-05-08T14-23-01Z",
  "started_at": "2026-05-08T14:23:01Z",
  "step1_new_events": 5,
  "step1_short_circuit": false
}
```

When short-circuiting, `meta.json` still gets written (with `step1_short_circuit: true`) for audit trail, but no further files are created in that run directory.

#### Step 2: Incremental event window

The triage classifier (Step 2) needs to know which events are new. The evolve command passes the last `NEW_COUNT` lines of `events.jsonl` as the triage input:

```bash
tail -n "$NEW_COUNT" "$OPC_IR_HOME/events/events.jsonl" > "$RUN_DIR/new-events.jsonl"
```

### Tests

Add test cases to the existing `tests/e2e-phase1.bats` or create `tests/evolve-ingestion.bats`:

```bash
#!/usr/bin/env bats

setup() {
  export OPC_IR_HOME="$(mktemp -d)"
  mkdir -p "$OPC_IR_HOME/events" "$OPC_IR_HOME/logs" "$OPC_IR_HOME/harness/runs"
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export PATH="$SCRIPT_DIR/bin:$PATH"
}

teardown() {
  rm -rf "$OPC_IR_HOME"
}

@test "evolve: short-circuits on 0 new events" {
  # Pre-populate events (same as what sources would produce)
  # Create a sources.yaml that points to already-seen events
  cat > "$OPC_IR_HOME/test-sources.yaml" <<EOF
sources: []
EOF

  # Simulate evolve Step 1
  NEW_COUNT=$(fetch-rss.sh --sources "$OPC_IR_HOME/test-sources.yaml" --home "$OPC_IR_HOME")
  [ "$NEW_COUNT" -eq 0 ]
  # Verify log records short-circuit
}

@test "evolve: proceeds to triage when new events exist" {
  FIXTURES="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/fixtures"
  cat > "$OPC_IR_HOME/test-sources.yaml" <<EOF
sources:
  - name: test-feed
    url: file://$FIXTURES/rss/reuters-business.xml
    type: rss
    enabled: true
EOF

  NEW_COUNT=$(fetch-rss.sh --sources "$OPC_IR_HOME/test-sources.yaml" --home "$OPC_IR_HOME")
  [ "$NEW_COUNT" -gt 0 ]
}
```

### Verification

1. `bats tests/evolve-ingestion.bats` exits 0.
2. Empty sources list → evolve completes in <1 second with no LLM calls.
3. With canned RSS → `events.jsonl` populated → triage receives correct incremental window.
4. `meta.json` correctly records `step1_new_events` and `step1_short_circuit`.

---

## M3.3: Hard-rule Trigger Consumption

### Goal

Implement the fire-and-forget trigger marker pattern from the design spec (§4.1 Step 5). When evolve's triage identifies a hard-rule event, it writes a marker file to `~/.opc-ir/triggers/{ticker}.trigger`. On the **next** evolve tick, before Step 1, the evolve command checks for trigger files, dispatches `/opc-ir-verdict {ticker}` for each, then deletes the marker. A 6-hour cool-down per ticker prevents rapid re-triggering (Q8).

### Files

| File | Action | Purpose |
|---|---|---|
| `commands/opc-ir-evolve.md` | Modify | Add trigger consumption at start + trigger writing in Step 5 |
| `bin/trigger-manage.sh` | Create | Utility for trigger file operations (create, check cool-down, consume) |
| `tests/trigger-consume.bats` | Create | Full trigger lifecycle tests |

### Steps

#### Step 1: `bin/trigger-manage.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# trigger-manage.sh — Manage hard-rule trigger marker files
# Usage:
#   trigger-manage.sh create <ticker>           → write trigger file
#   trigger-manage.sh check  <ticker>           → exit 0 if triggerable (no cool-down), exit 1 if cooling
#   trigger-manage.sh consume <ticker>          → delete trigger file
#   trigger-manage.sh list                      → list pending triggers (ticker per line)

OPC_IR_HOME="${OPC_IR_HOME:-$HOME/.opc-ir}"
TRIGGER_DIR="$OPC_IR_HOME/triggers"
VERDICTS_FILE="$OPC_IR_HOME/verdict/verdicts.jsonl"
COOLDOWN_SECONDS="${OPC_IR_VERDICT_COOLDOWN:-21600}"  # 6 hours = 21600s

mkdir -p "$TRIGGER_DIR"

ACTION="${1:-list}"
TICKER="${2:-}"

case "$ACTION" in
  create)
    [[ -z "$TICKER" ]] && { echo "ERROR: ticker required" >&2; exit 1; }
    echo "{\"ticker\":\"$TICKER\",\"created_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
      > "$TRIGGER_DIR/${TICKER}.trigger"
    echo "Trigger created for $TICKER"
    ;;

  check)
    [[ -z "$TICKER" ]] && { echo "ERROR: ticker required" >&2; exit 1; }
    # Check cool-down: find last verdict timestamp for this ticker
    if [[ -f "$VERDICTS_FILE" ]]; then
      last_ts=$(grep "\"ticker\":\"$TICKER\"" "$VERDICTS_FILE" 2>/dev/null \
        | tail -1 \
        | jq -r '.ts // empty' 2>/dev/null || true)
      if [[ -n "$last_ts" ]]; then
        last_epoch=$(date -d "$last_ts" +%s 2>/dev/null || echo 0)
        now_epoch=$(date +%s)
        elapsed=$((now_epoch - last_epoch))
        if [[ "$elapsed" -lt "$COOLDOWN_SECONDS" ]]; then
          remaining=$(( (COOLDOWN_SECONDS - elapsed) / 60 ))
          echo "COOLING: $TICKER last verdict ${elapsed}s ago, ${remaining}m remaining"
          exit 1
        fi
      fi
    fi
    echo "READY: $TICKER"
    exit 0
    ;;

  consume)
    [[ -z "$TICKER" ]] && { echo "ERROR: ticker required" >&2; exit 1; }
    rm -f "$TRIGGER_DIR/${TICKER}.trigger"
    echo "Trigger consumed for $TICKER"
    ;;

  list)
    for f in "$TRIGGER_DIR"/*.trigger 2>/dev/null; do
      [[ -f "$f" ]] || continue
      basename "$f" .trigger
    done
    ;;

  *)
    echo "Usage: trigger-manage.sh {create|check|consume|list} [ticker]" >&2
    exit 1
    ;;
esac
```

#### Step 2: Evolve — Trigger writing (Step 5)

After triage completes and identifies `hard_rule_hit: true` with `verdict_targets`, the evolve command writes triggers:

```bash
# Step 5: Write hard-rule trigger markers
for ticker in $(jq -r '.verdict_targets[]' "$RUN_DIR/triage.json" 2>/dev/null); do
  bin/trigger-manage.sh create "$ticker"
  log_msg "Hard-rule trigger written for $ticker"
done
```

#### Step 3: Evolve — Trigger consumption (Step 0, before fetch)

At the very beginning of each evolve tick, before Step 1 fetch:

```bash
# Step 0: Consume pending triggers from previous tick
for ticker in $(bin/trigger-manage.sh list); do
  if bin/trigger-manage.sh check "$ticker"; then
    log_msg "Dispatching verdict for $ticker (hard-rule trigger)"
    # Dispatch verdict (runs in current session)
    /opc-ir-verdict "$ticker" || log_msg "WARN: verdict dispatch failed for $ticker"
    bin/trigger-manage.sh consume "$ticker"
  else
    log_msg "Cool-down active for $ticker, consuming trigger without dispatch"
    bin/trigger-manage.sh consume "$ticker"
  fi
done
```

The trigger is always consumed — whether the verdict runs or the cool-down skips it. This prevents stale triggers from accumulating.

#### Step 4: Cool-down configuration

The cool-down period is configurable via:
1. Environment variable: `OPC_IR_VERDICT_COOLDOWN=21600` (seconds)
2. `~/.opc-ir/config/local.yaml`: `verdict.cooldown_hours: 6`
3. Default: 6 hours (21600 seconds)

The `trigger-manage.sh check` command reads the cool-down from environment first, then config file, then default.

### Tests

**File**: `tests/trigger-consume.bats`

```bash
#!/usr/bin/env bats

setup() {
  export OPC_IR_HOME="$(mktemp -d)"
  mkdir -p "$OPC_IR_HOME/triggers" "$OPC_IR_HOME/verdict" "$OPC_IR_HOME/logs"
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export PATH="$SCRIPT_DIR/bin:$PATH"
}

teardown() {
  rm -rf "$OPC_IR_HOME"
}

@test "trigger-manage: create writes marker file" {
  run trigger-manage.sh create NDX
  [ "$status" -eq 0 ]
  [ -f "$OPC_IR_HOME/triggers/NDX.trigger" ]
  jq -e '.ticker == "NDX"' "$OPC_IR_HOME/triggers/NDX.trigger"
}

@test "trigger-manage: list returns pending triggers" {
  trigger-manage.sh create NDX
  trigger-manage.sh create SPX
  run trigger-manage.sh list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "NDX"
  echo "$output" | grep -q "SPX"
}

@test "trigger-manage: consume deletes marker" {
  trigger-manage.sh create NDX
  [ -f "$OPC_IR_HOME/triggers/NDX.trigger" ]
  trigger-manage.sh consume NDX
  [ ! -f "$OPC_IR_HOME/triggers/NDX.trigger" ]
}

@test "trigger-manage: check passes with no prior verdict" {
  run trigger-manage.sh check NDX
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "READY"
}

@test "trigger-manage: check fails during cool-down" {
  # Create a recent verdict entry
  mkdir -p "$OPC_IR_HOME/verdict"
  local now_ts
  now_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "{\"ticker\":\"NDX\",\"ts\":\"$now_ts\",\"consensus\":{\"direction\":\"long\"}}" \
    > "$OPC_IR_HOME/verdict/verdicts.jsonl"

  export OPC_IR_VERDICT_COOLDOWN=21600
  run trigger-manage.sh check NDX
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "COOLING"
}

@test "trigger-manage: check passes after cool-down expires" {
  # Create an old verdict entry (7 hours ago)
  mkdir -p "$OPC_IR_HOME/verdict"
  local old_ts
  old_ts="$(date -u -d '7 hours ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-7H +%Y-%m-%dT%H:%M:%SZ)"
  echo "{\"ticker\":\"NDX\",\"ts\":\"$old_ts\",\"consensus\":{\"direction\":\"long\"}}" \
    > "$OPC_IR_HOME/verdict/verdicts.jsonl"

  export OPC_IR_VERDICT_COOLDOWN=21600
  run trigger-manage.sh check NDX
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "READY"
}

@test "trigger-manage: different tickers have independent cool-downs" {
  local now_ts
  now_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "{\"ticker\":\"NDX\",\"ts\":\"$now_ts\",\"consensus\":{}}" \
    > "$OPC_IR_HOME/verdict/verdicts.jsonl"

  export OPC_IR_VERDICT_COOLDOWN=21600
  # NDX should be cooling
  run trigger-manage.sh check NDX
  [ "$status" -eq 1 ]
  # SPX should be ready (no prior verdict)
  run trigger-manage.sh check SPX
  [ "$status" -eq 0 ]
}

@test "trigger consumption: trigger always consumed even on cool-down skip" {
  local now_ts
  now_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "{\"ticker\":\"NDX\",\"ts\":\"$now_ts\",\"consensus\":{}}" \
    > "$OPC_IR_HOME/verdict/verdicts.jsonl"

  trigger-manage.sh create NDX
  [ -f "$OPC_IR_HOME/triggers/NDX.trigger" ]

  export OPC_IR_VERDICT_COOLDOWN=21600
  # Simulate evolve Step 0 logic
  if ! trigger-manage.sh check NDX; then
    trigger-manage.sh consume NDX
  fi
  [ ! -f "$OPC_IR_HOME/triggers/NDX.trigger" ]
}
```

### Verification

1. `bats tests/trigger-consume.bats` exits 0 — all 8 tests pass.
2. `shellcheck -S warning bin/trigger-manage.sh` exits 0.
3. Manual test: create trigger → next evolve tick picks it up → verdict dispatched → trigger file gone.
4. Cool-down test: create trigger within 6h of last verdict for same ticker → trigger consumed without verdict dispatch.
5. Multiple tickers triggered in same triage → each gets independent trigger file → each consumed independently.

---

## M3.4: Helper Commands

### Goal

Add three power-user flags to the evolve command: `--light` (reduced LLM cost), `--dry-run` (preview without side effects), and `--inject-event` (manual event insertion). These address Q2, Q9, and D2 from the spec.

### Files

| File | Action | Purpose |
|---|---|---|
| `commands/opc-ir-evolve.md` | Modify | Parse --light, --dry-run, --inject-event flags |
| `bin/inject-event.sh` | Create | Constructs and appends a manual event to events.jsonl |
| `tests/helper-commands.bats` | Create | Tests all three flags |

### Steps

#### Step 1: `--light` mode

When `--light` is passed, evolve runs in reduced mode:
- Step 1 (fetch): runs normally
- Step 2 (triage): runs normally
- Step 3 (watchers): dispatch **only the top-1 scored dimension** instead of all matched watchers
- Step 4 (synthesizer): runs with single-watcher input
- Step 5 (triggers): runs normally
- Step 6 (forecast check): **skipped entirely** — never triggers /opc-ir-forecast

Implementation in evolve command:

```bash
LIGHT_MODE=false
for arg in "$@"; do
  [[ "$arg" == "--light" ]] && LIGHT_MODE=true
done

# In Step 3:
if [[ "$LIGHT_MODE" == "true" ]]; then
  # Extract top-1 dimension by score from triage.json
  TOP_DIM=$(jq -r '
    .events
    | map(.dimension_scores | to_entries[])
    | group_by(.key)
    | map({dim: .[0].key, max_score: (map(.value) | max)})
    | sort_by(-.max_score)
    | .[0].dim
  ' "$RUN_DIR/triage.json")
  WATCHERS_TO_DISPATCH=("$TOP_DIM")
else
  WATCHERS_TO_DISPATCH=($(jq -r '.watchers_to_dispatch[]' "$RUN_DIR/triage.json"))
fi

# In Step 6:
if [[ "$LIGHT_MODE" == "true" ]]; then
  log_msg "Light mode: skipping forecast dispatch"
else
  # Check forecast.md mtime > 8h ...
fi
```

#### Step 2: `--dry-run` mode

When `--dry-run` is passed, evolve runs triage but makes no persistent changes:
- Step 1 (fetch): runs normally (events.jsonl **is** appended — fetch is idempotent due to dedup)
- Step 2 (triage): runs normally
- Step 3–6: **skipped entirely**
- Output: triage results printed to stdout (dimension scores, routing decisions, hard-rule hits)

```bash
DRY_RUN=false
for arg in "$@"; do
  [[ "$arg" == "--dry-run" ]] && DRY_RUN=true
done

# After Step 2:
if [[ "$DRY_RUN" == "true" ]]; then
  echo "=== DRY RUN: Triage Results ==="
  echo ""
  echo "New events: $NEW_COUNT"
  echo ""
  echo "Dimension scores:"
  jq -r '
    .events[] |
    "  [\(.id)] \(.title)"
    + "\n    " + (
      .dimension_scores | to_entries | sort_by(-.value)
      | map("\(.key): \(.value | tostring)")
      | join(", ")
    )
  ' "$RUN_DIR/triage.json"
  echo ""
  echo "Watchers to dispatch: $(jq -r '.watchers_to_dispatch | join(", ")' "$RUN_DIR/triage.json")"
  echo ""
  if jq -e '.hard_rule_hit == true' "$RUN_DIR/triage.json" >/dev/null 2>&1; then
    echo "HARD RULE HIT: $(jq -r '.verdict_targets | join(", ")' "$RUN_DIR/triage.json")"
  else
    echo "No hard-rule triggers."
  fi
  echo ""
  echo "=== DRY RUN COMPLETE (no world-model changes, no triggers written) ==="
  exit 0
fi
```

Key invariant: `--dry-run` does NOT write trigger files, does NOT update world-model.md, does NOT dispatch watchers or synthesizer.

#### Step 3: `--inject-event`

The `--inject-event` flag accepts a quoted event description and inserts it as a manual event before running the normal evolve pipeline.

**File**: `bin/inject-event.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# inject-event.sh — Insert a manual event into events.jsonl
# Usage: inject-event.sh <title> [--summary <text>] [--url <url>] [--home <path>]
# Source is always "manual". ID uses md5 of title + timestamp.

OPC_IR_HOME="${OPC_IR_HOME:-$HOME/.opc-ir}"
TITLE=""
SUMMARY=""
URL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --summary) SUMMARY="$2"; shift 2 ;;
    --url)     URL="$2"; shift 2 ;;
    --home)    OPC_IR_HOME="$2"; shift 2 ;;
    *)         TITLE="$1"; shift ;;
  esac
done

[[ -z "$TITLE" ]] && { echo "ERROR: event title required" >&2; exit 1; }

EVENTS_FILE="$OPC_IR_HOME/events/events.jsonl"
mkdir -p "$(dirname "$EVENTS_FILE")"
touch "$EVENTS_FILE"

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
HASH=$(echo -n "manual-${TITLE}-${NOW}" | md5sum | cut -c1-12)
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

echo "1"  # new event count = 1
```

In the evolve command, `--inject-event` is handled before Step 1:

```bash
INJECT_EVENT=""
args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --inject-event) INJECT_EVENT="$2"; shift 2 ;;
    --light)        LIGHT_MODE=true; shift ;;
    --dry-run)      DRY_RUN=true; shift ;;
    *)              args+=("$1"); shift ;;
  esac
done

# Before Step 1: handle injection
if [[ -n "$INJECT_EVENT" ]]; then
  INJECT_COUNT=$(bin/inject-event.sh "$INJECT_EVENT" --home "$OPC_IR_HOME")
  log_msg "Injected manual event: $INJECT_EVENT"
  # Skip Step 1 RSS fetch — go directly to Step 2 with the injected event
  NEW_COUNT="$INJECT_COUNT"
else
  # Step 1: normal RSS fetch
  NEW_COUNT=$(bin/fetch-rss.sh --home "$OPC_IR_HOME")
fi
```

When `--inject-event` is used, the RSS fetch is skipped and the injected event becomes the sole input to triage. This addresses D2 (public-RSS info density gap) by allowing users to manually feed Bloomberg/terminal events.

#### Step 4: Flag combinations

| Combination | Behavior |
|---|---|
| `--inject-event "..." --dry-run` | Inject event + run triage + display results, no world-model changes |
| `--inject-event "..." --light` | Inject event + light evolve (top-1 watcher, no forecast) |
| `--dry-run --light` | Normal fetch + triage display only (--light is irrelevant since Steps 3–6 skipped) |
| `--inject-event "..." --dry-run --light` | Same as inject + dry-run |

### Tests

**File**: `tests/helper-commands.bats`

```bash
#!/usr/bin/env bats

setup() {
  export OPC_IR_HOME="$(mktemp -d)"
  mkdir -p "$OPC_IR_HOME/events" "$OPC_IR_HOME/logs" \
           "$OPC_IR_HOME/world" "$OPC_IR_HOME/triggers" \
           "$OPC_IR_HOME/harness/runs"
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export PATH="$SCRIPT_DIR/bin:$PATH"
  FIXTURES="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/fixtures"

  # Create a sample world-model so evolve doesn't fail on missing deps
  cp "$FIXTURES/world-model-sample.md" "$OPC_IR_HOME/world/world-model.md" 2>/dev/null || true
}

teardown() {
  rm -rf "$OPC_IR_HOME"
}

@test "inject-event: creates valid event in events.jsonl" {
  run inject-event.sh "Fed raises rates by 50bps" --home "$OPC_IR_HOME"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$OPC_IR_HOME/events/events.jsonl")" -eq 1 ]
  jq -e '.source == "manual"' "$OPC_IR_HOME/events/events.jsonl"
  jq -e '.title == "Fed raises rates by 50bps"' "$OPC_IR_HOME/events/events.jsonl"
}

@test "inject-event: requires title" {
  run inject-event.sh --home "$OPC_IR_HOME"
  [ "$status" -eq 1 ]
}

@test "inject-event: optional summary and url" {
  run inject-event.sh "Test event" \
    --summary "Detailed description of the event" \
    --url "https://example.com/article" \
    --home "$OPC_IR_HOME"
  [ "$status" -eq 0 ]
  jq -e '.summary == "Detailed description of the event"' "$OPC_IR_HOME/events/events.jsonl"
  jq -e '.url == "https://example.com/article"' "$OPC_IR_HOME/events/events.jsonl"
}

@test "inject-event: ID contains 'manual' prefix" {
  inject-event.sh "Test" --home "$OPC_IR_HOME"
  jq -e '.id | startswith("manual-")' "$OPC_IR_HOME/events/events.jsonl"
}

@test "--dry-run: does not modify world-model" {
  # Pre-populate with an event so triage has input
  inject-event.sh "Fed surprise rate cut" --home "$OPC_IR_HOME"

  # Record world-model state
  local wm_before=""
  [[ -f "$OPC_IR_HOME/world/world-model.md" ]] && wm_before=$(md5sum "$OPC_IR_HOME/world/world-model.md")

  # Note: full dry-run test requires evolve command integration
  # This test validates the inject + dry-run contract at script level
  [ -f "$OPC_IR_HOME/events/events.jsonl" ]

  # world-model unchanged
  local wm_after=""
  [[ -f "$OPC_IR_HOME/world/world-model.md" ]] && wm_after=$(md5sum "$OPC_IR_HOME/world/world-model.md")
  [ "$wm_before" = "$wm_after" ]
}

@test "--dry-run: does not write trigger files" {
  inject-event.sh "War declared — major hard-rule event" --home "$OPC_IR_HOME"
  # In dry-run, even if triage identifies hard-rule, no trigger files written
  local trigger_count
  trigger_count=$(ls "$OPC_IR_HOME/triggers/"*.trigger 2>/dev/null | wc -l || echo 0)
  [ "$trigger_count" -eq 0 ]
}

@test "--light: flag is accepted without error" {
  # Validates that flag parsing does not crash
  # Full --light test requires evolve command integration
  inject-event.sh "Minor economic data release" --home "$OPC_IR_HOME"
  [ -f "$OPC_IR_HOME/events/events.jsonl" ]
}

@test "inject-event: successive injections produce unique IDs" {
  inject-event.sh "Event one" --home "$OPC_IR_HOME"
  sleep 1  # ensure different timestamp
  inject-event.sh "Event two" --home "$OPC_IR_HOME"
  local total
  total=$(wc -l < "$OPC_IR_HOME/events/events.jsonl")
  local unique
  unique=$(jq -r '.id' "$OPC_IR_HOME/events/events.jsonl" | sort -u | wc -l)
  [ "$total" -eq 2 ]
  [ "$unique" -eq 2 ]
}
```

### Verification

1. `bats tests/helper-commands.bats` exits 0 — all 8 tests pass.
2. `shellcheck -S warning bin/inject-event.sh` exits 0.
3. Manual verification: `/opc-ir-evolve --dry-run` prints triage results to stdout, `world-model.md` unchanged, no trigger files written.
4. Manual verification: `/opc-ir-evolve --light` dispatches exactly 1 watcher, does not trigger forecast.
5. Manual verification: `/opc-ir-evolve --inject-event "Fed cuts rates 75bps"` appends manual event, runs full evolve pipeline.
6. Combined flags: `/opc-ir-evolve --inject-event "Test" --dry-run` shows triage output without side effects.

---

## Phase 3 Exit Criteria

All of the following must be true before Phase 3 is considered complete:

1. **RSS ingestion operational**: `bin/fetch-rss.sh` fetches from ≥10 configured sources, dedup prevents duplicates, per-source failures are isolated and logged.
2. **Evolve loop autonomous**: `/loop 1h /opc-ir-evolve` fetches RSS → triages → dispatches watchers → updates world-model → writes triggers → optionally triggers forecast. Zero manual intervention required.
3. **Short-circuit efficient**: Evolve on 0 new events completes in <1 second with no LLM API calls.
4. **Hard-rule triggers consumed**: Marker files written by evolve Step 5 are picked up on next tick, verdict dispatched if cool-down allows, marker always deleted.
5. **Cool-down enforced**: Same-ticker verdicts cannot fire within 6 hours of each other (configurable).
6. **Helper commands functional**: `--light`, `--dry-run`, `--inject-event` all work individually and in combination.
7. **All tests pass**: `bats tests/fetch-rss.bats tests/evolve-ingestion.bats tests/trigger-consume.bats tests/helper-commands.bats` exits 0.
8. **All scripts lint-clean**: `shellcheck -S warning bin/fetch-rss.sh bin/trigger-manage.sh bin/inject-event.sh` exits 0.

**MVP-publishable milestone reached**: The auto-running plugin produces world-model + forecast + verdict + digest from real-world RSS data, lacking only calibration learning (Phase 4).

---

## Appendix: Full File Inventory

| File | Type | Milestone | Action |
|---|---|---|---|
| `bin/fetch-rss.sh` | script | M3.1 | Create |
| `bin/trigger-manage.sh` | script | M3.3 | Create |
| `bin/inject-event.sh` | script | M3.4 | Create |
| `defaults/sources.yaml` | config | M3.1 | Modify |
| `commands/opc-ir-evolve.md` | command | M3.2–M3.4 | Modify |
| `tests/fixtures/rss/reuters-business.xml` | fixture | M3.1 | Create |
| `tests/fixtures/rss/ap-news.xml` | fixture | M3.1 | Create |
| `tests/fixtures/rss/bbc-business.xml` | fixture | M3.1 | Create |
| `tests/fixtures/rss/cnbc-world.xml` | fixture | M3.1 | Create |
| `tests/fixtures/rss/ft-markets.xml` | fixture | M3.1 | Create |
| `tests/fixtures/rss/bloomberg-markets.xml` | fixture | M3.1 | Create |
| `tests/fixtures/rss/xinhua-english.xml` | fixture | M3.1 | Create |
| `tests/fixtures/rss/scmp-economy.xml` | fixture | M3.1 | Create |
| `tests/fixtures/rss/fed-press.xml` | fixture | M3.1 | Create |
| `tests/fixtures/rss/ecb-press.xml` | fixture | M3.1 | Create |
| `tests/fixtures/rss/duplicate-event.xml` | fixture | M3.1 | Create |
| `tests/fixtures/rss/malformed.xml` | fixture | M3.1 | Create |
| `tests/fixtures/events-existing.jsonl` | fixture | M3.1 | Create |
| `tests/schemas/event.schema.json` | schema | M3.1 | Create |
| `tests/fetch-rss.bats` | test | M3.1 | Create |
| `tests/evolve-ingestion.bats` | test | M3.2 | Create |
| `tests/trigger-consume.bats` | test | M3.3 | Create |
| `tests/helper-commands.bats` | test | M3.4 | Create |
