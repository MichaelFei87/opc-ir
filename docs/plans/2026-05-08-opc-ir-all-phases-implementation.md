# OPC-IR All-Phases Implementation Plan

> **Date:** 2026-05-08
> **Source spec:** `docs/specs/2026-05-08-opc-ir-overview-design.md`
> **Quality tier:** functional (Claude Code plugin = bash + markdown + YAML, no UI)
> **Scope:** M1.1–M5.4 — all five phases from Core Engine POC to Scheduling + Premium
> **Phase plans:** Each phase has a dedicated plan doc in `docs/plans/phase-{N}-*.md`

---

## Overview

OPC-IR is a Claude Code Plugin that applies multi-role independent voting to investment research. It produces three outputs: World-Model evolution, Macro Forecast, and single-asset Verdicts. This master plan decomposes all five phases into implementable milestones with concrete file paths, test commands, and verification criteria.

### Phase Summary

| Phase | Name | Milestones | Effort | Key Deliverable |
|---|---|---|---|---|
| 1 | Core Engine (POC) | M1.1–M1.5 | 5–8 days | Forecast + Verdict with sample data |
| 2 | Memory Layer | M2.1–M2.4 | 5–7 days | World-Model + thesis persistence |
| 3 | Auto-loop Polish | M3.1–M3.4 | 4–5 days | RSS ingestion + hard-rule triggers |
| 4 | Calibration | M4.1–M4.5 | 6–8 days | Ground-truth alignment + posterior weights |
| 5 | Scheduling + Premium | M5.1–M5.4 | 5–7 days | Desktop scheduler + premium sources |

### Dependency Graph

```
Phase 1 ─┬─ M1.1 (scaffold)
         ├─ M1.2 (roles + pipeline)
         ├─ M1.3 (forecast) ← M1.1, M1.2
         ├─ M1.4 (verdict) ← M1.1, M1.2     [M1.3 ∥ M1.4]
         └─ M1.5 (mitigations) ← M1.3, M1.4
                          │
Phase 2 ─┬─ M2.1 (triage) ← Phase 1
         ├─ M2.2 (watchers) ← M2.1
         ├─ M2.3 (evolve chain) ← M2.1, M2.2
         └─ M2.4 (thesis history) ← M1.4
                          │
Phase 3 ─┬─ M3.1 (fetch-rss) ← Phase 2
         ├─ M3.2 (evolve + ingestion) ← M2.3, M3.1
         ├─ M3.3 (trigger consumption) ← M3.2
         └─ M3.4 (helper commands) ← M3.2
                          │
Phase 4 ─┬─ M4.1 (price truth) ← Phase 1–2 jsonl
         ├─ M4.2 (event truth) ← Phase 1 verdict-judge
         ├─ M4.3 (posterior calc) ← M4.1, M4.2
         ├─ M4.4 (regime detection) ← M4.3
         └─ M4.5 (monthly rolling) ← Phase 3 events.jsonl
                          │
Phase 5 ─┬─ M5.1 (scheduler) ← Phase 3
         ├─ M5.2 (quota visibility) ← Phase 3
         ├─ M5.3 (premium sources) ← M3.1
         └─ M5.4 (integrity check) ← M1.1
```

### Technology Stack

- **Runtime:** Claude Code plugin (markdown commands/agents/skills + bash scripts)
- **Testing:** `bats` (bash), fixtures under `tests/fixtures/`, schemas under `tests/schemas/`
- **Linting:** `shellcheck -S warning` for bash, `yq` for YAML, `jq` for JSON
- **Data validation:** `ajv` or `python -m jsonschema` for JSONL schema checking
- **Conventions:** 2-space indent, `#!/usr/bin/env bash` + `set -euo pipefail`, `OPC_IR_HOME=$(mktemp -d)` for test isolation
- **Git:** one atomic commit per implement unit, co-author trailer required

### Runtime File Layout

```
~/.opc-ir/
├── config/local.yaml, secrets.env
├── world/world-model.jsonl, world-model.md
├── forecast/forecast.jsonl, forecast.md
├── verdict/verdicts.jsonl, digest.md, theses/{ticker}.md
├── events/events.jsonl
├── calibration/predictions-vs-truth.jsonl, role-weights.yaml
├── harness/runs/{run-id}/meta.json, triage.json, role-{name}/evaluation.md, synthesis.md
├── triggers/{ticker}.trigger
└── logs/{YYYY-MM-DD}.log
```

### Plugin Directory Layout (Repo)

```
opc-ir/
├── .claude-plugin/plugin.json
├── commands/opc-ir-{init,evolve,forecast,verdict,calibrate,digest,status}.md
├── agents/{triage-classifier,role-evaluator,synthesizer,verdict-judge}.md
├── skills/opc-ir/skill.md
├── roles/_schools/ (5), _advocates/ (2), _forecast/ (5), _watchers/ (7)
├── pipeline/{forked OPC files + native OPC-IR files}
├── bin/{fetch-rss,fetch-prices,ground-truth-linker,vote-aggregate,forecast-aggregate,forecast-render,verdict-aggregate,verdict-render-digest,invalidator-lint,falsifier-lint}.sh
├── defaults/{sources,watch-assets,dimension-weights,role-weights,horizons,triage-thresholds}.yaml
├── tests/{scaffold,roles,forked-meta,forecast,invalidator-lint,verdict,falsifier-lint,mitigations,e2e-phase1}.bats
├── tests/fixtures/, tests/schemas/, tests/lib/
├── docs/{README,ARCHITECTURE,CUSTOMIZE,PREMIUM-SOURCES,INHERITS-FROM-OPC}.md
├── docs/specs/, docs/plans/
└── LICENSE
```

---

## Phase 1: Core Engine (POC)

**Detailed plan:** [`docs/plans/phase-1-core-engine.md`](phase-1-core-engine.md)

**Goal:** Prove multi-role voting in a financial setting with sample-data inputs. From-zero install + sample fixtures → 3 commands → readable digest.

### M1.1: Plugin Scaffold

**Files to create:**
- `.claude-plugin/plugin.json` — plugin manifest with name "opc-ir", version "0.1.0"
- `commands/opc-ir-init.md` — creates `~/.opc-ir/` directory tree
- `commands/opc-ir-status.md` — reports timestamps, health, phase
- `commands/opc-ir-evolve.md` — stub (Phase 2 implementation)
- `commands/opc-ir-forecast.md` — stub (M1.3 fills in)
- `commands/opc-ir-verdict.md` — stub (M1.4 fills in)
- `commands/opc-ir-calibrate.md` — stub (Phase 4 implementation)
- `commands/opc-ir-digest.md` — regenerates digest.md from latest verdicts
- `agents/` — empty directory marker
- `skills/opc-ir/skill.md` — plugin skill entry point
- `LICENSE` — MIT
- `.gitignore` — excludes `~/.opc-ir/`, `*.log`, `.DS_Store`
- `tests/scaffold.bats` — validates plugin structure
- `tests/lib/check-frontmatter.sh` — YAML frontmatter parser utility
- `.git/hooks/pre-commit` — runs `shellcheck` on staged `.sh` files

**Verification:** `bats tests/scaffold.bats` exits 0; `jq -r '.name' .claude-plugin/plugin.json` returns `opc-ir`; `ls commands/opc-ir-*.md | wc -l` equals 7.

### M1.2: Roles + Pipeline

**Files to create:**
- `roles/_schools/{fundamental-analyst,technical-analyst,macro-economist,quant-modeler,behavioral-analyst}.md` (5 files)
- `roles/_advocates/{bull-advocate,bear-advocate}.md` (2 files)
- `roles/_forecast/{macro-strategist,cross-asset-allocator,regime-detector,historical-analogist,contrarian-strategist}.md` (5 files)
- `pipeline/discussion-protocol.md` — forked from OPC with `forked-from`/`forked-at: 2026-05-08` frontmatter
- `pipeline/role-evaluator-prompt.md` — forked from OPC
- `pipeline/gate-protocol.md` — forked from OPC
- `pipeline/role-spec.md` — forked from OPC
- `pipeline/forecast-protocol.md` — native, describes 5-strategist concurrent dispatch + vote + invalidator-lint gate
- `pipeline/vote-protocol.md` — native, formula: `final[asset][horizon][tier] = Σ(prob × prior × posterior)`, normalize, dissent L1 > 0.3
- `pipeline/verdict-protocol.md` — native, 5 schools + 2 advocates, advocate cap 0.5
- `pipeline/invalidator-lint.md` — native, specificity check (numeric + temporal + asset/event)
- `pipeline/triage-protocol.md` — native stub (Phase 2)
- `pipeline/evolve-protocol.md` — native stub (Phase 2)
- `pipeline/calibration-protocol.md` — native stub (Phase 4)
- `defaults/sources.yaml` — 10+ RSS sources
- `defaults/watch-assets.yaml` — 14 assets
- `defaults/dimension-weights.yaml` — 7 dimensions with weights
- `defaults/role-weights.yaml` — all priors=1.0, no posterior (cold-start)
- `defaults/horizons.yaml` — 1d, 1w, 1m, 3m
- `defaults/triage-thresholds.yaml` — threshold values
- `docs/INHERITS-FROM-OPC.md` — documents fork lineage
- `tests/roles.bats` — validates role file counts and frontmatter
- `tests/forked-meta.bats` — validates `forked-from`/`forked-at` on OPC-forked files

**Verification:** `bats tests/roles.bats tests/forked-meta.bats` exits 0; role counts match (5/2/5); all `defaults/*.yaml` parse via `yq`.

### M1.3: Forecast Flow

**Files to create/modify:**
- `commands/opc-ir-forecast.md` — full implementation (reads world-model, dispatches 5 strategists, votes, lint gate)
- `agents/synthesizer.md` — merges strategist outputs into forecast
- `agents/role-evaluator.md` — dispatches a single role and collects evaluation
- `bin/forecast-aggregate.sh` — weighted vote aggregation (bash + jq)
- `bin/forecast-render.sh` — ASCII probability bars for forecast.md
- `bin/invalidator-lint.sh` — checks specificity (numeric + temporal + asset/event regex)
- `tests/fixtures/world-model-sample.md` — sample world-model for testing
- `tests/fixtures/strategist-{1..5}.json` — 5 strategist output fixtures
- `tests/fixtures/invalidator-good.txt` — passes lint
- `tests/fixtures/invalidator-bad.txt` — fails lint ("if X significantly changes")
- `tests/schemas/forecast.schema.json` — JSON Schema for forecast.jsonl rows
- `tests/forecast.bats` — end-to-end forecast flow test
- `tests/invalidator-lint.bats` — positive and negative lint cases

**Key implementation details:**
- Vote formula: `final[asset][horizon][tier] = Σ(strategist_prob × prior_weight × posterior_weight)`, normalize to sum=1.0
- Cold-start: `posterior_weight = 1.0` when `N < 30`
- Dissent: per-strategist L1 distance > 0.3 from majority → `preserved_dissent`
- ASCII bars: `▓` blocks proportional to tier probability, 20-char width
- Invalidator-lint regex: must contain at least one number, one date/time reference, and one asset/event name

**Verification:** `bats tests/forecast.bats tests/invalidator-lint.bats` exits 0; `forecast.jsonl` validates against schema; ASCII bars present in `forecast.md`.

### M1.4: Verdict Flow

**Files to create/modify:**
- `commands/opc-ir-verdict.md` — full implementation (reads world-model + forecast + thesis, dispatches 5 schools + 2 advocates, votes, lint gate)
- `agents/verdict-judge.md` — dual-mode agent (verdict synthesis + calibration falsifier check)
- `bin/verdict-aggregate.sh` — weighted vote aggregation (schools weight 1.0, advocates 0.5)
- `bin/verdict-render-digest.sh` — generates digest.md with disclaimer, conviction, split warning
- `bin/falsifier-lint.sh` — same specificity check as invalidator-lint for verdict falsifiers
- `tests/fixtures/school-{1..5}.json` — 5 school evaluation fixtures
- `tests/fixtures/advocate-{bull,bear}.json` — 2 advocate fixtures
- `tests/fixtures/falsifier-missing.json` — fixture with no falsifier (rejected by gate)
- `tests/schemas/verdict.schema.json` — JSON Schema for verdicts.jsonl rows
- `tests/verdict.bats` — end-to-end verdict flow test
- `tests/falsifier-lint.bats` — positive and negative lint cases

**Key implementation details:**
- Dual-axis: 5 schools (each weight 1.0) + 2 advocates (each weight 0.5, cannot override schools)
- Split detection: weighted long/short/neutral spread < 0.15 → `consensus.direction = "split"`
- Digest: disclaimer banner "This is research analysis, not investment advice", conviction value, split warning
- Thesis: rewrite `theses/{ticker}.md` with current stance + history section (M2.4 completes history)
- Falsifier-lint: same regex as invalidator-lint, retry counter max 2

**Verification:** `bats tests/verdict.bats tests/falsifier-lint.bats` exits 0; `verdicts.jsonl` validates against schema; `digest.md` contains disclaimer string.

### M1.5: Phase 1 Risk Mitigations

**Files to create/modify:**
- `bin/vote-aggregate.sh` — add posterior cap: `clamp(posterior, 0.5, 1.5)` (M3)
- `pipeline/vote-protocol.md` — document cap formula (M3)
- `bin/invalidator-lint.sh` — specificity regex already in M1.3 (M4, verify)
- `pipeline/invalidator-lint.md` — document specificity requirements (M4)
- `pipeline/verdict-protocol.md` — add disclaimer template reference (P1)
- `bin/verdict-render-digest.sh` — disclaimer already in M1.4 (P1, verify)
- `tests/schemas/forecast.schema.json` — add `regime_marker` field (P2)
- `tests/schemas/verdict.schema.json` — add `regime_marker` field (P2)
- `README.md` — add `## Limitations` section documenting public-RSS density gap (D2)
- `docs/ARCHITECTURE.md` — cross-reference table mapping each mitigation to file location
- `tests/mitigations.bats` — 5 assertions covering all mitigations

**Verification:** `bats tests/mitigations.bats` exits 0; `README.md` has Limitations section; `ARCHITECTURE.md` has cross-reference table.

### Phase 1 Exit Criteria

From-zero install + sample fixtures → `/opc-ir-init` → `/opc-ir-forecast` → `/opc-ir-verdict NDX` → readable `digest.md` with disclaimer. Both invalidator-lint and falsifier-lint gates fire at least one positive and one negative case. `bats tests/e2e-phase1.bats` exits 0.

---

## Phase 2: Memory Layer

**Detailed plan:** [`docs/plans/phase-2-memory-layer.md`](phase-2-memory-layer.md)

**Goal:** Continuous world-model evolution from events, with thesis persistence across verdicts.

### M2.1: Triage Classifier

**Files to create:**
- `agents/triage-classifier.md` — LLM agent that scores events across 7 dimensions
- `tests/fixtures/sample-events-10.jsonl` — 10 diverse sample events
- `tests/schemas/triage.schema.json` — JSON Schema for triage output
- `tests/triage.bats` — validates triage output against schema, checks dimension scores, watcher routing

**Key details:**
- Per-event output: 7-dimension scores (0.0–1.0), `watchers_to_dispatch` (dimensions above 0.6 threshold), `hard_rule_hit` boolean, `verdict_targets` array
- Hard rules: central bank policy, war/ceasefire, NDX top-10 earnings, circuit breaker
- Batch ≤20 events per triage invocation (D6 mitigation)

**Verification:** `bats tests/triage.bats` exits 0; 10 sample events produce conformant `triage.json`.

### M2.2: 7 Watchers

**Files to create:**
- `roles/_watchers/{politics,econ-finance,military,tech-ai,humanities,energy-commodity,corp-fundamentals}-watcher.md` (7 files)
- `tests/watcher-dispatch.bats` — concurrent dispatch test, single-failure tolerance

**Key details:**
- Each watcher receives: routed event subset + frozen world-model.md snapshot
- Output: `evaluation.md` with frontmatter (role, run_id, events_considered) + sections: Disturbance to World-Model, Cross-dimension implications
- All 7 fully independent; single failure → warning, does not block others

**Verification:** `bats tests/watcher-dispatch.bats` exits 0; single-watcher failure produces warning not error.

### M2.3: Evolve Full Chain

**Files to modify:**
- `commands/opc-ir-evolve.md` — full implementation (without ingestion): batch events → triage → watchers → synthesize → world-model update → trigger markers
- `agents/synthesizer.md` — extend for evolve synthesis (merge watcher proposals by weight)

**Files to create:**
- `bin/evolve-synthesize.sh` — merges watcher outputs, writes world-model delta
- `tests/evolve.bats` — full chain test with sample events
- `tests/fixtures/watcher-outputs/` — 7 sample watcher evaluations

**Key details:**
- World-model.jsonl: append delta `{run_id, ts, deltas: [{dimension, field, before, after, trigger_events, watcher, watcher_confidence}]}`
- World-model.md: rewrite with updated per-dimension sections
- Hard-rule trigger: write `~/.opc-ir/triggers/{ticker}.trigger` file with `{run_id, event_id, timestamp}`

**Verification:** `bats tests/evolve.bats` exits 0; world-model.jsonl has delta entries; trigger marker written for hard-rule events.

### M2.4: Thesis History

**Files to modify:**
- `bin/verdict-render-digest.sh` — preserve History section when rewriting `theses/{ticker}.md`
- `commands/opc-ir-verdict.md` — inject existing thesis into all 7 roles' input

**Files to create:**
- `tests/thesis-history.bats` — second verdict on same ticker preserves first stance

**Verification:** `bats tests/thesis-history.bats` exits 0; second verdict shows prior stance in History.

### Phase 2 Exit Criteria

Batch events → triage → watchers → world-model.md readable + jsonl deltas recorded. Hard-rule writes trigger marker. Second verdict on same ticker preserves first stance in History section.

---

## Phase 3: Auto-loop Polish

**Detailed plan:** [`docs/plans/phase-3-auto-loop-polish.md`](phase-3-auto-loop-polish.md)

**Goal:** Automatic ingestion from RSS, hard-rule async verdict triggering, helper commands for power users.

### M3.1: RSS Fetch + Dedup

**Files to create:**
- `bin/fetch-rss.sh` — fetches from all sources in `sources.yaml`, dedup against events.jsonl tail, per-source fault tolerance
- `defaults/sources.yaml` — ≥10 RSS sources (Reuters, AP, BBC, CNBC, FT, Bloomberg RSS, Xinhua, SCMP, Fed RSS, ECB RSS)
- `tests/fixtures/rss/` — canned XML files for each source
- `tests/fetch-rss.bats` — tests with mock data, no real network

**Key details:**
- Exit 0 always (even all-source fail)
- Per-source timeout (configurable, default 10s)
- Dedup: URL + title fuzzy match against last 100 entries in events.jsonl
- Event schema: `{id: "<source>-<published-utc>-<hash>", source, fetched_at, published_at, title, summary, url, raw_text}`
- Failures logged to `logs/{date}.log`

**Verification:** `bats tests/fetch-rss.bats` exits 0; produces events.jsonl entries from canned XML.

### M3.2: Evolve + Ingestion

**Files to modify:**
- `commands/opc-ir-evolve.md` — Step 1 calls `bin/fetch-rss.sh`; Step 1 → 0 new events: short-circuit exit

**Verification:** Evolve with empty RSS cache produces short-circuit; with canned events produces full chain.

### M3.3: Hard-rule Trigger Consumption

**Files to modify:**
- `commands/opc-ir-evolve.md` — at start, check `~/.opc-ir/triggers/*.trigger`; for each, dispatch `/opc-ir-verdict {ticker}` then delete marker

**Key details:**
- Cool-down: default 6h per ticker (check trigger file mtime vs last verdict timestamp)
- Marker consumed after verdict dispatch (or cool-down skip)

**Verification:** `bats tests/trigger-consume.bats` exits 0; trigger file deleted after verdict; cool-down prevents re-trigger within 6h.

### M3.4: Helper Commands

**Files to modify:**
- `commands/opc-ir-evolve.md` — add `--light`, `--dry-run`, `--inject-event` flags
- `commands/opc-ir-verdict.md` — read cool-down from config

**Key details:**
- `--light`: skip forecast dispatch, only dispatch top-1 scored watcher dimension
- `--dry-run`: run triage, display dimension scores and routing, but do NOT update world-model or write triggers
- `--inject-event`: append user-provided event to events.jsonl with `source: "manual"`, then run evolve

**Verification:** `bats tests/helper-commands.bats` exits 0; dry-run does not modify world-model.

### Phase 3 Exit Criteria

Auto-running plugin: `/loop 1h /opc-ir-evolve` produces world-model + forecast + verdict + digest. Helper commands work. RSS fetching with per-source isolation. MVP-publishable point reached.

---

## Phase 4: Calibration

**Detailed plan:** [`docs/plans/phase-4-calibration.md`](phase-4-calibration.md)

**Goal:** Ground-truth alignment and posterior role-weight learning. The quality flywheel.

### M4.1: Price Truth

**Files to create:**
- `bin/fetch-prices.sh` — multi-source fallback (yfinance → Alpha Vantage → FRED for rates)
- `bin/ground-truth-linker.sh` — aligns predictions to actual prices: t+horizon price → 5-tier bucket
- `tests/fixtures/prices/` — canned price data
- `tests/price-truth.bats` — tests bucket assignment, missing-price handling

**Key details:**
- 5-tier bucket boundaries defined in `defaults/tier-boundaries.yaml`
- Missing prices → skip sample, do not count toward N
- Multi-source: try yfinance first, fall back to Alpha Vantage, then FRED for interest rates

**Verification:** `bats tests/price-truth.bats` exits 0; bucket assignment correct for sample prices.

### M4.2: Event Truth

**Files to modify:**
- `agents/verdict-judge.md` — calibration-judge mode: evaluates whether thesis falsifiers were triggered by subsequent events

**Files to create:**
- `tests/event-truth.bats` — tests falsifier trigger detection

**Key details:**
- Input: thesis falsifier + subsequent events from events.jsonl
- Output: `triggered: true/false` with `evidence` field
- Human truth (optional): `human-overrides.jsonl` takes priority

**Verification:** `bats tests/event-truth.bats` exits 0; correctly identifies triggered/untriggered falsifiers.

### M4.3: Posterior Calculation

**Files to create:**
- `bin/calibrate-posteriors.sh` — computes Brier scores per role, derives posterior weights
- `tests/calibration.bats` — N≥30 floor, cap, anomaly rejection

**Key details:**
- Brier score per (role, asset, horizon): `mean((predicted_prob - actual_one_hot)^2)`
- Posterior: `clamp(prior_brier / role_brier, 0.5, 1.5)` — only if N≥30
- Anomaly: all posteriors 1.0/0.0/NaN → reject write, log warning
- Output: `calibration/predictions-vs-truth.jsonl` append + `calibration/role-weights.yaml` rewrite

**Verification:** `bats tests/calibration.bats` exits 0; N<30 produces no posterior update; cap enforced.

### M4.4: Regime Detection

**Files to create:**
- `bin/regime-detect.sh` — 30-day rolling Brier deterioration check
- `tests/regime.bats` — tests deterioration threshold detection

**Key details:**
- If 30-day rolling Brier > 2× long-term average → `regime_marker: "detected"`, reset posteriors to 1.0
- Digest warning: "Regime change detected — calibration weights reset"
- P2 full implementation (Phase 1 had placeholder field only)

**Verification:** `bats tests/regime.bats` exits 0; deterioration triggers reset + warning.

### M4.5: Monthly Rolling

**Files to create:**
- `bin/events-roll.sh` — splits events.jsonl by month, archives old months
- `tests/events-roll.bats` — tests cross-month grep, archive correctness

**Key details:**
- Monthly files: `events/events-YYYY-MM.jsonl`
- Current month: `events/events.jsonl` (symlink or latest)
- Cross-month grep: `bin/events-search.sh <query>` searches across all monthly files

**Verification:** `bats tests/events-roll.bats` exits 0; monthly split preserves all entries.

### Phase 4 Exit Criteria

`/opc-ir-calibrate` runs daily: identifies due predictions, fetches prices, computes Brier, updates posteriors (if N≥30). Regime detection triggers reset when performance deteriorates. Monthly rolling prevents unbounded growth.

---

## Phase 5: Scheduling + Premium

**Detailed plan:** [`docs/plans/phase-5-scheduling-premium.md`](phase-5-scheduling-premium.md)

**Goal:** Long-term productionization: scheduler abstraction, quota visibility, premium data sources, plugin integrity.

### M5.1: Scheduler Abstraction

**Files to create:**
- `bin/scheduler-abstract.sh` — unified interface for `/loop`, Desktop Tasks, Cloud Routines
- `pipeline/scheduler-protocol.md` — documents scheduler backends

**Key details:**
- Backend detection: check environment for Desktop Tasks API, Cloud Routines API, fall back to `/loop`
- Unified schedule config in `~/.opc-ir/config/local.yaml`: `scheduler.evolve_interval: 1h`, `scheduler.calibrate_interval: daily`
- `/loop` backend: generates CronCreate invocations
- Desktop/Cloud: generates platform-specific schedule entries

**Verification:** Scheduler creates appropriate schedule entries for detected backend.

### M5.2: Quota & Expiry Visibility

**Files to modify:**
- `commands/opc-ir-status.md` — add token usage, quota, loop expiry countdown
- `bin/token-logger.sh` — per-run token usage tracking

**Key details:**
- T1: `/loop` 7-day expiry → status shows days remaining + warning at <24h
- T2: per-run token count logged to `logs/token-usage.jsonl`; status shows cumulative + per-command average
- `--light` mode recommendation when quota is low

**Verification:** Status output includes expiry countdown and token usage summary.

### M5.3: Premium-Source Framework

**Files to modify:**
- `defaults/sources.yaml` — add `type` field (`rss|api|scrape`); add commented-out premium sources
- `bin/fetch-rss.sh` → `bin/fetch-sources.sh` — rename, add API source handler

**Files to create:**
- `docs/PREMIUM-SOURCES.md` — guide for configuring Bloomberg, Refinitiv, etc.
- `tests/premium-sources.bats` — tests API source handler with mock

**Key details:**
- API sources read credentials from `~/.opc-ir/config/secrets.env`
- `BLOOMBERG_API_KEY`, `REFINITIV_APP_KEY`, etc.
- Premium sources never required — plugin works with free RSS only
- `secrets.env` template shipped as `defaults/secrets.env.example`

**Verification:** `bats tests/premium-sources.bats` exits 0; API handler reads mock credentials and produces events.

### M5.4: Plugin Integrity Check

**Files to create:**
- `bin/integrity-check.sh` — SHA256 hash of all plugin files at install time
- Modify `commands/opc-ir-status.md` — add integrity check output

**Key details:**
- T6 mitigation: at install, write SHA256 manifest to `~/.opc-ir/config/install-manifest.sha256`
- Status command compares current file hashes to manifest
- Mismatch → warning with affected file list

**Verification:** `bats tests/integrity.bats` exits 0; tampered file detected by status command.

### Phase 5 Exit Criteria

Scheduler works across backends. Status shows quota + expiry. Premium sources configurable via `secrets.env`. Integrity check detects tampering. All Phase 1–5 acceptance criteria met.

---

## Cross-Phase Test Matrix

| Test File | Phase | Covers |
|---|---|---|
| `tests/scaffold.bats` | 1 | M1.1 plugin structure |
| `tests/roles.bats` | 1 | M1.2 role file counts + frontmatter |
| `tests/forked-meta.bats` | 1 | M1.2 OPC-forked file lineage |
| `tests/forecast.bats` | 1 | M1.3 forecast flow end-to-end |
| `tests/invalidator-lint.bats` | 1 | M1.3 invalidator specificity |
| `tests/verdict.bats` | 1 | M1.4 verdict flow end-to-end |
| `tests/falsifier-lint.bats` | 1 | M1.4 falsifier specificity |
| `tests/mitigations.bats` | 1 | M1.5 all 5 mitigations |
| `tests/e2e-phase1.bats` | 1 | M1.E end-to-end acceptance |
| `tests/triage.bats` | 2 | M2.1 triage classifier |
| `tests/watcher-dispatch.bats` | 2 | M2.2 concurrent watcher dispatch |
| `tests/evolve.bats` | 2 | M2.3 evolve full chain |
| `tests/thesis-history.bats` | 2 | M2.4 thesis persistence |
| `tests/fetch-rss.bats` | 3 | M3.1 RSS fetching + dedup |
| `tests/trigger-consume.bats` | 3 | M3.3 trigger marker lifecycle |
| `tests/helper-commands.bats` | 3 | M3.4 --light/--dry-run/--inject |
| `tests/price-truth.bats` | 4 | M4.1 price bucket assignment |
| `tests/event-truth.bats` | 4 | M4.2 falsifier trigger detection |
| `tests/calibration.bats` | 4 | M4.3 Brier + posterior calc |
| `tests/regime.bats` | 4 | M4.4 regime detection |
| `tests/events-roll.bats` | 4 | M4.5 monthly rolling |
| `tests/premium-sources.bats` | 5 | M5.3 API source handler |
| `tests/integrity.bats` | 5 | M5.4 SHA256 integrity check |

## JSON Schemas

### forecast.schema.json (Phase 1)

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["run_id", "timestamp", "world_model_ref", "forecasts", "strategist_dissent", "invalidators", "regime_marker"],
  "properties": {
    "run_id": { "type": "string" },
    "timestamp": { "type": "string", "format": "date-time" },
    "world_model_ref": { "type": "string" },
    "regime_marker": { "type": ["string", "null"] },
    "forecasts": {
      "type": "object",
      "patternProperties": {
        "^[A-Z0-9]+$": {
          "type": "object",
          "patternProperties": {
            "^(1d|1w|1m|3m)$": {
              "type": "object",
              "required": ["strongly_bearish", "bearish", "neutral", "bullish", "strongly_bullish"],
              "properties": {
                "strongly_bearish": { "type": "number", "minimum": 0, "maximum": 1 },
                "bearish": { "type": "number", "minimum": 0, "maximum": 1 },
                "neutral": { "type": "number", "minimum": 0, "maximum": 1 },
                "bullish": { "type": "number", "minimum": 0, "maximum": 1 },
                "strongly_bullish": { "type": "number", "minimum": 0, "maximum": 1 }
              }
            }
          }
        }
      }
    },
    "strategist_dissent": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["strategist", "asset", "horizon", "l1_distance"],
        "properties": {
          "strategist": { "type": "string" },
          "asset": { "type": "string" },
          "horizon": { "type": "string" },
          "l1_distance": { "type": "number" },
          "distribution": { "type": "object" }
        }
      }
    },
    "invalidators": {
      "type": "object",
      "patternProperties": {
        "^[A-Z0-9]+$": {
          "type": "object",
          "patternProperties": {
            "^(1d|1w|1m|3m)$": { "type": "string", "minLength": 20 }
          }
        }
      }
    }
  }
}
```

### verdict.schema.json (Phase 1)

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["run_id", "timestamp", "ticker", "world_model_ref", "forecast_ref", "consensus", "votes", "preserved_dissent", "falsifiers", "regime_marker"],
  "properties": {
    "run_id": { "type": "string" },
    "timestamp": { "type": "string", "format": "date-time" },
    "ticker": { "type": "string" },
    "world_model_ref": { "type": "string" },
    "forecast_ref": { "type": "string" },
    "regime_marker": { "type": ["string", "null"] },
    "consensus": {
      "type": "object",
      "required": ["direction", "conviction", "horizon"],
      "properties": {
        "direction": { "type": "string", "enum": ["long", "short", "neutral", "split"] },
        "conviction": { "type": "number", "minimum": 0, "maximum": 1 },
        "horizon": { "type": "string" }
      }
    },
    "votes": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["role", "direction", "weight", "weighted_score"],
        "properties": {
          "role": { "type": "string" },
          "direction": { "type": "string", "enum": ["long", "short", "neutral"] },
          "weight": { "type": "number" },
          "weighted_score": { "type": "number" }
        }
      }
    },
    "preserved_dissent": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["role", "direction", "reasoning_summary"],
        "properties": {
          "role": { "type": "string" },
          "direction": { "type": "string" },
          "reasoning_summary": { "type": "string" }
        }
      }
    },
    "falsifiers": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["role", "condition"],
        "properties": {
          "role": { "type": "string" },
          "condition": { "type": "string", "minLength": 20 }
        }
      }
    }
  }
}
```

---

## Implementation Sequence per Phase

Each phase follows the OPC loop pattern:

```
{P}.1  implement  — build all milestone files + tests
{P}.2  review     — ≥2 independent subagent review
{P}.3  fix        — address 🔴/🟡 findings
{P}.E  e2e-verify — end-to-end acceptance test
{P}.A  accept     — final acceptance against criteria
```

Phase 1 decomposes further into per-milestone steps (S1–S7 in the loop plan). Phases 2–5 may use coarser granularity depending on complexity discovered during implementation.

---

## Risk Tracking Across Phases

| Risk | Sev | Mitigated in | File |
|---|---|---|---|
| T1 loop expiry | H→L(POC) | Phase 5 M5.2 | `commands/opc-ir-status.md` |
| T2 quota exhaustion | H→L(POC) | Phase 5 M5.2 | `bin/token-logger.sh` |
| T3 watcher failure drift | M | Phase 2 M2.3 | `bin/evolve-synthesize.sh` |
| T4 nesting depth | M | Phase 2 M2.3 | trigger marker pattern |
| T5 log concurrent write | L | Phase 3 M3.2 | `flock` in log writes |
| T6 plugin tampering | L | Phase 5 M5.4 | `bin/integrity-check.sh` |
| T7 empty-tick waste | L | Phase 1 (auto) | evolve short-circuit |
| D1 RSS instability | M | Phase 3 M3.1 | `bin/fetch-rss.sh` ≥10 sources |
| D2 public-RSS density | H | Phase 1 M1.5 | `README.md` Limitations |
| D3 yfinance errors (CN) | M | Phase 4 M4.1 | multi-source fallback |
| D4 events.jsonl growth | L | Phase 4 M4.5 | monthly rolling |
| D5 duplicate events | M | Phase 3 M3.1 | fuzzy dedup |
| D6 triage token explosion | M | Phase 2 M2.1 | batch ≤20 |
| M3 weight collapse | H | Phase 1 M1.5 | posterior cap [0.5, 1.5] |
| M4 falsifier formality | H | Phase 1 M1.5 | invalidator-lint specificity |
| M5 pseudo-independence | H | Phase 2 | world-model dissent section |
| P1 advice misinterpretation | H | Phase 1 M1.5 | digest disclaimer |
| P2 over-trust Brier | H | Phase 1+4 | regime_marker + detection |

---

## Glossary

See spec Appendix A for full glossary. Key terms used in this plan:

- **Verdict** — single-asset judgment (long/short/neutral + conviction + horizon + falsifier)
- **Forecast** — multi-asset probability distribution over time horizons
- **World-Model** — 7-dimension macro snapshot continuously updated from events
- **Thesis** — persistent narrative for a ticker, accumulated across verdicts
- **Falsifier / Invalidator** — explicit condition under which prediction is admitted invalid
- **Brier score** — mean squared distance between predicted probability and one-hot truth
- **Cold start** — period before N≥30; posterior weights inactive
- **Regime change** — structural shift making historical calibration obsolete
- **Hard-rule** — event categories that auto-trigger verdicts
- **Run-id** — unique identifier per invocation, enabling immutable lineage

---

## Appendix B: Complete Code Blocks for Phase 1

This appendix contains the full source code for every script, test, schema, and configuration file created in Phase 1. These are the exact contents to write — no interpolation or placeholder expansion needed.

### B.1 Plugin Manifest — `.claude-plugin/plugin.json`

```json
{
  "name": "opc-ir",
  "version": "0.1.0",
  "description": "OPC-IR: Investment Research via Multi-Role Independent Voting. Produces World-Model evolution, Macro Forecasts, and single-asset Verdicts using the OPC methodology.",
  "author": "OPC-IR Contributors",
  "license": "MIT",
  "commands": [
    "commands/opc-ir-init.md",
    "commands/opc-ir-status.md",
    "commands/opc-ir-evolve.md",
    "commands/opc-ir-forecast.md",
    "commands/opc-ir-verdict.md",
    "commands/opc-ir-calibrate.md",
    "commands/opc-ir-digest.md"
  ],
  "agents": [
    "agents/triage-classifier.md",
    "agents/role-evaluator.md",
    "agents/synthesizer.md",
    "agents/verdict-judge.md"
  ],
  "skills": [
    "skills/opc-ir/skill.md"
  ]
}
```

### B.2 Command Stubs

#### `commands/opc-ir-init.md`

```markdown
---
name: opc-ir-init
description: Initialize OPC-IR runtime directory structure at ~/.opc-ir/
allowed-tools: Bash, Read, Write
---

# /opc-ir-init

Create the OPC-IR runtime directory tree if it does not exist.

## Procedure

1. Set `OPC_IR_HOME` to `${OPC_IR_HOME:-$HOME/.opc-ir}`.
2. Create directory structure:
   ```bash
   mkdir -p "$OPC_IR_HOME"/{config,world,forecast,verdict/theses,events,calibration,harness/runs,triggers,logs}
   ```
3. If `$OPC_IR_HOME/config/local.yaml` does not exist, create it with default contents:
   ```yaml
   # OPC-IR local configuration override
   # See defaults/*.yaml in the plugin repo for all options
   # Uncomment and modify values below to override defaults
   
   # scheduler:
   #   evolve_interval: 1h
   #   calibrate_interval: daily
   ```
4. Report created directories and current configuration.
5. Print: "OPC-IR initialized at $OPC_IR_HOME. Run /opc-ir-status to check health."
```

#### `commands/opc-ir-status.md`

```markdown
---
name: opc-ir-status
description: Report OPC-IR system health, timestamps, and current phase
allowed-tools: Bash, Read
---

# /opc-ir-status

Display system health dashboard.

## Procedure

1. Set `OPC_IR_HOME` to `${OPC_IR_HOME:-$HOME/.opc-ir}`.
2. Check directory exists; if not, print "OPC-IR not initialized. Run /opc-ir-init first." and exit.
3. Report:
   - **Phase:** "Phase 1 POC" (hardcoded until Phase 5 scheduler)
   - **Last evolve:** mtime of `$OPC_IR_HOME/world/world-model.md` or "never"
   - **Last forecast:** mtime of `$OPC_IR_HOME/forecast/forecast.md` or "never"
   - **Last verdict:** mtime of `$OPC_IR_HOME/verdict/digest.md` or "never"
   - **Last calibration:** mtime of `$OPC_IR_HOME/calibration/role-weights.yaml` or "never"
   - **Events count:** `wc -l < $OPC_IR_HOME/events/events.jsonl` or 0
   - **Pending triggers:** `ls $OPC_IR_HOME/triggers/*.trigger 2>/dev/null | wc -l`
   - **Disk usage:** `du -sh $OPC_IR_HOME`
4. Check for stale world-model (>24h since last evolve): print warning.
5. Check for stale forecast (>16h since last forecast): print warning.
```

#### `commands/opc-ir-evolve.md` (Phase 1 stub)

```markdown
---
name: opc-ir-evolve
description: "Evolve world-model: fetch → triage → watchers → synthesize (Phase 2 implementation)"
allowed-tools: Bash, Read, Write, Agent
---

# /opc-ir-evolve

Phase 2 implementation. Currently a stub.

## Procedure

1. Print: "World-model evolution requires Phase 2 (Memory Layer). Currently in Phase 1 POC mode."
2. Print: "Available Phase 1 commands: /opc-ir-forecast, /opc-ir-verdict <ticker>"
```

#### `commands/opc-ir-forecast.md` (Phase 1 stub — M1.3 fills in)

```markdown
---
name: opc-ir-forecast
description: Generate macro forecast across 14 watch-assets using 5 strategist roles
allowed-tools: Bash, Read, Write, Agent
---

# /opc-ir-forecast

Stub — replaced by M1.3 implementation.
```

#### `commands/opc-ir-verdict.md` (Phase 1 stub — M1.4 fills in)

```markdown
---
name: opc-ir-verdict
description: "Generate single-asset verdict using 5 schools + 2 advocates"
allowed-tools: Bash, Read, Write, Agent
---

# /opc-ir-verdict

Stub — replaced by M1.4 implementation.

## Arguments

- `<ticker>` — required, e.g. NDX, SPX, BTC
```

#### `commands/opc-ir-calibrate.md` (Phase 4 stub)

```markdown
---
name: opc-ir-calibrate
description: "Align ground truth with predictions; update posterior role-weights (Phase 4)"
allowed-tools: Bash, Read, Write
---

# /opc-ir-calibrate

Phase 4 implementation. Currently a stub.

## Procedure

1. Print: "Calibration requires Phase 4. Currently in Phase 1 POC mode."
```

#### `commands/opc-ir-digest.md`

```markdown
---
name: opc-ir-digest
description: Regenerate digest.md from latest verdicts
allowed-tools: Bash, Read, Write
---

# /opc-ir-digest

Regenerate the verdict digest from existing verdicts.jsonl.

## Procedure

1. Set `OPC_IR_HOME` to `${OPC_IR_HOME:-$HOME/.opc-ir}`.
2. Check `$OPC_IR_HOME/verdict/verdicts.jsonl` exists; if not, print "No verdicts found. Run /opc-ir-verdict <ticker> first." and exit.
3. Run `bin/verdict-render-digest.sh "$OPC_IR_HOME"` to regenerate `$OPC_IR_HOME/verdict/digest.md`.
4. Print the contents of `digest.md`.
```

### B.3 Core Bash Scripts

#### `bin/vote-aggregate.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# vote-aggregate.sh — Weighted vote aggregation with posterior cap
# Usage: vote-aggregate.sh <votes.json> <role-weights.yaml> <output.json>
#
# Input votes.json: array of {role, distribution: {tier: prob}, prior_weight, posterior_weight}
# Output: {aggregated: {tier: prob}, dissent: [...], weights_used: [...]}

VOTES_FILE="${1:?Usage: vote-aggregate.sh <votes.json> <role-weights.yaml> <output.json>}"
WEIGHTS_FILE="${2:?Usage: vote-aggregate.sh <votes.json> <role-weights.yaml> <output.json>}"
OUTPUT_FILE="${3:?Usage: vote-aggregate.sh <votes.json> <role-weights.yaml> <output.json>}"

# Clamp function: clamp(value, min, max)
clamp() {
  local val="$1" min_val="$2" max_val="$3"
  python3 -c "print(max($min_val, min($max_val, $val)))"
}

# Read votes and aggregate using jq + python3 for float arithmetic
python3 << 'PYEOF'
import json
import sys

votes_file = sys.argv[1] if len(sys.argv) > 1 else "${VOTES_FILE}"
output_file = sys.argv[2] if len(sys.argv) > 2 else "${OUTPUT_FILE}"

with open("${VOTES_FILE}") as f:
    votes = json.load(f)

tiers = ["strongly_bearish", "bearish", "neutral", "bullish", "strongly_bullish"]
aggregated = {t: 0.0 for t in tiers}
total_weight = 0.0
weights_used = []
dissent = []

for vote in votes:
    prior = vote.get("prior_weight", 1.0)
    posterior = vote.get("posterior_weight", 1.0)
    # M3 mitigation: clamp posterior to [0.5, 1.5]
    posterior = max(0.5, min(1.5, posterior))
    effective_weight = prior * posterior

    weights_used.append({
        "role": vote["role"],
        "prior": prior,
        "posterior_raw": vote.get("posterior_weight", 1.0),
        "posterior_clamped": posterior,
        "effective": effective_weight
    })

    dist = vote["distribution"]
    for tier in tiers:
        aggregated[tier] += dist.get(tier, 0.0) * effective_weight
    total_weight += effective_weight

# Normalize
if total_weight > 0:
    for tier in tiers:
        aggregated[tier] /= total_weight

# Compute majority distribution for dissent check
majority = aggregated.copy()

for vote in votes:
    dist = vote["distribution"]
    # L1 distance from majority
    l1 = sum(abs(dist.get(t, 0.0) - majority[t]) for t in tiers)
    if l1 > 0.3:
        dissent.append({
            "role": vote["role"],
            "l1_distance": round(l1, 4),
            "distribution": dist
        })

result = {
    "aggregated": {t: round(v, 6) for t, v in aggregated.items()},
    "dissent": dissent,
    "weights_used": weights_used,
    "total_weight": round(total_weight, 4)
}

with open("${OUTPUT_FILE}", "w") as f:
    json.dump(result, f, indent=2)
PYEOF
```

#### `bin/invalidator-lint.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# invalidator-lint.sh — Check invalidator/falsifier specificity
# Usage: invalidator-lint.sh <text>
# Exit 0 = passes specificity check
# Exit 1 = too vague (missing numeric, temporal, or asset/event reference)
#
# Specificity requirements (M4 mitigation):
#   1. Contains at least one number (price level, percentage, count)
#   2. Contains at least one temporal reference (date, "by Q3", "within 30 days", etc.)
#   3. Contains at least one asset or event reference (ticker, "Fed", "CPI", etc.)

TEXT="${1:?Usage: invalidator-lint.sh <text-or-file>}"

# If argument is a file path, read contents
if [[ -f "$TEXT" ]]; then
  TEXT=$(cat "$TEXT")
fi

ERRORS=()

# Check 1: numeric reference
if ! echo "$TEXT" | grep -qE '[0-9]+(\.[0-9]+)?%?'; then
  ERRORS+=("Missing numeric reference (price level, percentage, or count)")
fi

# Check 2: temporal reference
TEMPORAL_PATTERN='(20[0-9]{2}|Q[1-4]|[Jj]an|[Ff]eb|[Mm]ar|[Aa]pr|[Mm]ay|[Jj]un|[Jj]ul|[Aa]ug|[Ss]ep|[Oo]ct|[Nn]ov|[Dd]ec|within [0-9]+ (day|week|month)|by (end of|mid-)|before |after |next [0-9]+ (day|week|month)|[0-9]+ (day|week|month)s?)'
if ! echo "$TEXT" | grep -qE "$TEMPORAL_PATTERN"; then
  ERRORS+=("Missing temporal reference (date, quarter, or timeframe)")
fi

# Check 3: asset or event reference
ASSET_PATTERN='(NDX|SPX|RUT|VIX|HSI|HSCEI|CSI300|CYB|DXY|CNH|GLD|ZB|WTI|BTC|NASDAQ|S&P|Fed|ECB|PBOC|BOJ|CPI|GDP|NFP|PMI|ISM|FOMC|earnings|rate (cut|hike)|tariff|sanctions|oil|gold|dollar|yuan|bitcoin|treasury)'
if ! echo "$TEXT" | grep -qiE "$ASSET_PATTERN"; then
  ERRORS+=("Missing asset or event reference (ticker, institution, or macro indicator)")
fi

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "FAIL: Invalidator lacks specificity"
  for err in "${ERRORS[@]}"; do
    echo "  - $err"
  done
  echo ""
  echo "Invalidator text: $TEXT"
  echo ""
  echo "A valid invalidator must contain:"
  echo "  1. A numeric reference (e.g., 'drops below 4500', 'exceeds 5%')"
  echo "  2. A temporal reference (e.g., 'by Q3 2026', 'within 30 days')"
  echo "  3. An asset/event reference (e.g., 'SPX', 'Fed rate cut', 'CPI')"
  exit 1
fi

echo "PASS: Invalidator meets specificity requirements"
exit 0
```

#### `bin/forecast-render.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# forecast-render.sh — Render forecast.jsonl to human-readable forecast.md with ASCII bars
# Usage: forecast-render.sh <opc-ir-home>

OPC_IR_HOME="${1:?Usage: forecast-render.sh <opc-ir-home>}"
FORECAST_JSONL="$OPC_IR_HOME/forecast/forecast.jsonl"
FORECAST_MD="$OPC_IR_HOME/forecast/forecast.md"

if [[ ! -f "$FORECAST_JSONL" ]]; then
  echo "Error: $FORECAST_JSONL not found" >&2
  exit 1
fi

# Read last line of forecast.jsonl (most recent forecast)
LATEST=$(tail -1 "$FORECAST_JSONL")

TIMESTAMP=$(echo "$LATEST" | jq -r '.timestamp')
RUN_ID=$(echo "$LATEST" | jq -r '.run_id')
WM_REF=$(echo "$LATEST" | jq -r '.world_model_ref')

cat > "$FORECAST_MD" << HEADER
---
generated_at: $TIMESTAMP
run_id: $RUN_ID
world_model_ref: $WM_REF
---

# Macro Forecast

> Generated: $TIMESTAMP
> World-Model reference: $WM_REF

HEADER

# Render each asset
ASSETS=$(echo "$LATEST" | jq -r '.forecasts | keys[]' | sort)

for asset in $ASSETS; do
  echo "## $asset" >> "$FORECAST_MD"
  echo "" >> "$FORECAST_MD"
  
  HORIZONS=$(echo "$LATEST" | jq -r ".forecasts[\"$asset\"] | keys[]" | sort)
  
  for horizon in $HORIZONS; do
    echo "### $horizon" >> "$FORECAST_MD"
    echo '```' >> "$FORECAST_MD"
    
    for tier in strongly_bearish bearish neutral bullish strongly_bullish; do
      prob=$(echo "$LATEST" | jq -r ".forecasts[\"$asset\"][\"$horizon\"][\"$tier\"]")
      # Convert probability to bar width (max 20 chars)
      bar_len=$(python3 -c "print(int(round($prob * 20)))")
      bar=$(printf '▓%.0s' $(seq 1 "$bar_len") 2>/dev/null || true)
      pad=$(printf '░%.0s' $(seq 1 $((20 - bar_len))) 2>/dev/null || true)
      # Format tier name to 18 chars
      tier_display=$(printf "%-18s" "$tier")
      prob_display=$(printf "%5.1f%%" "$(python3 -c "print($prob * 100)")")
      echo "$tier_display $bar$pad $prob_display" >> "$FORECAST_MD"
    done
    
    echo '```' >> "$FORECAST_MD"
    echo "" >> "$FORECAST_MD"
  done
  
  # Show invalidator
  INVALIDATOR=$(echo "$LATEST" | jq -r ".invalidators[\"$asset\"] // empty" 2>/dev/null)
  if [[ -n "$INVALIDATOR" && "$INVALIDATOR" != "null" ]]; then
    echo "**Invalidator:** $INVALIDATOR" >> "$FORECAST_MD"
    echo "" >> "$FORECAST_MD"
  fi
done

# Dissent section
DISSENT_COUNT=$(echo "$LATEST" | jq '.strategist_dissent | length')
if [[ "$DISSENT_COUNT" -gt 0 ]]; then
  echo "---" >> "$FORECAST_MD"
  echo "" >> "$FORECAST_MD"
  echo "## Strategist Dissent" >> "$FORECAST_MD"
  echo "" >> "$FORECAST_MD"
  echo "$LATEST" | jq -r '.strategist_dissent[] | "- **\(.strategist)** on \(.asset)/\(.horizon): L1 distance \(.l1_distance | tostring)"' >> "$FORECAST_MD"
  echo "" >> "$FORECAST_MD"
fi

echo "Forecast rendered to $FORECAST_MD"
```

#### `bin/verdict-render-digest.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# verdict-render-digest.sh — Render verdicts.jsonl to digest.md
# Usage: verdict-render-digest.sh <opc-ir-home>

OPC_IR_HOME="${1:?Usage: verdict-render-digest.sh <opc-ir-home>}"
VERDICTS_JSONL="$OPC_IR_HOME/verdict/verdicts.jsonl"
DIGEST_MD="$OPC_IR_HOME/verdict/digest.md"

if [[ ! -f "$VERDICTS_JSONL" ]]; then
  echo "Error: $VERDICTS_JSONL not found" >&2
  exit 1
fi

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

cat > "$DIGEST_MD" << 'HEADER'
---
generated_at: TIMESTAMP_PLACEHOLDER
---

# OPC-IR Verdict Digest

> **DISCLAIMER: This is research analysis, not investment advice.** The outputs below are
> generated by an automated multi-role voting system using publicly available information.
> They do not constitute financial advice, recommendations, or solicitations. Past
> performance of the calibration system does not guarantee future accuracy. Always conduct
> your own research and consult qualified financial advisors before making investment decisions.

HEADER

sed -i.bak "s/TIMESTAMP_PLACEHOLDER/$TIMESTAMP/" "$DIGEST_MD" && rm -f "$DIGEST_MD.bak"

# Process each verdict (latest per ticker)
declare -A LATEST_VERDICTS
while IFS= read -r line; do
  ticker=$(echo "$line" | jq -r '.ticker')
  LATEST_VERDICTS["$ticker"]="$line"
done < "$VERDICTS_JSONL"

for ticker in $(echo "${!LATEST_VERDICTS[@]}" | tr ' ' '\n' | sort); do
  verdict="${LATEST_VERDICTS[$ticker]}"
  direction=$(echo "$verdict" | jq -r '.consensus.direction')
  conviction=$(echo "$verdict" | jq -r '.consensus.conviction')
  horizon=$(echo "$verdict" | jq -r '.consensus.horizon')
  ts=$(echo "$verdict" | jq -r '.timestamp')
  
  # Direction emoji
  case "$direction" in
    long) dir_emoji="🟢 LONG" ;;
    short) dir_emoji="🔴 SHORT" ;;
    neutral) dir_emoji="⚪ NEUTRAL" ;;
    split) dir_emoji="⚠️ SPLIT" ;;
    *) dir_emoji="❓ $direction" ;;
  esac
  
  cat >> "$DIGEST_MD" << VERDICT

## $ticker — $dir_emoji

- **Conviction:** $(python3 -c "print(f'{$conviction:.0%}')")
- **Horizon:** $horizon
- **Updated:** $ts

VERDICT

  # Split warning
  if [[ "$direction" == "split" ]]; then
    echo "> ⚠️ **Split verdict**: The voting panel is significantly divided on this asset. Exercise additional caution." >> "$DIGEST_MD"
    echo "" >> "$DIGEST_MD"
  fi

  # Dissent section
  DISSENT_COUNT=$(echo "$verdict" | jq '.preserved_dissent | length')
  if [[ "$DISSENT_COUNT" -gt 0 ]]; then
    echo "### Minority Positions" >> "$DIGEST_MD"
    echo "" >> "$DIGEST_MD"
    echo "$verdict" | jq -r '.preserved_dissent[] | "- **\(.role)** (\(.direction)): \(.reasoning_summary)"' >> "$DIGEST_MD"
    echo "" >> "$DIGEST_MD"
  fi
  
  # Falsifiers
  echo "### Active Falsifiers" >> "$DIGEST_MD"
  echo "" >> "$DIGEST_MD"
  echo "$verdict" | jq -r '.falsifiers[] | "- [\(.role)] \(.condition)"' >> "$DIGEST_MD"
  echo "" >> "$DIGEST_MD"
done

echo "Digest rendered to $DIGEST_MD"
```

#### `bin/falsifier-lint.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# falsifier-lint.sh — Same specificity check as invalidator-lint, for verdict falsifiers
# Usage: falsifier-lint.sh <text-or-file> [--retry-counter <file>]
# Exit 0 = passes; Exit 1 = fails
# With --retry-counter: increments counter in file, exits 2 if counter >= 2

TEXT="${1:?Usage: falsifier-lint.sh <text-or-file> [--retry-counter <file>]}"
RETRY_COUNTER=""

shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --retry-counter)
      RETRY_COUNTER="${2:?--retry-counter requires a file path}"
      shift 2
      ;;
    *)
      echo "Unknown flag: $1" >&2
      exit 1
      ;;
  esac
done

# If file, read contents
if [[ -f "$TEXT" ]]; then
  TEXT=$(cat "$TEXT")
fi

# Reuse invalidator-lint logic
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! "$SCRIPT_DIR/invalidator-lint.sh" "$TEXT" 2>&1; then
  # Lint failed
  if [[ -n "$RETRY_COUNTER" ]]; then
    # Increment retry counter
    if [[ -f "$RETRY_COUNTER" ]]; then
      COUNT=$(cat "$RETRY_COUNTER")
    else
      COUNT=0
    fi
    COUNT=$((COUNT + 1))
    echo "$COUNT" > "$RETRY_COUNTER"
    
    if [[ "$COUNT" -ge 2 ]]; then
      echo "FATAL: Falsifier lint failed after $COUNT retries (max 2)" >&2
      exit 2
    fi
    echo "Retry $COUNT/2 — falsifier must meet specificity requirements" >&2
  fi
  exit 1
fi
exit 0
```

### B.4 Defaults Configuration

#### `defaults/watch-assets.yaml`

```yaml
# OPC-IR Watch Assets — 14 cross-market instruments
# US + China scope (Phase 1 geographic focus)
assets:
  - symbol: NDX
    name: NASDAQ-100
    class: equity-index
    region: US
  - symbol: SPX
    name: S&P 500
    class: equity-index
    region: US
  - symbol: RUT
    name: Russell 2000
    class: equity-index
    region: US
  - symbol: VIX
    name: CBOE Volatility Index
    class: volatility
    region: US
  - symbol: HSI
    name: Hang Seng Index
    class: equity-index
    region: CN
  - symbol: HSCEI
    name: Hang Seng China Enterprises
    class: equity-index
    region: CN
  - symbol: CSI300
    name: CSI 300
    class: equity-index
    region: CN
  - symbol: CYB
    name: WisdomTree Chinese Yuan
    class: currency-etf
    region: CN
  - symbol: DXY
    name: US Dollar Index
    class: currency
    region: US
  - symbol: CNH
    name: Offshore Chinese Yuan
    class: currency
    region: CN
  - symbol: GLD
    name: Gold (SPDR)
    class: commodity
    region: global
  - symbol: ZB
    name: US Treasury Bond Futures
    class: fixed-income
    region: US
  - symbol: WTI
    name: Crude Oil WTI
    class: commodity
    region: global
  - symbol: BTC
    name: Bitcoin
    class: crypto
    region: global
```

#### `defaults/dimension-weights.yaml`

```yaml
# OPC-IR Macro Dimension Weights
# Used by triage classifier and watcher dispatch
dimensions:
  politics:
    weight: 1.5
    description: Government policy, regulation, geopolitics, elections, sanctions
  econ-finance:
    weight: 1.5
    description: Central bank policy, interest rates, inflation, employment, GDP
  military:
    weight: 1.0
    description: Armed conflicts, defense spending, arms deals, military exercises
  tech-ai:
    weight: 1.3
    sub_weight_ai: 0.6
    description: Technology sector, AI developments, chip industry, tech regulation
  humanities:
    weight: 0.8
    description: Social movements, demographics, education, cultural shifts
  energy-commodity:
    weight: 1.0
    description: Oil, gas, metals, agriculture, energy policy, supply chains
  corp-fundamentals:
    weight: 1.2
    description: Earnings, M&A, IPOs, bankruptcies, management changes
```

#### `defaults/role-weights.yaml`

```yaml
# OPC-IR Role Weights — Cold-start priors
# All posterior_weight fields are absent (cold-start: treated as 1.0)
# Posteriors only written by calibration after N>=30 samples per role

schools:
  fundamental-analyst:
    prior_weight: 1.0
  technical-analyst:
    prior_weight: 1.0
  macro-economist:
    prior_weight: 1.0
  quant-modeler:
    prior_weight: 1.0
  behavioral-analyst:
    prior_weight: 1.0

advocates:
  bull-advocate:
    prior_weight: 0.5
  bear-advocate:
    prior_weight: 0.5

forecast:
  macro-strategist:
    prior_weight: 1.0
  cross-asset-allocator:
    prior_weight: 1.0
  regime-detector:
    prior_weight: 1.0
  historical-analogist:
    prior_weight: 1.0
  contrarian-strategist:
    prior_weight: 1.0

watchers:
  politics-watcher:
    prior_weight: 1.0
  econ-finance-watcher:
    prior_weight: 1.0
  military-watcher:
    prior_weight: 1.0
  tech-ai-watcher:
    prior_weight: 1.0
  humanities-watcher:
    prior_weight: 1.0
  energy-commodity-watcher:
    prior_weight: 1.0
  corp-fundamentals-watcher:
    prior_weight: 1.0
```

#### `defaults/horizons.yaml`

```yaml
# OPC-IR Forecast Horizons
horizons:
  - id: 1d
    label: 1 Day
    calendar_days: 1
    description: Next trading session
  - id: 1w
    label: 1 Week
    calendar_days: 7
    description: Next 5 trading sessions
  - id: 1m
    label: 1 Month
    calendar_days: 30
    description: Next ~22 trading sessions
  - id: 3m
    label: 3 Months
    calendar_days: 90
    description: Next quarter
```

#### `defaults/triage-thresholds.yaml`

```yaml
# OPC-IR Triage Classifier Thresholds
watcher_route_threshold: 0.6
hard_rule_verdict_threshold: 0.85
hard_rules:
  - pattern: "central bank policy decision"
    description: "Fed, ECB, PBOC, BOJ rate decisions or QE announcements"
  - pattern: "war declaration or ceasefire"
    description: "Armed conflict escalation or de-escalation"
  - pattern: "earnings of NDX top-10 constituent"
    description: "AAPL, MSFT, NVDA, AMZN, META, GOOG, AVGO, TSLA, COST, NFLX"
  - pattern: "circuit breaker or market halt"
    description: "Exchange trading halt due to volatility limits"
max_batch_size: 20
```

#### `defaults/sources.yaml`

```yaml
# OPC-IR Event Sources — RSS feeds for Phase 1-3
# type: rss (default), api (Phase 5 premium), scrape (deprecated)
sources:
  - id: reuters-business
    url: https://feeds.reuters.com/reuters/businessNews
    type: rss
    region: global
    timeout_seconds: 10
  - id: reuters-markets
    url: https://feeds.reuters.com/reuters/marketsNews
    type: rss
    region: global
    timeout_seconds: 10
  - id: ap-business
    url: https://feeds.apnews.com/rss/business
    type: rss
    region: US
    timeout_seconds: 10
  - id: bbc-business
    url: https://feeds.bbci.co.uk/news/business/rss.xml
    type: rss
    region: global
    timeout_seconds: 10
  - id: cnbc-economy
    url: https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=20910258
    type: rss
    region: US
    timeout_seconds: 10
  - id: ft-markets
    url: https://www.ft.com/rss/markets
    type: rss
    region: global
    timeout_seconds: 10
  - id: bloomberg-markets
    url: https://feeds.bloomberg.com/markets/news.rss
    type: rss
    region: global
    timeout_seconds: 10
  - id: xinhua-english
    url: https://www.news.cn/english/rss/worldrss.xml
    type: rss
    region: CN
    timeout_seconds: 15
  - id: scmp-economy
    url: https://www.scmp.com/rss/91/feed
    type: rss
    region: CN
    timeout_seconds: 15
  - id: fed-press
    url: https://www.federalreserve.gov/feeds/press_all.xml
    type: rss
    region: US
    timeout_seconds: 10
  - id: ecb-press
    url: https://www.ecb.europa.eu/rss/press.html
    type: rss
    region: EU
    timeout_seconds: 10
```

### B.5 Test Files

#### `tests/scaffold.bats`

```bash
#!/usr/bin/env bats

# scaffold.bats — Validate OPC-IR plugin structure (M1.1)

@test "plugin.json exists and is valid JSON" {
  jq '.' .claude-plugin/plugin.json
}

@test "plugin.json has required fields" {
  name=$(jq -r '.name' .claude-plugin/plugin.json)
  [ "$name" = "opc-ir" ]
  
  version=$(jq -r '.version' .claude-plugin/plugin.json)
  [ -n "$version" ]
  
  description=$(jq -r '.description' .claude-plugin/plugin.json)
  [ ${#description} -gt 10 ]
}

@test "7 command files exist" {
  count=$(ls commands/opc-ir-*.md | wc -l | tr -d ' ')
  [ "$count" -eq 7 ]
}

@test "each command has YAML frontmatter with description >= 10 chars" {
  for cmd in commands/opc-ir-*.md; do
    # Extract frontmatter description
    desc=$(sed -n '/^---$/,/^---$/p' "$cmd" | grep 'description:' | sed 's/description: *//' | tr -d '"')
    [ ${#desc} -ge 10 ] || { echo "FAIL: $cmd description too short: '$desc'"; return 1; }
  done
}

@test "agent directory exists" {
  [ -d "agents" ]
}

@test "skill file exists" {
  [ -f "skills/opc-ir/skill.md" ]
}

@test "LICENSE file exists" {
  [ -f "LICENSE" ]
}

@test ".gitignore excludes runtime data" {
  grep -q '\.opc-ir' .gitignore || grep -q 'opc-ir' .gitignore
}
```

#### `tests/lib/check-frontmatter.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# check-frontmatter.sh — Validate YAML frontmatter in a markdown file
# Usage: check-frontmatter.sh <file.md> [required-key ...]
# Exit 0 = valid, Exit 1 = invalid

FILE="${1:?Usage: check-frontmatter.sh <file.md> [required-key ...]}"
shift

if [[ ! -f "$FILE" ]]; then
  echo "Error: file not found: $FILE" >&2
  exit 1
fi

# Extract frontmatter between first pair of ---
FRONTMATTER=$(sed -n '1{/^---$/!q};1,/^---$/p' "$FILE" | sed '1d;$d')

if [[ -z "$FRONTMATTER" ]]; then
  echo "Error: no YAML frontmatter found in $FILE" >&2
  exit 1
fi

# Validate YAML
echo "$FRONTMATTER" | yq '.' > /dev/null 2>&1 || {
  echo "Error: invalid YAML frontmatter in $FILE" >&2
  exit 1
}

# Check required keys
for key in "$@"; do
  VALUE=$(echo "$FRONTMATTER" | yq ".$key" 2>/dev/null)
  if [[ -z "$VALUE" || "$VALUE" == "null" ]]; then
    echo "Error: required key '$key' missing in frontmatter of $FILE" >&2
    exit 1
  fi
done

echo "OK: $FILE"
```

#### `tests/roles.bats`

```bash
#!/usr/bin/env bats

# roles.bats — Validate role file counts and structure (M1.2)

@test "5 school roles exist" {
  count=$(find roles/_schools -name '*.md' | wc -l | tr -d ' ')
  [ "$count" -eq 5 ]
}

@test "2 advocate roles exist" {
  count=$(find roles/_advocates -name '*.md' | wc -l | tr -d ' ')
  [ "$count" -eq 2 ]
}

@test "5 forecast strategist roles exist" {
  count=$(find roles/_forecast -name '*.md' | wc -l | tr -d ' ')
  [ "$count" -eq 5 ]
}

@test "each role has tags: array in frontmatter" {
  for role in roles/_schools/*.md roles/_advocates/*.md roles/_forecast/*.md; do
    bash tests/lib/check-frontmatter.sh "$role" tags || {
      echo "FAIL: $role missing tags"
      return 1
    }
  done
}

@test "school role names match spec" {
  for name in fundamental-analyst technical-analyst macro-economist quant-modeler behavioral-analyst; do
    [ -f "roles/_schools/$name.md" ] || { echo "Missing: roles/_schools/$name.md"; return 1; }
  done
}

@test "advocate role names match spec" {
  for name in bull-advocate bear-advocate; do
    [ -f "roles/_advocates/$name.md" ] || { echo "Missing: roles/_advocates/$name.md"; return 1; }
  done
}

@test "forecast strategist names match spec" {
  for name in macro-strategist cross-asset-allocator regime-detector historical-analogist contrarian-strategist; do
    [ -f "roles/_forecast/$name.md" ] || { echo "Missing: roles/_forecast/$name.md"; return 1; }
  done
}

@test "all defaults YAML files parse" {
  for f in defaults/*.yaml; do
    yq '.' "$f" > /dev/null || { echo "FAIL: $f does not parse"; return 1; }
  done
}

@test "role-weights.yaml has prior_weight 1.0 for all schools" {
  for school in fundamental-analyst technical-analyst macro-economist quant-modeler behavioral-analyst; do
    weight=$(yq ".schools[\"$school\"].prior_weight" defaults/role-weights.yaml)
    [ "$weight" = "1" ] || [ "$weight" = "1.0" ] || { echo "FAIL: $school prior=$weight"; return 1; }
  done
}

@test "role-weights.yaml has no posterior_weight (cold-start)" {
  # Should not contain posterior_weight key at all
  result=$(yq '.. | select(has("posterior_weight")) | .posterior_weight' defaults/role-weights.yaml 2>/dev/null || true)
  [ -z "$result" ] || { echo "FAIL: posterior_weight found in cold-start config"; return 1; }
}
```

#### `tests/forked-meta.bats`

```bash
#!/usr/bin/env bats

# forked-meta.bats — Validate OPC-forked files carry lineage frontmatter (M1.2)

FORKED_FILES=(
  "pipeline/discussion-protocol.md"
  "pipeline/role-evaluator-prompt.md"
  "pipeline/gate-protocol.md"
  "pipeline/role-spec.md"
)

@test "forked files have forked-from frontmatter" {
  for f in "${FORKED_FILES[@]}"; do
    [ -f "$f" ] || { echo "Missing: $f"; return 1; }
    grep -q 'forked-from:' "$f" || { echo "FAIL: $f missing forked-from"; return 1; }
  done
}

@test "forked files have forked-at: 2026-05-08" {
  for f in "${FORKED_FILES[@]}"; do
    grep -q 'forked-at:.*2026-05-08' "$f" || { echo "FAIL: $f missing forked-at date"; return 1; }
  done
}

@test "forked files have modifications: list" {
  for f in "${FORKED_FILES[@]}"; do
    grep -q 'modifications:' "$f" || { echo "FAIL: $f missing modifications list"; return 1; }
  done
}

@test "native pipeline files do NOT have forked-from" {
  NATIVE_FILES=(
    "pipeline/forecast-protocol.md"
    "pipeline/vote-protocol.md"
    "pipeline/verdict-protocol.md"
    "pipeline/invalidator-lint.md"
  )
  for f in "${NATIVE_FILES[@]}"; do
    if [ -f "$f" ]; then
      ! grep -q 'forked-from:' "$f" || { echo "FAIL: native file $f should not have forked-from"; return 1; }
    fi
  done
}
```

#### `tests/invalidator-lint.bats`

```bash
#!/usr/bin/env bats

# invalidator-lint.bats — Validate invalidator specificity check (M1.3 + M4 mitigation)

@test "good invalidator passes: specific with number, date, asset" {
  run bin/invalidator-lint.sh "If SPX drops below 4200 by Q3 2026, this forecast is invalidated"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "good invalidator passes: Fed rate cut" {
  run bin/invalidator-lint.sh "Invalidated if Fed cuts rates by more than 50bps before December 2026"
  [ "$status" -eq 0 ]
}

@test "bad invalidator fails: vague 'if X significantly changes'" {
  run bin/invalidator-lint.sh "If market conditions significantly change"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL"* ]]
}

@test "bad invalidator fails: missing numeric" {
  run bin/invalidator-lint.sh "If SPX drops by Q3 2026"
  [ "$status" -eq 1 ]
  [[ "$output" == *"numeric"* ]]
}

@test "bad invalidator fails: missing temporal" {
  run bin/invalidator-lint.sh "If SPX drops below 4200"
  [ "$status" -eq 1 ]
  [[ "$output" == *"temporal"* ]]
}

@test "bad invalidator fails: missing asset" {
  run bin/invalidator-lint.sh "If the index drops below 4200 by Q3 2026"
  [ "$status" -eq 1 ]
  [[ "$output" == *"asset"* ]]
}

@test "good invalidator from file" {
  tmp=$(mktemp)
  echo "NDX falls below 18000 within 30 days of this forecast" > "$tmp"
  run bin/invalidator-lint.sh "$tmp"
  [ "$status" -eq 0 ]
  rm -f "$tmp"
}
```

#### `tests/mitigations.bats`

```bash
#!/usr/bin/env bats

# mitigations.bats — Validate all Phase 1 mandatory risk mitigations (M1.5)

@test "M3: vote-aggregate clamps posterior 5.0 to 1.5" {
  # Create test votes with extreme posterior
  tmp_dir=$(mktemp -d)
  cat > "$tmp_dir/votes.json" << 'EOF'
[
  {
    "role": "test-role",
    "distribution": {"strongly_bearish": 0.1, "bearish": 0.2, "neutral": 0.4, "bullish": 0.2, "strongly_bullish": 0.1},
    "prior_weight": 1.0,
    "posterior_weight": 5.0
  }
]
EOF
  cat > "$tmp_dir/weights.yaml" << 'EOF'
schools:
  test-role:
    prior_weight: 1.0
EOF
  
  bin/vote-aggregate.sh "$tmp_dir/votes.json" "$tmp_dir/weights.yaml" "$tmp_dir/output.json"
  
  # Check that the clamped posterior is 1.5, not 5.0
  clamped=$(jq '.weights_used[0].posterior_clamped' "$tmp_dir/output.json")
  [ "$clamped" = "1.5" ]
  
  rm -rf "$tmp_dir"
}

@test "M3: vote-aggregate clamps posterior 0.0 to 0.5" {
  tmp_dir=$(mktemp -d)
  cat > "$tmp_dir/votes.json" << 'EOF'
[
  {
    "role": "test-role",
    "distribution": {"strongly_bearish": 0.1, "bearish": 0.2, "neutral": 0.4, "bullish": 0.2, "strongly_bullish": 0.1},
    "prior_weight": 1.0,
    "posterior_weight": 0.0
  }
]
EOF
  cat > "$tmp_dir/weights.yaml" << 'EOF'
schools:
  test-role:
    prior_weight: 1.0
EOF
  
  bin/vote-aggregate.sh "$tmp_dir/votes.json" "$tmp_dir/weights.yaml" "$tmp_dir/output.json"
  clamped=$(jq '.weights_used[0].posterior_clamped' "$tmp_dir/output.json")
  [ "$clamped" = "0.5" ]
  
  rm -rf "$tmp_dir"
}

@test "M4: invalidator-lint requires specificity (numeric+temporal+asset)" {
  # Good: passes
  run bin/invalidator-lint.sh "If SPX drops below 4200 by Q3 2026"
  [ "$status" -eq 0 ]
  
  # Bad: fails
  run bin/invalidator-lint.sh "If market conditions significantly change"
  [ "$status" -eq 1 ]
}

@test "P1: disclaimer present in verdict-protocol template" {
  grep -qi "research analysis, not investment advice" pipeline/verdict-protocol.md
}

@test "P2: regime_marker field in forecast schema" {
  jq '.properties.regime_marker' tests/schemas/forecast.schema.json | grep -q 'string'
}

@test "P2: regime_marker field in verdict schema" {
  jq '.properties.regime_marker' tests/schemas/verdict.schema.json | grep -q 'string'
}

@test "D2: README has Limitations section" {
  grep -c '## Limitations' README.md
}

@test "ARCHITECTURE.md has mitigation cross-reference" {
  grep -c 'M3' docs/ARCHITECTURE.md
  grep -c 'M4' docs/ARCHITECTURE.md
  grep -c 'P1' docs/ARCHITECTURE.md
  grep -c 'P2' docs/ARCHITECTURE.md
  grep -c 'D2' docs/ARCHITECTURE.md
}
```

### B.6 Pre-commit Hook

#### `.git/hooks/pre-commit`

```bash
#!/usr/bin/env bash
set -euo pipefail

# OPC-IR pre-commit hook — runs shellcheck on staged .sh files

STAGED_SH=$(git diff --cached --name-only --diff-filter=ACM | grep '\.sh$' || true)

if [[ -n "$STAGED_SH" ]]; then
  echo "Running shellcheck on staged .sh files..."
  FAILED=0
  for f in $STAGED_SH; do
    if ! shellcheck -S warning "$f"; then
      FAILED=1
    fi
  done
  if [[ "$FAILED" -eq 1 ]]; then
    echo "shellcheck failed — fix warnings before committing"
    exit 1
  fi
  echo "shellcheck passed"
fi

# Validate YAML frontmatter in staged .md files
STAGED_MD=$(git diff --cached --name-only --diff-filter=ACM | grep '\.md$' || true)

if [[ -n "$STAGED_MD" ]]; then
  for f in $STAGED_MD; do
    # Only check files with frontmatter (start with ---)
    if head -1 "$f" | grep -q '^---$'; then
      if [[ -x "tests/lib/check-frontmatter.sh" ]]; then
        tests/lib/check-frontmatter.sh "$f" || {
          echo "Frontmatter validation failed: $f"
          exit 1
        }
      fi
    fi
  done
fi
```

### B.7 Sample Role File (template for all 12 Phase 1 roles)

#### `roles/_schools/fundamental-analyst.md`

```markdown
---
name: fundamental-analyst
tags: [review, verdict]
school: true
description: Evaluates assets through financial statements, valuation metrics, and corporate health
---

# Fundamental Analyst

## Identity

You are a fundamental analyst specializing in equity and macro valuation. You evaluate assets by analyzing financial statements, earnings quality, balance sheet health, cash flow sustainability, and intrinsic value relative to market price.

## Expertise

- Discounted cash flow (DCF) and comparable company analysis
- Earnings quality assessment (accruals, revenue recognition)
- Balance sheet stress testing (debt maturity, liquidity ratios)
- Margin analysis and operating leverage
- Dividend sustainability and capital allocation
- Sector-specific valuation multiples

## When to Include

Include this role when:
- Evaluating a specific equity or equity index verdict
- Assessing corporate earnings impact on broader market
- Analyzing valuation extremes (bubble/crash signals)
- Any verdict involving corp-fundamentals dimension events

## Anti-Patterns

- Do NOT ignore macro context — fundamentals exist within a macro regime
- Do NOT rely solely on trailing metrics — forward estimates and guidance matter
- Do NOT dismiss market price as "irrational" without a specific catalyst timeline
- Do NOT produce a falsifier that lacks numeric price/valuation triggers

## Output Format

Your evaluation must include:
1. **Stance**: long / short / neutral
2. **Thesis**: 2-3 sentence core argument with specific data points
3. **Falsifier** (MANDATORY): specific condition that would invalidate your thesis
   - Must include: numeric threshold + temporal bound + asset/event reference
   - Example: "Invalidated if NDX forward P/E exceeds 35x before Q4 2026"
   - NOT acceptable: "Invalidated if fundamentals deteriorate significantly"
4. **Key risks acknowledged**: risks to your thesis you're aware of but believe are outweighed
```

### B.8 Fixture Files

#### `tests/fixtures/world-model-sample.md`

```markdown
---
updated_at: "2026-05-07T18:00:00Z"
evolved_from_run: "sample-run-001"
schema_version: 1
---

# World-Model Snapshot

## Politics
- US-China relations tense following new semiconductor export controls
- US presidential cycle: incumbent trailing in polls, policy uncertainty elevated
- EU regulatory push on AI accelerating

## Econ-finance
- Fed holding rates at 4.75%, market pricing 2 cuts by year-end
- US CPI trending down to 2.8% YoY, core sticky at 3.1%
- China PBOC cut RRR by 25bps, stimulus measures expanding
- US unemployment at 4.1%, labor market softening gradually

## Military
- Middle East tensions elevated but contained; no major escalation
- South China Sea patrol frequency increased 15% QoQ

## Tech-AI
- AI capex cycle accelerating: NVDA, MSFT, GOOG each raised guidance
- AI regulation bills advancing in EU and US Congress
- Chip shortage easing for mature nodes; leading-edge still tight

## Humanities
- Remote work adoption stabilizing at ~30% of knowledge workers
- AI anxiety index rising in consumer surveys

## Energy-commodity
- WTI range-bound $72-78; OPEC+ maintaining cuts
- Gold at $2,400 on geopolitical hedging; central bank buying strong
- Natural gas normalized after warm winter

## Corp-fundamentals
- Q1 2026 earnings: 78% of SPX beat estimates, revenue growth 6.2% YoY
- NDX top-10 aggregate revenue growth 14% YoY, margin expansion 120bps
- Small-cap (RUT) earnings declining -3% YoY, credit concerns mounting
```

#### `tests/fixtures/strategist-1.json` (macro-strategist sample)

```json
{
  "role": "macro-strategist",
  "forecasts": {
    "NDX": {
      "1d": {"strongly_bearish": 0.05, "bearish": 0.15, "neutral": 0.50, "bullish": 0.25, "strongly_bullish": 0.05},
      "1w": {"strongly_bearish": 0.05, "bearish": 0.20, "neutral": 0.40, "bullish": 0.25, "strongly_bullish": 0.10},
      "1m": {"strongly_bearish": 0.10, "bearish": 0.20, "neutral": 0.30, "bullish": 0.25, "strongly_bullish": 0.15},
      "3m": {"strongly_bearish": 0.10, "bearish": 0.15, "neutral": 0.25, "bullish": 0.30, "strongly_bullish": 0.20}
    },
    "SPX": {
      "1d": {"strongly_bearish": 0.05, "bearish": 0.15, "neutral": 0.55, "bullish": 0.20, "strongly_bullish": 0.05},
      "1w": {"strongly_bearish": 0.05, "bearish": 0.20, "neutral": 0.40, "bullish": 0.25, "strongly_bullish": 0.10},
      "1m": {"strongly_bearish": 0.10, "bearish": 0.20, "neutral": 0.35, "bullish": 0.25, "strongly_bullish": 0.10},
      "3m": {"strongly_bearish": 0.10, "bearish": 0.15, "neutral": 0.30, "bullish": 0.30, "strongly_bullish": 0.15}
    }
  },
  "invalidators": {
    "NDX": {
      "1d": "NDX closes below 19500 on May 9 2026 following NVDA earnings miss",
      "1w": "NDX falls below 19000 by May 15 2026 on broader tech selloff",
      "1m": "NDX drops below 18000 by June 8 2026 on Fed hawkish surprise at June FOMC",
      "3m": "NDX below 17000 by August 2026 on AI capex cycle reversal signal"
    },
    "SPX": {
      "1d": "SPX drops below 5200 on May 9 2026 on labor market shock",
      "1w": "SPX falls below 5100 by May 15 2026 on CPI upside surprise",
      "1m": "SPX below 4900 by June 2026 on credit event in commercial real estate",
      "3m": "SPX below 4600 by August 2026 on recession confirmation (2 consecutive negative GDP)"
    }
  },
  "prior_weight": 1.0,
  "posterior_weight": 1.0
}
```

---

## Appendix C: Phase 2–5 Key File Specifications

Detailed specifications for Phases 2–5 are in their respective plan documents. This appendix provides a quick-reference listing of all files created in each phase.

### Phase 2 Files (Memory Layer)

| File | Type | Milestone |
|---|---|---|
| `agents/triage-classifier.md` | agent | M2.1 |
| `roles/_watchers/politics-watcher.md` | role | M2.2 |
| `roles/_watchers/econ-finance-watcher.md` | role | M2.2 |
| `roles/_watchers/military-watcher.md` | role | M2.2 |
| `roles/_watchers/tech-ai-watcher.md` | role | M2.2 |
| `roles/_watchers/humanities-watcher.md` | role | M2.2 |
| `roles/_watchers/energy-commodity-watcher.md` | role | M2.2 |
| `roles/_watchers/corp-fundamentals-watcher.md` | role | M2.2 |
| `bin/evolve-synthesize.sh` | script | M2.3 |
| `tests/triage.bats` | test | M2.1 |
| `tests/watcher-dispatch.bats` | test | M2.2 |
| `tests/evolve.bats` | test | M2.3 |
| `tests/thesis-history.bats` | test | M2.4 |
| `tests/fixtures/sample-events-10.jsonl` | fixture | M2.1 |
| `tests/schemas/triage.schema.json` | schema | M2.1 |

### Phase 3 Files (Auto-loop Polish)

| File | Type | Milestone |
|---|---|---|
| `bin/fetch-rss.sh` | script | M3.1 |
| `tests/fixtures/rss/*.xml` | fixture | M3.1 |
| `tests/fetch-rss.bats` | test | M3.1 |
| `tests/trigger-consume.bats` | test | M3.3 |
| `tests/helper-commands.bats` | test | M3.4 |

### Phase 4 Files (Calibration)

| File | Type | Milestone |
|---|---|---|
| `bin/fetch-prices.sh` | script | M4.1 |
| `bin/ground-truth-linker.sh` | script | M4.1 |
| `bin/calibrate-posteriors.sh` | script | M4.3 |
| `bin/regime-detect.sh` | script | M4.4 |
| `bin/events-roll.sh` | script | M4.5 |
| `defaults/tier-boundaries.yaml` | config | M4.1 |
| `tests/price-truth.bats` | test | M4.1 |
| `tests/event-truth.bats` | test | M4.2 |
| `tests/calibration.bats` | test | M4.3 |
| `tests/regime.bats` | test | M4.4 |
| `tests/events-roll.bats` | test | M4.5 |
| `tests/fixtures/prices/*.json` | fixture | M4.1 |

### Phase 5 Files (Scheduling + Premium)

| File | Type | Milestone |
|---|---|---|
| `bin/scheduler-abstract.sh` | script | M5.1 |
| `bin/token-logger.sh` | script | M5.2 |
| `bin/integrity-check.sh` | script | M5.4 |
| `pipeline/scheduler-protocol.md` | protocol | M5.1 |
| `defaults/secrets.env.example` | config | M5.3 |
| `docs/PREMIUM-SOURCES.md` | doc | M5.3 |
| `tests/premium-sources.bats` | test | M5.3 |
| `tests/integrity.bats` | test | M5.4 |
