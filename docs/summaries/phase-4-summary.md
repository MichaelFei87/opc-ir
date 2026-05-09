# Phase 4 Summary — Calibration & Ground Truth

**Status:** Complete (P4.1 + P4.1R fixes + P4.2 events rolling)
**Tests:** 124 total (19 new: 12 calibration + 7 events-rolling)

## What Phase 4 Added

### M4.1 — Price Truth Pipeline
- **`bin/fetch-prices.sh`** — Yahoo Finance price fetcher with fixture mode (`OPC_IR_PRICE_FIXTURE_DIR`) for testing. UTC-aware timestamps.
- **`bin/ground-truth-linker.sh`** — Links matured forecast and verdict predictions to price truth. Processes both `forecast.jsonl` (consensus) and `verdicts.jsonl` (per-role votes). Deduplicates on `run_id|asset|horizon|role`.

### M4.3 — Brier Score Calibration
- **`bin/calibrate-posteriors.sh`** — Computes per-role Brier scores, applies N>=30 cold-start floor, calculates posteriors as `clamp(prior_brier / role_brier, 0.5, 1.5)`. Regime detection compares recent-30 consensus Brier against historical.

### M4.4 — Regime Detection
- Built into `calibrate-posteriors.sh` — if recent 30 consensus records have Brier 50%+ worse than historical, `regime_warning: true` is set.

### M4.5 — Monthly Events Rolling
- **`bin/events-migrate.sh`** — One-time migration from monolithic `events.jsonl` to monthly files (`2026-05-events.jsonl`). Replaces original with symlink.
- **`bin/events-grep.sh`** — Cross-month event search with `--after`, `--before`, `--months` filters. Date comparison uses date-only substring to avoid ISO timestamp/date string mismatch.

### Calibrate Command
- **`commands/opc-ir-calibrate.md`** — Full 5-step pipeline: migration check → ground truth linking → event truth (verdict falsifier evaluation) → posterior calculation → status report. Supports `--dry-run`, `--force`, `--verbose`.

### P4.1R Review Fixes
- **Critical:** ground-truth-linker now processes `verdicts.jsonl` per-role votes (was only doing forecast consensus — per-role Brier was impossible)
- **Medium:** Prior weight lookup matches role name to correct YAML category
- **Medium:** Yahoo Finance timestamps use UTC (was local TZ)
- **Medium:** Regime detection filters to `_consensus` records only
- **Medium:** `bare except:` → `except Exception:` throughout (5 occurrences)

## How to Run (Phases 1-4 Combined)

### Prerequisites
```bash
brew install yq jq bats-core
```

### Run Tests
```bash
cd opc-ir
bats tests/*.bats        # 124 tests, 0 failures
```

### Price Fetching (fixture mode)
```bash
export OPC_IR_PRICE_FIXTURE_DIR=tests/fixtures/prices
bin/fetch-prices.sh NDX 2026-04-01
# → {"asset":"NDX","date":"2026-04-01","close":18000.00,"source":"fixture"}
```

### Ground Truth Linking
```bash
export OPC_IR_HOME=/tmp/opc-ir-test
mkdir -p "$OPC_IR_HOME"/{forecast,verdict,calibration,logs}
export OPC_IR_PRICE_FIXTURE_DIR=tests/fixtures/prices

# Create a matured forecast
echo '{"run_id":"r1","ts":"2026-04-01T00:00:00Z","forecasts":{"NDX":{"1w":{"strongly_bearish":0.05,"bearish":0.1,"neutral":0.2,"bullish":0.4,"strongly_bullish":0.25}}}}' > "$OPC_IR_HOME/forecast/forecast.jsonl"

bin/ground-truth-linker.sh --home "$OPC_IR_HOME"
cat "$OPC_IR_HOME/calibration/predictions-vs-truth.jsonl"
```

### Calibration
```bash
bin/calibrate-posteriors.sh --home "$OPC_IR_HOME"
cat "$OPC_IR_HOME/calibration/calibration-report.json"
```

### Events Rolling
```bash
# Migrate existing events
bin/events-migrate.sh --home "$OPC_IR_HOME"

# Search across months
bin/events-grep.sh --home "$OPC_IR_HOME" --after 2026-04-01 --before 2026-05-31
```

## Architecture After Phase 4

```
events.jsonl ← fetch-rss.sh / inject-event.sh
     ↓ triage → watchers → evolve-synthesize.sh
world-model.jsonl + world-model.md
     ↓ triggers
     ↓ forecast pipeline → forecast.jsonl
     ↓ verdict pipeline → verdicts.jsonl
     ↓
ground-truth-linker.sh ← fetch-prices.sh
     ↓
predictions-vs-truth.jsonl
     ↓
calibrate-posteriors.sh → calibration-report.json
     ↓
role-weights.yaml (posterior weights feed back into vote-aggregate)
```

## Key Design Decisions

1. **Fixture mode** — All price fetching can be tested offline via `OPC_IR_PRICE_FIXTURE_DIR`
2. **Batch writes** — Truth records accumulated in memory, written once (not per-record open/close)
3. **Env var passing** — All Python snippets use `os.environ`, never string interpolation (injection-safe)
4. **Date-only comparison** — `events-grep.sh` compares `published_at[0:10]` against date strings to avoid ISO timestamp sorting bugs
5. **Symlink migration** — Monthly rolling is backward-compatible; existing readers follow the symlink transparently
