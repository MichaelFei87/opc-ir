---
title: Verdict Protocol
created: 2026-05-08
type: native
---

# Verdict Protocol

Single-asset verdict synthesis for OPC-IR.

## Overview

The verdict flow produces a directional recommendation for a single asset by dispatching 5 school analysts + 2 advocates independently, then aggregating via weighted vote.

## Preflight — Required Binaries

Before executing any step, verify ALL required scripts exist on PATH. Run `which verdict-aggregate.sh verdict-render-digest.sh thesis-update.sh falsifier-lint.sh`. If ANY script is missing, **FAIL immediately** with: `❌ Missing required bin: <name>`. Do NOT proceed, do NOT improvise, do NOT substitute.

## Procedure


> **🚫 HARD RULE — ALL DATA MUST COME FROM bin/ SCRIPTS AND defaults/ FILES**
> You MUST NOT fetch data by any means other than bin/ scripts (on PATH) or reading `$CLAUDE_PLUGIN_ROOT/defaults/` files. Do NOT use WebSearch, WebFetch, curl, feedparser, or write inline scripts to obtain data. Do NOT fabricate or guess data. If a script is missing or fails, **FAIL**.

> **🚫 HARD RULE — NO INLINE REIMPLEMENTATION**: Every `bin/*.sh` script below MUST be executed as bare commands (they are on PATH). Do NOT rewrite or approximate any script's logic.

> **🚫 HARD RULE — SEQUENTIAL GATE**: Each step is a gate. If a step's script exits non-zero, **STOP immediately and report the failure**. Do NOT proceed.

### Step 1 — Context Assembly

For the target asset, gather:
- Current world-model snapshot — includes a `## Market Data` section with the latest quantitative market snapshot (yields, prices, trends). Schools and advocates should cite precise numbers from this section.
- Latest forecast for this asset (all horizons)
- Previous verdict (if any) for continuity
- Role weights from `calibration/role-weights.yaml`
- Asset metadata from `$CLAUDE_PLUGIN_ROOT/defaults/watch-assets.yaml`

### Step 2 — Independent School Dispatch (Parallel)

Dispatch each of the following 7 roles in parallel:

**Schools (5):**
1. `roles/_schools/fundamental-analyst.md`
2. `roles/_schools/technical-analyst.md`
3. `roles/_schools/macro-economist.md`
4. `roles/_schools/quant-modeler.md`
5. `roles/_schools/behavioral-analyst.md`

**Advocates (2):**
6. `roles/_advocates/bull-advocate.md`
7. `roles/_advocates/bear-advocate.md`

Each receives: role file (read and include in the agent prompt), context, target asset.
Each produces: direction (long/short/neutral) + thesis + falsifier.

> **⚠️ STRUCTURED OUTPUT REQUIREMENT**: Each school/advocate agent MUST write a **JSON** file (NOT YAML):
> `$VERDICT_RUN/school-outputs/{role-name}.json`
>
> The file is a single JSON object:
> ```json
> {
>   "role": "fundamental-analyst",
>   "asset": "NDX",
>   "direction": "long",
>   "confidence": 0.75,
>   "thesis": "Strong AI capex cycle supports NDX earnings growth...",
>   "falsifier": "NDX drops below 27000 within 30 days on NASDAQ correction",
>   "key_risks": ["Tariff escalation", "Energy cost pass-through"],
>   "timeframe": "1m",
>   "weight": 1.0
> }
> ```
>
> - Schools set `"weight": 1.0`; advocates set `"weight": 0.5`
> - **⚠️ CRITICAL**: The downstream `verdict-aggregate.sh` reads JSON via `json.load()`.
>   If the agent writes YAML instead of JSON, the pipeline WILL FAIL.
>   Include this instruction verbatim in every agent prompt:
>   "You MUST write your output as a JSON object using the Write tool. Do NOT use YAML format.
>    The file extension MUST be .json and the content MUST be valid JSON."

### Step 2b — Assemble Votes JSON

After all 7 agents complete, the orchestrator assembles their outputs into a single `votes.json` array:

1. Read each `$VERDICT_RUN/school-outputs/{role-name}.json`
2. Combine into a JSON array: `[{role1_output}, {role2_output}, ...]`
3. Write to `$VERDICT_RUN/votes.json`

This file is the input to `verdict-aggregate.sh`.

### Step 3 — Vote Aggregation

Run `verdict-aggregate.sh $VERDICT_RUN/votes.json $VERDICT_RUN/verdict.json`:
- Weight by role-weights (advocates at 0.5× prior via the `weight` field in each vote)
- Produce consensus distribution
- Extract dominant stance

### Step 4 — Falsifier Lint

For each role's falsifier:
- Run `falsifier-lint.sh` on each falsifier text
- If any fail → ITERATE with retry counter
- Retry counter >= 2 → FAIL (verdict rejected)
- If all pass → proceed

### Step 5 — Render Digest

Run `verdict-render-digest.sh` to produce human-readable verdict.

### Step 6 — Update Thesis

Run `thesis-update.sh <opc-ir-home> <ticker> <verdict.json>` to persist the new stance and archive the previous one. This maintains a per-ticker thesis file with history in `verdict/theses/`.

## Output Format

Each school/advocate must produce a **JSON** file (see Step 2 for the exact schema and write instructions).

Required fields:
- `role`: role name (e.g. `"fundamental-analyst"`)
- `asset`: target ticker symbol
- `direction`: `"long"` | `"short"` | `"neutral"`
- `confidence`: float 0.0–1.0
- `thesis`: 2–3 sentence directional thesis
- `falsifier`: specific condition (must pass `falsifier-lint.sh`)
- `key_risks`: array of risk strings
- `timeframe`: primary horizon (`"1d"`, `"1w"`, `"1m"`, `"3m"`)
- `weight`: `1.0` for schools, `0.5` for advocates

## Verdict Digest

The final digest includes:
- **Disclaimer banner**: "This is research analysis, not investment advice" — mandatory on every digest
- Consensus stance with confidence
- Bull case summary (from bull-advocate + supportive schools)
- Bear case summary (from bear-advocate + cautious schools)
- Key falsifiers (aggregated)
- Dissenting views (minority positions)
