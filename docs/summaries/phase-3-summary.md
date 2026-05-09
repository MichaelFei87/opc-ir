# Phase 3 Summary — Event Ingestion & Trigger System

**Status:** Complete (P3.1 + P3.1R review fixes applied)
**Tests:** 117 total (12 new calibration tests from P4.1 overlap, 7 fetch-rss, 7 trigger, 7 inject-event)

## What Phase 3 Added

### M3.1 — RSS Feed Fetcher (`bin/fetch-rss.sh`)
- Fetches RSS feeds from `defaults/sources.yaml` or user's `local.yaml`
- Python-based XML parsing (macOS bash 3.x compatible)
- 3-layer dedup: event ID, URL, normalized title (100-item window)
- Supports `file://` URLs for testing
- Temp file cleanup via `trap EXIT`

### M3.3 — Trigger Marker System (`bin/trigger-manage.sh`)
- CRUD for hard-rule trigger marker files
- 6-hour cool-down enforcement (configurable via `OPC_IR_VERDICT_COOLDOWN`)
- Ticker format validation (`^[A-Z0-9._-]+$`)
- Env var passing to Python (code injection fix from P3.1R)

### M3.4 — Manual Event Injection (`bin/inject-event.sh`)
- `opc-ir-inject-event` command for manual event entry
- Deterministic IDs with `manual-` prefix
- macOS `md5` / Linux `md5sum` fallback

### Evolve Command Updated (`commands/opc-ir-evolve.md`)
- Step 0: Trigger consumption (always consumes, even if cooling)
- Step 1: RSS fetch or manual inject
- Step 2-6: Full evolve pipeline with `--dry-run`, `--light`, `--inject-event` flags

### P3.1R Review Fixes
- **Critical:** `trigger-manage.sh` Python injection via `$TICKER`/`$VERDICTS_FILE` — fixed with env var passing
- **Critical:** `fetch-rss.sh` temp file leak — fixed with `trap EXIT`
- **Medium:** Ticker format validation added
- **Medium:** `printf '%s\n'` instead of `echo` for XML content

## How to Run (Phases 1-3 Combined)

### Prerequisites
```bash
brew install yq jq       # YAML/JSON processing
brew install bats-core    # Test runner
```

### Run Tests
```bash
cd opc-ir
bats tests/*.bats        # 117 tests, 0 failures
```

### Manual Event Injection
```bash
export OPC_IR_HOME=/tmp/opc-ir-test
mkdir -p "$OPC_IR_HOME/events"

# Inject a manual event
bin/inject-event.sh "Fed raises rates 50bp" --summary "Unexpected hawkish move" --url "https://example.com/fed"
cat "$OPC_IR_HOME/events/events.jsonl"
```

### RSS Fetch (with test fixture)
```bash
# Create a sources file pointing to local XML
cat > /tmp/test-sources.yaml << 'EOF'
sources:
  - name: test-feed
    url: "file://$(pwd)/tests/fixtures/rss/reuters-business.xml"
    enabled: true
    type: rss
EOF

bin/fetch-rss.sh --sources /tmp/test-sources.yaml --home "$OPC_IR_HOME"
cat "$OPC_IR_HOME/events/events.jsonl"
```

### Trigger System
```bash
# Create a trigger
bin/trigger-manage.sh create NDX

# Check cool-down
bin/trigger-manage.sh check NDX

# List pending
bin/trigger-manage.sh list

# Consume
bin/trigger-manage.sh consume NDX
```

### Full Evolve Pipeline (dry-run)
```bash
# Requires Claude Code agent runtime for LLM-based triage/watchers
# Use --dry-run to test plumbing without LLM calls
# (evolve command is an agent command, run via Claude Code)
```

## Architecture After Phase 3

```
events.jsonl ← fetch-rss.sh / inject-event.sh
     ↓ triage
     ↓ watchers (7 roles)
     ↓ evolve-synthesize.sh
world-model.jsonl + world-model.md
     ↓ triggers (trigger-manage.sh)
     ↓ forecast pipeline
forecast.jsonl → verdict pipeline → verdicts.jsonl
```
