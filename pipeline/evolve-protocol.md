---
title: Evolve Protocol
created: 2026-05-08
type: native
status: active
---

# Evolve Protocol

World-model evolution procedure for OPC-IR.

## Overview

The evolve flow updates the world-model snapshot by integrating new events and market data through dimension watchers.

## Preflight — Required Binaries

Before executing any step, verify ALL required scripts exist on PATH. Run `which fetch-rss.sh fetch-market-data.sh fetch-earnings.sh`. If ANY script is missing, **FAIL immediately** with: `❌ Missing required bin: <name>`. Do NOT proceed, do NOT improvise, do NOT substitute.

## Procedure


> **🚫 HARD RULE — ALL DATA MUST COME FROM bin/ SCRIPTS**
> You MUST NOT fetch data by any means other than executing bin/ scripts (on PATH). Specifically:
> - **NO WebSearch / WebFetch** — do NOT use web search tools to find news, prices, or any external data
> - **NO direct RSS/API calls** — do NOT use `curl`, `wget`, `feedparser`, or any HTTP client to fetch RSS feeds, APIs, or web pages
> - **NO inline scripts** — do NOT write Python/bash/node scripts to fetch or process data
> - **NO fabricated data** — do NOT invent, guess, or hallucinate market prices, events, or earnings
> - The ONLY way to get events is `bin/fetch-rss.sh`. The ONLY way to get market data is `bin/fetch-market-data.sh`. The ONLY way to get earnings is `bin/fetch-earnings.sh`.
> - If a script is missing or fails, **FAIL** — do NOT substitute with any alternative data source.

> **🚫 HARD RULE — NO INLINE REIMPLEMENTATION**: Every `bin/*.sh` script below MUST be executed as the actual file as bare commands (they are on PATH). Do NOT rewrite or approximate any script's logic.

> **🚫 HARD RULE — SEQUENTIAL GATE**: Each step is a gate. If a step's script exits non-zero, **STOP immediately and report the failure**. Do NOT proceed. Do NOT skip. Do NOT continue with partial data.

> **🚫 HARD RULE — NO AD-HOC INSPECTION COMMANDS**: Do NOT run temporary shell commands (e.g. python one-liners, jq, etc.) to preview or summarize market data, events, or other pipeline data between steps. Watchers read JSON files directly — manual previews are unnecessary and error-prone.

1. **Fetch events** — `fetch-rss.sh --home "$OPC_IR_HOME"`
   - If 0 new events: log and **exit successfully** (short-circuit — no LLM cost). Do NOT proceed.
   - If script fails: **FAIL**.
   - **The stdout integer IS the new-event count.** Save it as `$NEW_COUNT`. Do NOT reinterpret it as "fetch cycles" or any other meaning.
   - **To get the new events**: `tail -n $NEW_COUNT "$OPC_IR_HOME/events/events.jsonl"`. That's it. The script appends new events to the end of events.jsonl in order, so the last `$NEW_COUNT` lines are exactly the new events.
   - **Do NOT compute diffs** against triage history, do NOT scan the full events.jsonl, do NOT write ad-hoc python to find "untriaged" events. The diff is already done by the script's dedup logic.
2. **Fetch market data** — `fetch-market-data.sh --home "$OPC_IR_HOME"`
   - If script fails: **FAIL**. Do NOT proceed without market data.
3. **Fetch earnings** — `fetch-earnings.sh --home "$OPC_IR_HOME"`
   - If script fails: **FAIL**. Do NOT proceed without earnings data.
4. **Triage events** — dispatch `triage-classifier` agent, route per `$CLAUDE_PLUGIN_ROOT/defaults/triage-thresholds.yaml`
   - **Input**: the `$NEW_COUNT` events from step 1 (obtained via `tail -n $NEW_COUNT`). Pass these directly to the triage agent. Do NOT re-derive the event list.
   - **Triage file format**: each triage JSON file contains a flat list of objects, each with `"id"` (not `"event_id"`), `"scores"`, `"routed_to"`, etc.
   - If `--dry-run`: display triage results and **exit here**.
5. **Build context briefs** — for each activated watcher, assemble:
   - Routed events from triage
   - Market data context (see §Market Data Context below)
   - **Read JSON files directly** (via the Read tool) and pass their content to watcher prompts. Do NOT run ad-hoc shell commands (python, jq, etc.) to parse or summarize market data. The "NO AD-HOC INSPECTION COMMANDS" rule applies here — watchers interpret the raw JSON themselves.
6. **Dispatch dimension watchers** — for each watcher activated by triage, dispatch the corresponding role:
   1. `roles/_watchers/politics-watcher.md`
   2. `roles/_watchers/econ-finance-watcher.md`
   3. `roles/_watchers/military-watcher.md`
   4. `roles/_watchers/tech-ai-watcher.md`
   5. `roles/_watchers/humanities-watcher.md`
   6. `roles/_watchers/energy-commodity-watcher.md`
   7. `roles/_watchers/corp-fundamentals-watcher.md`
   
   Only dispatch watchers that triage routed events to. Each watcher proposes world-model deltas.
7. **Synthesize deltas** — two sub-steps:

   **7a. Market data + audit log** (script) — `evolve-synthesize.sh <watcher-outputs-dir> <world-model.jsonl> --market-dir "$OPC_IR_HOME/market-data"`
   - Renders market data JSON → `$RUNDIR/market-data-section.md` (Markdown tables)
   - Appends delta metadata to `world-model.jsonl` (audit log)
   - Does NOT modify `world-model.md`
   - If script fails: **FAIL**.

   **7b. Narrative synthesis** (LLM orchestrator) — merge watcher deltas into world model:
   1. **Backup** — copy current `world-model.md` to `$RUNDIR/world-model-backup.md`
   2. **Read** the current `world-model.md` (full)
   3. **Read** each watcher output from `$RUNDIR/watchers/*.md`
   4. **Read** `$RUNDIR/market-data-section.md` (from 7a)
   5. **Merge** using these rules:
      - For each dimension WITH watcher output: integrate the delta into the existing section (update/add bullets, adjust salience, update triggers). Preserve existing bullets that the delta does not contradict.
      - For each dimension WITHOUT watcher output: **keep the existing section unchanged**.
      - Update `## Cross Dimension Threads` table based on new cross-dimension signals from watchers.
      - Update `## Risk Register` — adjust probabilities/trends for affected risks, add new risks if warranted.
      - Replace `## Market Data` section with 7a output.
      - Update frontmatter (`snapshot_date`, `run_id`, `dimensions_updated`).
      - Update cycle summary (final italic paragraph).
   6. **Safety guards:**
      - If ALL watcher outputs are empty or missing → only update Market Data section, keep everything else unchanged.
      - If `market-data-section.md` does not exist → keep old Market Data section.
      - NEVER discard existing dimension content. If in doubt, keep the old content and append new signals.
   7. **Write** the updated `world-model.md` via Edit (prefer incremental edits over full rewrite when possible).
8. **Write trigger markers** — for each dimension updated, create a trigger for the relevant ticker(s):
   - First run `trigger-manage.sh list` to see existing trigger tickers.
   - Then run `trigger-manage.sh create <TICKER>` for each affected ticker (e.g. `trigger-manage.sh create ECB`, `trigger-manage.sh create GEOPOLITICS`).
   - The script signature is `trigger-manage.sh {create|check|consume|list} [ticker]`. It does NOT accept `--home` or any other flags.
9. **Report** — summary of events processed, dimensions updated, watchers dispatched, triggers written.

## Market Data Context

When dispatching watchers, inject relevant market data from the JSON files in `$OPC_IR_HOME/market-data/`:

### econ-finance-watcher receives:
- `macro-snapshot.json` — full snapshot (all macro instruments, yield curve, VIX, DXY, commodities)
- Key focus: yield curve shape (2s10s spread), rate trends, DXY movement, VIX level

### corp-fundamentals-watcher receives:
- `watcher-snapshot.json` — all equity-single asset prices and trends
- `earnings/{SYMBOL}-{YYYY}Q{N}.json` — latest quarterly earnings for each watcher asset
- The watcher should generate an LLM summary for any earnings file where `summary` is `null`, and write it back

### energy-commodity-watcher receives:
- `macro-snapshot.json` instruments: WTI, GLD
- Relevant for commodity price trend context

### Other watchers:
- Receive no market data by default. The orchestrator may selectively inject macro-snapshot excerpts if triage determines market context is relevant to the dimension.

## Watcher Roles

7 dimension watchers (one per macro dimension), defined in `roles/_watchers/`:
1. `politics-watcher.md`
2. `econ-finance-watcher.md`
3. `military-watcher.md`
4. `tech-ai-watcher.md`
5. `humanities-watcher.md`
6. `energy-commodity-watcher.md`
7. `corp-fundamentals-watcher.md`

## Error Handling

**Every script failure is fatal.** If any `bin/*.sh` script exits non-zero, the pipeline MUST stop immediately with a clear error message. Do NOT:
- Continue with partial data
- Skip a failed step and proceed to the next
- Substitute inline logic for a failed script
- Use WebSearch, WebFetch, curl, or any other tool to fetch data as a workaround
- Write your own Python/bash script to replace the failed script
