# Phase 5 Summary — Scheduling, Visibility & Integrity

**Status:** Complete (P5.1 + review pending)
**Tests:** 137 total (13 new Phase 5 tests)

## What Phase 5 Added

### M5.1 — Scheduler Abstraction
- **`defaults/schedules.yaml`** — Single source of truth for 4 recurring jobs: evolve (1h), forecast (8h, disabled by default), calibrate (24h), digest (24h)
- **`bin/scheduler-loop.sh`** — `/loop` backend with register/unregister/list/status/record-run. Tracks 7-day expiry with countdown.
- **`bin/scheduler-dispatch.sh`** — Routes to active backend (reads `~/.opc-ir/scheduler/active-backend`, defaults to "loop")

### M5.2 — Quota & Expiry Visibility
- **`bin/token-tracker.sh`** — Records per-run token consumption to daily JSONL logs. Provides 7-day summary with daily averages and monthly projections.
- **`commands/opc-ir-status.md`** — Full 7-section dashboard: plugin info, integrity check, scheduler health with expiry countdown, stream freshness, data source counts, token usage, and quick stats.

### M5.3 — Premium Source Framework
- **`docs/PREMIUM-SOURCES.md`** — Setup guide for Bloomberg API, Refinitiv/LSEG, NewsAPI, TradingView. Covers credentials management via `secrets.env` (chmod 600, never committed), source enabling in `local.yaml`, and custom API source creation.

### M5.4 — Plugin Integrity Check
- **`bin/integrity.sh`** — SHA256-based lock/verify system. Uses Python `hashlib` for portability (no `sha256sum` dependency). `lock` generates master hash + per-file manifest at install time. `verify` detects any modification and lists changed files.

## How to Run (All 5 Phases Combined)

### Prerequisites
```bash
brew install yq jq bats-core python3
```

### Run Tests
```bash
cd opc-ir
bats tests/*.bats        # 137 tests, 0 failures
```

### Initialize OPC-IR
```bash
export OPC_IR_HOME=~/.opc-ir
mkdir -p "$OPC_IR_HOME"/{config,events,world,forecast,verdict,calibration,triggers,scheduler,logs}

# Generate integrity lock
bin/integrity.sh lock

# Register schedules
bin/scheduler-loop.sh register evolve /opc-ir-evolve 1h
bin/scheduler-loop.sh register calibrate /opc-ir-calibrate 24h
bin/scheduler-loop.sh register digest /opc-ir-digest 24h

# Check status
bin/scheduler-loop.sh list
```

### Manual Event → Full Pipeline
```bash
# 1. Inject an event
bin/inject-event.sh "Fed raises rates 50bp" --summary "Unexpected hawkish move"

# 2. Evolve world-model (agent command — requires Claude Code)
# /opc-ir-evolve

# 3. Check triggers
bin/trigger-manage.sh list

# 4. Forecast (agent command)
# /opc-ir-forecast

# 5. Verdict (agent command)
# /opc-ir-verdict NDX

# 6. Calibrate (after predictions mature)
bin/ground-truth-linker.sh --home "$OPC_IR_HOME"
bin/calibrate-posteriors.sh --home "$OPC_IR_HOME"
```

### Token Tracking
```bash
# Record a run's token usage
bin/token-tracker.sh record evolve run-001 5000 2000

# View 7-day summary
bin/token-tracker.sh summary 7
```

### Integrity Check
```bash
bin/integrity.sh verify
# → INTEGRITY OK: all plugin files match install lock.
```

### Premium Sources
```bash
# 1. Add credential
echo 'NEWSAPI_KEY=your-key-here' >> ~/.opc-ir/config/secrets.env
chmod 600 ~/.opc-ir/config/secrets.env

# 2. Enable in local.yaml
cat >> ~/.opc-ir/config/local.yaml << 'EOF'
sources:
  newsapi:
    enabled: true
EOF

# 3. Fetch will now include NewsAPI results
# /opc-ir-evolve
```

## Full Architecture

```
                    ┌─────────────────────────────┐
                    │     defaults/schedules.yaml  │
                    └──────────┬──────────────────┘
                               │
                    scheduler-dispatch.sh → scheduler-loop.sh
                               │
              ┌────────────────┼────────────────┐
              ↓                ↓                ↓
         /opc-ir-evolve  /opc-ir-calibrate /opc-ir-digest
              │                │                │
  fetch-rss.sh ← sources.yaml │                │
  inject-event.sh              │                │
              ↓                │                │
        events.jsonl           │                │
  (monthly: YYYY-MM-events.jsonl)               │
              ↓                │                │
   triage-classifier           │                │
              ↓                │                │
   7 watchers (parallel)       │                │
              ↓                │                │
   evolve-synthesize.sh        │                │
              ↓                │                │
   world-model.jsonl + .md     │                │
              ↓                │                │
   thesis-update.sh            │                │
              ↓                │                │
   trigger-manage.sh           │                │
              │                │                │
   ┌──────────┴──────────┐     │                │
   ↓                     ↓     │                │
/opc-ir-forecast  /opc-ir-verdict              │
   ↓                     ↓     │                │
forecast.jsonl    verdicts.jsonl│                │
   │                     │     │                │
   └──────────┬──────────┘     │                │
              ↓                │                │
   ground-truth-linker.sh ← fetch-prices.sh    │
              ↓                │                │
   predictions-vs-truth.jsonl  │                │
              ↓                │                │
   calibrate-posteriors.sh ────┘                │
              ↓                                 │
   calibration-report.json                      │
   role-weights.yaml ──────→ vote-aggregate ────┘
              ↓
   token-tracker.sh → logs/tokens/
   integrity.sh → install.lock
```

## Commit History
```
647ba1a feat: P3.1 auto-loop — RSS fetch, triggers, inject-event, Phase 2 summary
4524a67 feat: P3.1R fixes + P4.1 calibration pipeline — 117 tests, 0 failures
9736ba6 feat: P4.1R fixes + P4.2 events rolling — 124 tests, 0 failures
be65276 feat: Phase 5 — scheduler, tokens, integrity, premium sources — 137 tests
```
