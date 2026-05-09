# Phase 2 Summary — Memory Layer

**Completed:** 2026-05-08
**Tests:** 84 total, 0 failures (including all Phase 1 tests)
**Commits:** `b0d4469` (P2.1), `715a58e` (P2.2)

## What Phase 2 Adds

Phase 2 implements the **Memory Layer** — the system that processes events, updates the world-model, and persists thesis history across verdict runs.

### M2.1: Triage + Watchers
- **Triage classifier** (`agents/triage-classifier.md`) — scores events across 7 dimensions (0.0–1.0), routes to watchers at ≥0.6 threshold, handles hard rules
- **7 watcher roles** (`roles/_watchers/`) — one per dimension, each with `tags: [review, evolve]` and `output_format: delta`
- **Triage schema** (`tests/schemas/triage.schema.json`) — validates output structure

### M2.2: Watcher Dispatch (already included in M2.1)
- Watcher roles created for all 7 dimensions: politics, econ-finance, military, tech-ai, humanities, energy-commodity, corp-fundamentals

### M2.3: Evolve Full Chain
- **Evolve command** (`commands/opc-ir-evolve.md`) — full pipeline: events → triage → watchers → synthesize → world-model update → trigger markers
- **Evolve synthesizer** (`bin/evolve-synthesize.sh`) — merges watcher delta outputs into `world-model.jsonl` (append-only log) and `world-model.md` (human-readable snapshot)
- **Synthesizer agent** (`agents/synthesizer.md`) — documents merge logic and conflict resolution

### M2.4: Thesis History
- **Thesis updater** (`bin/thesis-update.sh`) — creates/updates `theses/{TICKER}.md` with current stance, falsifiers, dissent, and a **History section** preserving all prior stances
- History chain survives across multiple verdict runs (tested with 3 sequential verdicts)

## Critical Fixes from Review

The P2.1R review found 2 critical issues, both fixed in P2.2:

1. **Single file discovery source** — `evolve-synthesize.sh` had diverging bash `find` and Python `os.listdir()` paths. Fixed: bash passes file list via `FILE_LIST` environment variable; Python uses only that.
2. **Dimension preservation** — `world-model.md` was fully overwritten each run, losing prior dimensions. Fixed: script reads existing MD, preserves sections for dimensions not updated in current run.

## Files Created/Modified

### New Files (Phase 2)
| File | Type | Purpose |
|------|------|---------|
| `agents/triage-classifier.md` | agent | Event classification across 7 dimensions |
| `agents/synthesizer.md` | agent | Watcher output merge logic |
| `roles/_watchers/*.md` (×7) | roles | Dimension-specific world-model watchers |
| `bin/evolve-synthesize.sh` | script | Merge watcher deltas into world-model |
| `bin/thesis-update.sh` | script | Update thesis files with history |
| `commands/opc-ir-evolve.md` | command | Full evolve pipeline command |
| `tests/triage.bats` | test | 5 triage validation tests |
| `tests/watcher-dispatch.bats` | test | 6 watcher role structure tests |
| `tests/evolve.bats` | test | 5 evolve chain tests (incl. dimension preservation) |
| `tests/thesis-history.bats` | test | 6 thesis persistence tests |
| `tests/schemas/triage.schema.json` | schema | Triage output validation |
| `tests/fixtures/sample-events-10.jsonl` | fixture | 10 diverse sample events |
| `tests/fixtures/watcher-outputs/` (×3) | fixture | Watcher delta outputs |
| `tests/fixtures/verdict-ndx-first.json` | fixture | First NDX verdict |
| `tests/fixtures/verdict-ndx-second.json` | fixture | Second NDX verdict |

## How to Run & Test

### Prerequisites

Same as Phase 1, plus no new dependencies.

```bash
# Verify tools
jq --version    # JSON processing
bats --version  # Test runner
python3 --version  # Float arithmetic
```

### Run All Tests (Phase 1 + Phase 2)

```bash
bats tests/*.bats
# Expected: 84 tests, 0 failures
```

### Run Phase 2 Tests Only

```bash
bats tests/triage.bats tests/watcher-dispatch.bats tests/evolve.bats tests/thesis-history.bats
# Expected: 22 tests, 0 failures
```

### Individual Phase 2 Flows

#### Evolve Chain (synthesize watcher outputs)

```bash
# Create a temp directory for output
TEST_DIR=$(mktemp -d)
touch "$TEST_DIR/world-model.jsonl"

# Run evolve-synthesize with test fixtures
bin/evolve-synthesize.sh tests/fixtures/watcher-outputs "$TEST_DIR/world-model.jsonl" "$TEST_DIR/world-model.md"

# Inspect results
cat "$TEST_DIR/world-model.md"          # Human-readable snapshot
cat "$TEST_DIR/world-model.jsonl"       # Append-only delta log

# Clean up
rm -rf "$TEST_DIR"
```

#### Thesis Update (with history preservation)

```bash
TEST_DIR=$(mktemp -d)

# First verdict — creates thesis
bin/thesis-update.sh "$TEST_DIR" NDX tests/fixtures/verdict-ndx-first.json
cat "$TEST_DIR/theses/NDX.md"  # Shows LONG stance

# Second verdict — updates thesis, preserves history
bin/thesis-update.sh "$TEST_DIR" NDX tests/fixtures/verdict-ndx-second.json
cat "$TEST_DIR/theses/NDX.md"  # Shows NEUTRAL + History section with prior LONG

rm -rf "$TEST_DIR"
```

### Combined Phase 1 + Phase 2 Demo

```bash
TEST_DIR=$(mktemp -d)
mkdir -p "$TEST_DIR/verdict" "$TEST_DIR/forecast"

# Phase 1: Generate forecast
bin/vote-aggregate.sh tests/fixtures/strategist-votes.json defaults/role-weights.yaml "$TEST_DIR/forecast/forecast.json"
echo '{}' | jq --slurpfile f "$TEST_DIR/forecast/forecast.json" '{horizon:"1m",forecasts:{"NDX":$f[0]}}' > "$TEST_DIR/forecast/forecasts.jsonl"
bin/forecast-render.sh "$TEST_DIR"

# Phase 1: Generate verdict
bin/verdict-aggregate.sh tests/fixtures/verdict-votes-ndx.json defaults/role-weights.yaml "$TEST_DIR/verdict/verdict-ndx.json"
jq '. + {ticker:"NDX",timestamp:"2026-05-08T10:00:00Z"}' "$TEST_DIR/verdict/verdict-ndx.json" >> "$TEST_DIR/verdict/verdicts.jsonl"
bin/verdict-render-digest.sh "$TEST_DIR"

# Phase 2: Update thesis with history
bin/thesis-update.sh "$TEST_DIR" NDX "$TEST_DIR/verdict/verdict-ndx.json"

# Phase 2: Evolve world-model
touch "$TEST_DIR/world-model.jsonl"
bin/evolve-synthesize.sh tests/fixtures/watcher-outputs "$TEST_DIR/world-model.jsonl" "$TEST_DIR/world-model.md"

# Inspect everything
echo "=== Forecast ===" && cat "$TEST_DIR/forecast/forecast.md"
echo "=== Verdict Digest ===" && cat "$TEST_DIR/verdict/digest.md"
echo "=== Thesis ===" && cat "$TEST_DIR/theses/NDX.md"
echo "=== World Model ===" && cat "$TEST_DIR/world-model.md"

rm -rf "$TEST_DIR"
```

## Test Breakdown

| Test File | Count | Coverage |
|-----------|-------|----------|
| `tests/triage.bats` | 5 | Schema, sample events, agent file |
| `tests/watcher-dispatch.bats` | 6 | Role count, names, tags, fixtures |
| `tests/evolve.bats` | 5 | Synthesize chain, dimension preservation |
| `tests/thesis-history.bats` | 6 | Create, update, 3-step history chain |
| Phase 1 tests | 62 | Scaffold, roles, forecast, verdict, mitigations, e2e |
| **Total** | **84** | |

## Architecture Update

```
Events → Triage Classifier → Watcher Routing
                                    ↓
                    [politics] [econ-finance] [military] ...
                                    ↓
                         evolve-synthesize.sh
                          ↓              ↓
                  world-model.jsonl   world-model.md
                  (append-only)       (snapshot, preserved)

Verdict → thesis-update.sh → theses/{TICKER}.md (with History)
```

## What's Next: Phase 3

Phase 3 (Auto-loop Polish) will add:
- **M3.1**: RSS fetch from 11 configured sources
- **M3.2**: Full evolve + ingestion pipeline
- **M3.3**: Hard-rule trigger → async verdict consumption
- **M3.4**: Helper commands (`/opc-ir-digest`, `/opc-ir-status`)
