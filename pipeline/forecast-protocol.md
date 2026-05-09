---
title: Forecast Protocol
created: 2026-05-08
type: native
---

# Forecast Protocol

Multi-strategist macro forecast generation for OPC-IR.

## Overview

The forecast flow dispatches 5 strategist roles independently to produce probability distributions across watch-assets and 4 time horizons.

## Preflight — Required Binaries

Before executing any step, verify ALL required scripts exist on PATH. Run `which vote-aggregate.sh forecast-render.sh forecast-assemble.sh invalidator-lint.sh`. If ANY script is missing, **FAIL immediately** with: `❌ Missing required bin: <name>`. Do NOT proceed, do NOT improvise, do NOT substitute.

## Procedure


> **🚫 HARD RULE — ALL DATA MUST COME FROM bin/ SCRIPTS AND defaults/ FILES**
> You MUST NOT fetch data by any means other than bin/ scripts (on PATH) or reading `$CLAUDE_PLUGIN_ROOT/defaults/` files. Do NOT use WebSearch, WebFetch, curl, feedparser, or write inline scripts to obtain data. Do NOT fabricate or guess data. If a script is missing or fails, **FAIL**.

> **🚫 HARD RULE — NO INLINE REIMPLEMENTATION**: Every `bin/*.sh` script below MUST be executed as bare commands (they are on PATH). Do NOT rewrite or approximate any script's logic.

> **🚫 HARD RULE — SEQUENTIAL GATE**: Each step is a gate. If a step's script exits non-zero, **STOP immediately and report the failure**. Do NOT proceed.

### Step 1 — Context Assembly

Gather inputs and **write a shared context file** so strategist agents don't duplicate large prompts.

1. Collect:
   - Current world-model snapshot (latest `world-model.md`) — includes a `## Market Data` section with the latest quantitative market snapshot (yields, prices, trends). Strategists should cite precise numbers from this section.
   - Previous forecast tail (last 3 forecasts if available)
   - Role weights from `calibration/role-weights.yaml` (or defaults)
   - Watch-asset list from `$CLAUDE_PLUGIN_ROOT/defaults/watch-assets.yaml`
   - Horizons from `$CLAUDE_PLUGIN_ROOT/defaults/horizons.yaml`

2. **MANDATORY**: Build `$FORECAST_RUN/shared-context.md` by **mechanically concatenating** the source files — do NOT summarize, paraphrase, or abridge any content.

   Use a bash command to assemble the file:
   ```bash
   # Step 2a: Copy world-model VERBATIM (do NOT summarize)
   cp "$OPC_IR_HOME/world/world-model.md" "$FORECAST_RUN/shared-context.md"
   ```

   Then APPEND the remaining sections using the Write/Edit tool:
   - Previous forecast tail (last 3 forecasts from `forecast.jsonl` if available — key distribution numbers, not full JSON)
   - Watch-asset symbol list (just symbols, one per line) from `$CLAUDE_PLUGIN_ROOT/defaults/watch-assets.yaml`
   - Horizon IDs: `1d, 1w, 1m, 3m`
   - The invalidator format rules (copied verbatim from the "INVALIDATOR FORMAT RULES" section below)

   > **🚫 DO NOT SUMMARIZE THE WORLD-MODEL.** The world-model.md must appear in shared-context.md **in full, unmodified**. Strategists need the complete analytical detail — not just bullet-point summaries of "Key Macro State." Every subsection (e.g., Indo-Pacific Security, Financial Stability, AI Regulation, Agriculture) contains signals that may affect specific assets. Summarizing loses these signals.

3. Create the output directories:
   ```
   mkdir -p $FORECAST_RUN/strategist-outputs
   mkdir -p $FORECAST_RUN/aggregated
   ```

> **⚠️ WHY**: Each strategist agent is dispatched independently. Without a shared context file, the orchestrator must embed all context in every agent prompt (5× duplication). By writing to `$FORECAST_RUN/shared-context.md`, each agent prompt only needs to say `Read $FORECAST_RUN/shared-context.md` — saving ~60% of prompt tokens across the 5 agents.
>
> **⚠️ VERIFY**: After writing `shared-context.md`, verify its size: `wc -l $FORECAST_RUN/shared-context.md`. It MUST be at least 200 lines (the world-model alone is 300+ lines). If it's under 200 lines, the world-model was likely summarized — **FAIL and redo Step 2**.

### Step 2 — Independent Dispatch (Parallel)

Dispatch each of the following 5 strategists in parallel:

1. `roles/_forecast/macro-strategist.md`
2. `roles/_forecast/cross-asset-allocator.md`
3. `roles/_forecast/regime-detector.md`
4. `roles/_forecast/historical-analogist.md`
5. `roles/_forecast/contrarian-strategist.md`

Each receives:
- Their role file (read and include in the agent prompt)
- Instruction to `Read $FORECAST_RUN/shared-context.md` for all shared context
- Output format: 5-tier probability distribution per asset per horizon
- The exact output path: `$FORECAST_RUN/strategist-outputs/{role-name}.json`

Each strategist writes a forecast independently. No strategist sees another's output.

> **⚠️ STRUCTURED OUTPUT REQUIREMENT**: Each strategist agent MUST write a **JSON** file (NOT YAML):
> `$FORECAST_RUN/strategist-outputs/{role-name}.json`
>
> **The directory is `strategist-outputs/`, NOT `strategists/`.**
>
> The file is a JSON array of objects, one per (asset, horizon):
> ```json
> [
>   {"asset": "NDX", "horizon": "1d", "distribution": {"strongly_bearish": 0.05, "bearish": 0.15, "neutral": 0.50, "bullish": 0.25, "strongly_bullish": 0.05}, "invalidator": "NDX drops below 28000 within 7 days", "confidence_note": "..."},
>   ...
> ]
> ```
>
> **⚠️ CRITICAL**: The downstream `vote-aggregate.sh` reads these files with `json.load()`. If the agent writes YAML instead of JSON, the pipeline WILL FAIL. Include this instruction verbatim in every agent prompt:
> "You MUST write your output as a JSON array using the Write tool. Do NOT use YAML format. The file extension MUST be .json and the content MUST be valid JSON."
>
> The orchestrator MUST include `$FORECAST_RUN` path in the agent prompt so the agent can write this file.
> The agent MUST use the Write tool to create this file. Distribution values MUST sum to 1.0 (±0.01).

> **⚠️ INVALIDATOR FORMAT RULES — include these verbatim in every strategist prompt:**
>
> Every `invalidator` field MUST pass `invalidator-lint.sh`, which checks three regex rules:
>
> 1. **Numeric reference** (REQUIRED): Must contain at least one number — a price level, percentage, or count.
>    - ✅ "SPX drops below 7000", "VIX exceeds 25", "NFP prints above 200K"
>    - ❌ "markets crash", "growth slows significantly"
>
> 2. **Temporal reference** (REQUIRED): Must match one of these patterns:
>    - A year: `2026`, `2027`
>    - A quarter: `Q1`, `Q2`, `Q3`, `Q4`
>    - A month name: `Jan`, `Feb`, `Mar`, `Apr`, `May`, `Jun`, `Jul`, `Aug`, `Sep`, `Oct`, `Nov`, `Dec`
>    - A timeframe: `within N days/weeks/months`, `by end of`, `by mid-`, `before`, `after`, `next N days/weeks/months`, `N days/weeks/months`
>    - ❌ "5 consecutive sessions", "soon", "near-term" — these do NOT match
>
> 3. **Asset/event reference** (REQUIRED): Must contain a recognized keyword (case-insensitive):
>    - Index tickers: `NDX`, `SPX`, `RUT`, `VIX`, `HSI`, `HSCEI`, `CSI300`, `DXY`, `CNH`, `USDCNY`, `GLD`, `ZB`, `WTI`, `BTC`, `NASDAQ`, `S&P`
>    - Institutions: `Fed`, `ECB`, `PBOC`, `BOJ`
>    - Macro indicators: `CPI`, `GDP`, `NFP`, `PMI`, `ISM`, `FOMC`
>    - Events/terms: `earnings`, `rate cut`, `rate hike`, `tariff`, `sanctions`, `oil`, `gold`, `dollar`, `yuan`, `bitcoin`, `treasury`
>    - ⚠️ Individual stock tickers (MSFT, NVDA, GOOGL, META, TSM) are NOT in this list. For single-stock invalidators, append a recognized parent reference like `NASDAQ` or `earnings`.
>    - ❌ "MSFT drops below 400" alone will FAIL. ✅ "MSFT drops below 400 on NASDAQ weakness within 30 days"
>
> **Example valid invalidators:**
> - "SPX drops below 7000 within 30 days"
> - "Fed signals rate cut before Sep 2026"
> - "WTI falls below $75 by Q3 2026 on ceasefire"
> - "NVDA misses earnings estimates in Q2 2026; NASDAQ breaks 28000"

### Step 3 — Invalidator Lint (Pre-Aggregation)

For each strategist's output, check invalidator specificity **before** aggregation:
- For each `$FORECAST_RUN/strategist-outputs/*.json` file, extract every `invalidator` field
- Run `invalidator-lint.sh <invalidator-text>` on each
- If any fail → re-prompt that strategist (retry max 2), then FAIL
- If all pass → proceed

> **⚠️ WHY BEFORE AGGREGATION**: Catching bad invalidators early avoids wasting the aggregation step. If a strategist's invalidators fail lint, only that strategist needs to be re-run.

### Step 4 — Vote Aggregation

Run batch aggregation across all asset/horizon pairs:
```
vote-aggregate.sh $FORECAST_RUN/strategist-outputs $CLAUDE_PLUGIN_ROOT/defaults/role-weights.yaml $FORECAST_RUN/aggregated
```

`vote-aggregate.sh` in batch mode (3 arguments) automatically discovers all (asset, horizon) pairs from the strategist JSON files, applies role weights, and writes one JSON file per pair to the output directory. No manual looping required.

This produces ~96 aggregated JSON files (24 assets × 4 horizons, minus any pairs with zero votes).

### Step 5 — Assemble & Render

1. Run `forecast-assemble.sh $FORECAST_RUN ~/.opc-ir` to produce `forecast.jsonl`
2. Run `forecast-render.sh ~/.opc-ir` to produce human-readable `forecast.md`

## Output Format

Each strategist must write a JSON file to `$FORECAST_RUN/strategist-outputs/{role-name}.json` containing an array of forecast entries:

```json
[
  {
    "asset": "<symbol>",
    "horizon": "<1d|1w|1m|3m>",
    "distribution": {
      "strongly_bearish": 0.05,
      "bearish": 0.15,
      "neutral": 0.50,
      "bullish": 0.25,
      "strongly_bullish": 0.05
    },
    "invalidator": "<specific condition with numeric + temporal + asset/event>",
    "confidence_note": "<brief reasoning>"
  }
]
```

Distribution values MUST sum to 1.0 (tolerance: ±0.01).
