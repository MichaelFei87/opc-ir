# OPC-IR

**Investment Research via Multi-Role Independent Voting**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.0.1-orange.svg)](plugin.json)
[![Tests](https://img.shields.io/badge/tests-160%20passing-brightgreen.svg)](tests/)
[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-plugin-blueviolet.svg)](https://claude.ai)

OPC-IR is a [Claude Code](https://claude.ai) plugin that applies the [OPC (One Person Company)](https://github.com/iamtouchskyer/opc) methodology to macro investment research. It maintains a continuously evolving world-model, generates falsifiable forecasts, and calibrates itself against ground truth — all through independent multi-role voting where **the agent that produces a forecast never evaluates it**.

---

## Table of Contents

- [Why OPC-IR](#why-opc-ir)
- [Built on OPC](#built-on-opc)
- [Quick Start](#quick-start)
- [Architecture](#architecture)
- [Commands](#commands)
- [Pipeline Deep Dive](#pipeline-deep-dive)
- [Watch Assets](#watch-assets)
- [Roles](#roles)
- [Data Sources](#data-sources)
- [Configuration](#configuration)
- [Tests](#tests)
- [Project Structure](#project-structure)
- [Limitations](#limitations)
- [Acknowledgments](#acknowledgments)
- [License](#license)

---

## Why OPC-IR

Traditional investment analysis suffers from three structural problems:

| Problem | How OPC-IR Solves It |
|---------|---------------------|
| **Anchoring bias** — once a senior analyst states a view, the team gravitates toward it | Each role votes independently. No role ever sees another's output before aggregation |
| **No accuracy tracking** — most research desks don't measure whether their calls were right | Brier scores computed for every role on every resolved prediction. Weights auto-adjust |
| **Vague predictions** — "the market could go up or down" is unfalsifiable | Every forecast requires a specific invalidator: numeric threshold + temporal bound + triggering event. `invalidator-lint` rejects anything less |

The result: a system that gets measurably better over time, where each prediction is a testable hypothesis rather than an opinion.

---

## Built on OPC

OPC-IR is built on **[OPC v0.10.0](https://github.com/iamtouchskyer/opc)** by [@iamtouchskyer](https://github.com/iamtouchskyer). OPC's core architecture — independent multi-role evaluation with code-enforced quality gates — is the foundation:

| OPC Concept | OPC-IR Application |
|---|---|
| **Independent multi-role voting** | 14 roles (7 watchers + 5 schools + 2 advocates) vote without seeing each other's output |
| **Digraph pipeline with gates** | Events → triage → watchers → synthesize → forecast → verdict → calibrate |
| **Code-enforced quality gates** | `invalidator-lint` / `falsifier-lint` reject vague predictions mechanically |
| **Build != Review** | The watcher that observes a dimension never judges its own forecast accuracy |
| **Autonomous loop** | OPC's `/opc loop` was used to implement all 5 phases of OPC-IR itself |

OPC-IR was literally built by OPC — every phase went through OPC's build-verify flow with independent code review agents.

---

## Quick Start

### Install

**From Marketplace (recommended):**

```bash
# Add the marketplace
claude plugin marketplace add MichaelFei87/MichaelFei-claude-plugins-marketplace

# Install
claude plugin install opc-ir@MichaelFei-claude-plugins-marketplace
```

**From GitHub:**

```bash
claude --plugin-url https://github.com/MichaelFei87/opc-ir/archive/main.zip
```

### Prerequisites

```bash
# System tools
brew install jq yq python3

# Python dependencies (no API keys needed)
pip3 install yfinance pandas lxml
```

### First Run

```bash
/opc-ir-init                    # Create ~/.opc-ir/ runtime directory

/opc-ir-evolve                  # Fetch RSS + market data → triage → 7 watchers → world-model

/opc-ir-status                  # Verify everything is healthy
```

### Daily Workflow

```bash
/opc-ir-evolve                  # Update world-model with latest events

/opc-ir-forecast                # 5 strategists vote on macro outlook

/opc-ir-verdict NVDA            # 5 schools + 2 advocates vote on single asset

/opc-ir-digest                  # Render human-readable daily summary
```

### Calibration (after predictions mature)

```bash
/opc-ir-calibrate               # Link predictions to actual prices, compute Brier scores
```

---

## Architecture

### System Overview

```
                    ┌─────────────────────────────────────────────┐
                    │            Event Ingestion                   │
                    │  10 RSS feeds → 3-layer dedup → monthly JSONL│
                    └──────────────────┬──────────────────────────┘
                                       │
                    ┌──────────────────┴──────────────────────────┐
                    │            Market Data Layer                 │
                    │  22 macro instruments + 5 equities + earnings│
                    │  All via yfinance — zero API keys            │
                    └──────────────────┬──────────────────────────┘
                                       │
                    ┌──────────────────┴──────────────────────────┐
                    │      Triage Classifier (LLM Agent)          │
                    │  Score events across 7 dimensions            │
                    │  4 hard rules (central bank, war, earnings,  │
                    │  circuit breakers) → auto-trigger verdicts   │
                    └──────────────────┬──────────────────────────┘
                                       │
          ┌────────┬────────┬─────┬────┴───┬──────┬──────┐
          ▼        ▼        ▼     ▼        ▼      ▼      ▼
       politics  econ   military tech   human  energy  corp
       watcher   fin    watcher  ai    watcher watcher fund
                 watcher         watcher               watcher
          │        │        │     │        │      │      │
          └────────┴────────┴─────┴────┬───┴──────┴──────┘
                                       │
                    ┌──────────────────┴──────────────────────────┐
                    │    Stream 1: World-Model                     │
                    │    evolve-synthesize → world-model.jsonl      │
                    │    + trigger markers for auto-verdicts        │
                    └──────┬───────────────────┬──────────────────┘
                           │                   │
              ┌────────────▼───────┐  ┌────────▼──────────────┐
              │ Stream 2: Forecast │  │ Stream 3: Verdict      │
              │ 5 strategists      │  │ 5 schools + 2 advocates│
              │ × 26 assets        │  │ on single ticker       │
              │ × 4 horizons       │  │                        │
              │ → forecast.jsonl   │  │ → verdicts.jsonl       │
              │ → forecast.md      │  │ → digest.md            │
              └────────┬───────────┘  └────────┬──────────────┘
                       └────────┬──────────────┘
                                │
                    ┌───────────▼─────────────────────────────────┐
                    │         Calibration Loop                     │
                    │  ground-truth-linker → predictions-vs-truth  │
                    │  calibrate-posteriors → Brier scores          │
                    │  → role-weights.yaml (posteriors)             │
                    │  Weights feed back into next aggregation      │
                    └─────────────────────────────────────────────┘
```

### Three Output Streams

| Stream | Produced By | Output Files | Content |
|--------|------------|--------------|---------|
| **World-Model** | 7 watchers + evolve-synthesize | `world-model.jsonl`, `world-model.md` | Structured macro view across 7 dimensions |
| **Forecast** | 5 strategists | `forecast.jsonl`, `forecast.md` | Probability distributions for 26 assets at 4 horizons |
| **Verdict** | 5 schools + 2 advocates | `verdicts.jsonl`, `digest.md` | Directional stance + conviction on a single asset |

### 7 Macro Dimensions

| Dimension | Watcher | Example Signals |
|-----------|---------|----------------|
| **politics** | `politics-watcher` | Elections, sanctions, trade policy, regulation |
| **econ-finance** | `econ-finance-watcher` | Central bank decisions, CPI, employment, yields |
| **military** | `military-watcher` | Armed conflicts, defense spending, arms deals |
| **tech-ai** | `tech-ai-watcher` | AI breakthroughs, chip supply, tech regulation |
| **humanities** | `humanities-watcher` | Demographics, labor shifts, cultural movements |
| **energy-commodity** | `energy-commodity-watcher` | Oil supply, metals, energy transition |
| **corp-fundamentals** | `corp-fundamentals-watcher` | Earnings, M&A, IPOs, management changes |

Dimension weights control triage routing sensitivity (configurable in `defaults/dimension-weights.yaml`):

```yaml
politics: 1.5        # highest — geopolitics moves markets
econ-finance: 1.5    # highest — central bank + macro
tech-ai: 1.3
corp-fundamentals: 1.2
military: 1.0
energy-commodity: 1.0
humanities: 0.8      # lowest — slow-moving trends
```

---

## Commands

| Command | Description |
|---------|-------------|
| `/opc-ir-init` | Initialize `~/.opc-ir/` runtime directory with all subdirectories and default configs |
| `/opc-ir-evolve` | Full evolve chain: fetch RSS + market data → triage → dispatch 7 watchers → synthesize world-model → trigger markers |
| `/opc-ir-forecast` | 5 strategists vote independently on macro outlook across 26 assets at 4 horizons (1d, 1w, 1m, 3m) |
| `/opc-ir-verdict <ticker>` | Single-asset verdict: 5 schools + 2 advocates vote, with falsifier-lint gate and split detection |
| `/opc-ir-calibrate` | Link matured predictions to actual prices via Yahoo Finance, compute per-role Brier scores, update posteriors |
| `/opc-ir-digest` | Render `digest.md` from latest verdicts with disclaimer banner |
| `/opc-ir-status` | 7-section dashboard: plugin info, integrity, scheduler, stream freshness, data sources, tokens, quick stats |

---

## Pipeline Deep Dive

### Evolve Chain (`/opc-ir-evolve`)

```
events-migrate check → fetch-rss.sh (10 feeds, 3-layer dedup)
                     → fetch-market-data.sh (22 macro + 5 equity via yfinance)
                     → fetch-earnings.sh (quarterly EPS for equity-single assets)
                     → triage-classifier (LLM Agent: score 7 dims, 4 hard rules)
                     → 7 watcher Agents dispatched in parallel
                     → evolve-synthesize.sh → world-model.jsonl + world-model.md
                     → trigger-manage.sh (hard-rule markers for auto-verdicts)
```

### Forecast Chain (`/opc-ir-forecast`)

```
5 strategist Agents vote independently (no anchoring)
→ invalidator-lint gate (numeric threshold + temporal bound + event required)
→ forecast-assemble.sh (weighted consensus + L1 dissent per strategist)
→ forecast-render.sh → forecast.md
```

### Verdict Chain (`/opc-ir-verdict`)

```
5 school Agents + 2 advocate Agents vote independently
→ falsifier-lint gate (same 3-component check)
→ verdict-aggregate.sh (weighted consensus, split detection at spread < 0.15)
→ thesis-update.sh → theses/{ticker}.md
→ verdict-render-digest.sh → digest.md
```

### Calibration Chain (`/opc-ir-calibrate`)

```
events-migrate check
→ ground-truth-linker.sh (link predictions to actual prices via fetch-prices.sh)
→ calibrate-posteriors.sh (Brier scores, N≥30 cold-start floor)
→ role-weights.yaml posteriors updated (clamped to [0.5, 1.5] × prior)
→ calibration-report.json (regime detection: 50%+ degradation flagged)
```

### Quality Gates

Every prediction must pass lint before being accepted:

```bash
# Both linters enforce 3 components:
# 1. Numeric threshold (e.g., "drops below $4200")
# 2. Temporal bound (e.g., "within 2 weeks")
# 3. Triggering event (e.g., "if CPI exceeds 4.5%")

bin/invalidator-lint.sh "SPX drops below 4200 within 2 weeks if CPI exceeds 4.5%"
# → exit 0 (pass)

bin/invalidator-lint.sh "markets could decline"
# → exit 1 (fail — no threshold, no bound, no trigger)
```

---

## Watch Assets

26 instruments across 9 categories:

| Category | Symbols | Source |
|----------|---------|--------|
| **US Indices** | NDX, SPX, RUT | yfinance (^NDX, ^GSPC, ^RUT) |
| **Single Stocks** | MSFT, NVDA, GOOGL, META, TSM | yfinance (direct) |
| **Volatility** | VIX | yfinance (^VIX) |
| **China Indices** | HSI, HSCEI, CSI300 | yfinance (^HSI, ^HSCE, 000300.SS) |
| **Currencies** | DXY, CNH, CYB, USDCNY | yfinance (DX-Y.NYB, CNH=X, CYB, CNY=X) |
| **Commodities** | GLD, WTI | yfinance (GC=F, CL=F) |
| **Fixed Income** | ZB | yfinance (ZB=F) |
| **Yield Curve** | US3M, US2Y, US5Y, US10Y, US30Y, 2s10s spread | yfinance (^IRX, ^FVX, etc.) |
| **Crypto** | BTC | yfinance (BTC-USD) |
| **Options Sentiment** | SPX P/C, NDX P/C | yfinance (SPY, QQQ options chains) |

---

## Roles

### Watchers (7) — World-Model Evolution

Each dimension has a dedicated watcher that runs independently during `/opc-ir-evolve`. Watchers consume events from triage + relevant market data, and produce dimension deltas.

### Schools (5) — Verdict Voting

| Role | Expertise |
|------|-----------|
| `fundamental-analyst` | DCF, earnings quality, balance sheet, intrinsic value |
| `technical-analyst` | Price action, volume, momentum, chart patterns |
| `macro-economist` | Central bank policy, yield curve, fiscal dynamics |
| `quant-modeler` | Factor models, stat-arb, volatility surfaces |
| `behavioral-analyst` | Sentiment, positioning, fund flows, contrarian signals |

### Strategists (5) — Forecast Voting

| Role | Expertise |
|------|-----------|
| `macro-strategist` | Top-down global growth, policy regime analysis |
| `cross-asset-allocator` | Inter-market correlations, risk-parity, rotation |
| `regime-detector` | Statistical regime change, volatility regimes, HMM |
| `historical-analogist` | Historical parallels, rhyming cycles, secular trends |
| `contrarian-strategist` | Sentiment extremes, crowded trades, mean-reversion |

### Advocates (2) — Forced Bull/Bear Positions

| Role | Weight | Purpose |
|------|--------|---------|
| `bull-advocate` | 0.5× | Forced constructive case — upside catalysts, underappreciated positives |
| `bear-advocate` | 0.5× | Forced destructive case — downside risks, overlooked vulnerabilities |

All roles must produce a **falsifier/invalidator** with: numeric threshold + temporal bound + triggering event.

Weights start at prior (1.0 for schools/strategists, 0.5 for advocates) and are updated after N >= 30 calibration samples, clamped to [0.5, 1.5] × prior.

---

## Data Sources

### RSS Feeds (10 sources, configured in `defaults/sources.yaml`)

| Source | Coverage |
|--------|----------|
| Reuters (World + Business) | Global news, markets |
| Associated Press | Breaking news |
| BBC World | International events |
| CNBC | US markets, earnings |
| Financial Times | Global macro, policy |
| Bloomberg | Markets, finance |
| South China Morning Post | China/Asia geopolitics |
| Federal Reserve | US monetary policy |
| European Central Bank | EU monetary policy |

### Market Data (via yfinance — zero API keys)

| Script | Output | Content |
|--------|--------|---------|
| `fetch-market-data.sh` | `macro-snapshot.json` | 22 instruments: yields in bp, 60-day trends, 2s10s spread |
| | `watcher-snapshot.json` | 5 equities: price, 52-week range, 1m/3m trends |
| `fetch-earnings.sh` | `earnings/{SYM}-{Q}.json` | Quarterly EPS (actual vs estimate), revenue, YoY, beat/miss |
| `fetch-prices.sh` | (stdout JSON) | Single-asset single-date price lookup for calibration |

### Premium Sources (optional)

Bloomberg, Refinitiv, NewsAPI, and TradingView are supported via `~/.opc-ir/config/secrets.env`. See `docs/PREMIUM-SOURCES.md`.

---

## Configuration

### Defaults (in `defaults/`)

| File | Purpose |
|------|---------|
| `sources.yaml` | RSS feed definitions (URLs, regions, timeouts) |
| `watch-assets.yaml` | 26 instruments with yfinance ticker mappings |
| `role-weights.yaml` | Cold-start priors; posteriors added by calibration |
| `dimension-weights.yaml` | Triage dimension weights (politics=1.5, humanities=0.8) |
| `triage-thresholds.yaml` | Routing threshold (0.6), hard rules, batch size |
| `horizons.yaml` | Forecast horizons: 1d, 1w, 1m, 3m |

### Runtime Directory (`~/.opc-ir/`)

```
~/.opc-ir/
├── config/           # local.yaml overrides, secrets.env
├── events/           # YYYY-MM-events.jsonl (monthly rolling)
├── world/            # world-model.jsonl, world-model.md
├── market-data/      # macro-snapshot.json, watcher-snapshot.json, earnings/
├── forecast/         # forecast.jsonl, forecast.md
├── verdict/          # verdicts.jsonl, digest.md, theses/
├── calibration/      # predictions-vs-truth.jsonl, calibration-report.json
├── triggers/         # {TICKER}.marker (6-hour cooldown)
├── scheduler/        # active-backend, jobs/
└── logs/             # daily logs, tokens/
```

---

## Tests

```bash
bats tests/*.bats    # 160 tests across 20 test files
```

Coverage includes:

- **Plugin structure** — plugin.json, commands, roles, defaults, bin/ scripts all present
- **Role validation** — all 14 roles have valid YAML frontmatter
- **RSS pipeline** — fetch, 3-layer dedup (ID/URL/title), monthly rolling, event injection
- **Triage schema** — dimension scores, routing thresholds, hard rules
- **Evolve chain** — watcher dispatch, world-model output, market data section
- **Forecast schema** — 5-tier probability distributions, invalidator presence
- **Verdict schema** — directional stance, falsifier presence, split detection
- **Market data** — live yfinance validation: macro/watcher JSON schemas, yield bp format, 2s10s spread math, earnings schema, options P/C ratios
- **Calibration** — fetch-prices (live API), ground-truth linking, Brier scores, posterior clamping
- **Quality gates** — invalidator-lint and falsifier-lint pass/fail cases
- **Infrastructure** — scheduler, token tracker, integrity checks, status dashboard
- **Risk mitigations** — weight explosion guards (M3), vague invalidator rejection (M4), disclaimer banner (P1), regime detection (P2)
- **End-to-end** — full forecast + verdict flows with sample data

All tests use **live API data** — no fixtures or mocks.

---

## Project Structure

```
opc-ir/
├── plugin.json                 # Plugin manifest (v0.0.1)
├── LICENSE                     # MIT
│
├── agents/                     # LLM agent definitions
│   └── triage-classifier.md    # 7-dimension event scorer with hard rules
│
├── bin/                        # 22 executable bash scripts (the entire pipeline)
│   ├── fetch-rss.sh            # RSS ingestion (10 sources, 3-layer dedup)
│   ├── fetch-market-data.sh    # 22 macro + 5 equity via yfinance batch
│   ├── fetch-earnings.sh       # Quarterly EPS via yfinance
│   ├── fetch-prices.sh         # Single-asset price lookup (for calibration)
│   ├── evolve-synthesize.sh    # Merge watcher deltas → world-model
│   ├── vote-aggregate.sh       # Weighted vote aggregation (shared)
│   ├── verdict-aggregate.sh    # 5 schools + 2 advocates → consensus
│   ├── forecast-assemble.sh    # 5 strategists → consensus + L1 dissent
│   ├── forecast-render.sh      # forecast.jsonl → forecast.md
│   ├── verdict-render-digest.sh# verdicts.jsonl → digest.md
│   ├── invalidator-lint.sh     # 3-component specificity gate (forecasts)
│   ├── falsifier-lint.sh       # 3-component specificity gate (verdicts)
│   ├── ground-truth-linker.sh  # Link predictions to actual prices
│   ├── calibrate-posteriors.sh # Brier scores → role-weights.yaml
│   ├── trigger-manage.sh       # CRUD for hard-rule trigger markers
│   ├── thesis-update.sh        # Append thesis to theses/{ticker}.md
│   ├── inject-event.sh         # Manual event injection
│   ├── events-migrate.sh       # Monolithic → monthly JSONL migration
│   ├── events-grep.sh          # Cross-month event search
│   ├── scheduler-loop.sh       # /loop backend (register/unregister/status)
│   ├── scheduler-dispatch.sh   # Route to active scheduling backend
│   ├── token-tracker.sh        # Per-run token usage + 7-day projections
│   ├── integrity.sh            # SHA256 plugin file integrity check
│   └── opc-ir-status.sh        # 7-section health dashboard
│
├── commands/                   # 7 slash commands for Claude Code
├── roles/                      # 14 role definitions
│   ├── _watchers/              # 7 dimension watchers
│   ├── _schools/               # 5 analytical school roles
│   ├── _forecast/              # 5 strategist roles
│   └── _advocates/             # 2 bull/bear advocate roles
│
├── defaults/                   # 6 YAML config files (cold-start defaults)
├── pipeline/                   # 7 protocol docs (step-by-step procedures)
├── skills/opc-ir/              # Skill manifest with script execution policy
├── tests/                      # 20 bats test files, 160 tests
│   ├── schemas/                # 3 JSON Schema files (forecast, verdict, triage)
│   └── lib/                    # Test helpers (frontmatter validation)
│
└── docs/
    ├── ARCHITECTURE.md         # System overview, risk mitigations
    ├── INHERITS-FROM-OPC.md    # Forked vs native files tracking
    ├── PREMIUM-SOURCES.md      # Bloomberg, Refinitiv, NewsAPI guide
    ├── specs/                  # 2 design specs
    ├── plans/                  # 5 implementation plans (phases 1–5)
    └── summaries/              # 5 phase completion summaries
```

---

## Limitations

- Forecasts and verdicts are research analysis, **not investment advice**
- Calibration requires **N >= 30** resolved predictions per role before weights adjust
- Public RSS feeds introduce 5–15 minute latency vs. real-time data
- The system cannot predict black swan events outside its training distribution
- Ground truth alignment is inherently delayed (outcomes take time to resolve)
- Options sentiment data depends on Yahoo Finance availability (may be sparse for some tickers)

---

## Acknowledgments

OPC-IR would not exist without the **[OPC project](https://github.com/iamtouchskyer/opc)** by [@iamtouchskyer](https://github.com/iamtouchskyer). The core insight — independent multi-role evaluation with code-enforced quality gates — is OPC's contribution. OPC-IR applies it to a new domain.

---

## License

[MIT](LICENSE) — (c) 2026 OPC-IR Contributors
