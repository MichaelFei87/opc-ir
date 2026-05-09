---
title: Calibration Protocol
created: 2026-05-08
type: native
status: active
---

# Calibration Protocol

Brier score calibration and role-weight posterior update for OPC-IR.


> **🚫 HARD RULE — ALL DATA MUST COME FROM bin/ SCRIPTS**
> You MUST NOT fetch data by any means other than bin/ scripts (on PATH). Do NOT use WebSearch, WebFetch, curl, or write inline scripts to obtain prices, events, or any external data. Do NOT fabricate or guess data. If a script is missing or fails, **FAIL**.

> **🚫 HARD RULE — NO INLINE REIMPLEMENTATION**: Calibration MUST be performed by calling `calibrate-posteriors.sh`, ground-truth linking by `ground-truth-linker.sh`, and price fetching by `fetch-prices.sh`. Do NOT reimplement Brier score calculation or weight update logic inline.

> **🚫 HARD RULE — SEQUENTIAL GATE**: Each step is a gate. If a step's script exits non-zero, **STOP immediately and report the failure**. Do NOT proceed to the next step.

## Preflight — Required Binaries

Before executing any step, verify ALL required scripts exist on PATH. Run `which fetch-prices.sh ground-truth-linker.sh calibrate-posteriors.sh events-grep.sh events-migrate.sh`. If ANY script is missing, **FAIL immediately** with: `❌ Missing required bin: <name>`. Do NOT proceed, do NOT improvise, do NOT substitute.

## Overview

Calibration aligns ground truth outcomes with prior predictions, computes Brier scores per role, and updates posterior role-weights. Safe to run anytime; idempotent on already-linked records.

## Procedure

### Step 0: Migration check

If `$OPC_IR_HOME/events/events.jsonl` exists and is NOT a symlink, run monthly migration:

```bash
events-migrate.sh --home "$OPC_IR_HOME"
```

### Step 1: Price Truth + Ground Truth Linking

```bash
NEW_RECORDS=$(ground-truth-linker.sh --home "$OPC_IR_HOME")
```

Report: "Linked N new prediction→truth records"

If `$NEW_RECORDS` is 0 and no existing truth records exist, print status and exit:
> "No matured predictions to calibrate against. Predictions mature after their horizon (1d/1w/1m/3m) elapses."

### Step 2: Event Truth (Verdict Falsifier Evaluation)

For each matured verdict in `$OPC_IR_HOME/verdict/verdicts.jsonl` that:
- Has matured (ts + horizon < now)
- Has at least one falsifier
- Is not yet event-judged (no `truth_source: "event"` record for this key)

Do:
1. Gather events via `events-grep.sh --after $PRED_DATE --before $TARGET_DATE --home "$OPC_IR_HOME"`
2. If events found, use the Agent tool to judge whether the falsifier was triggered, passing:
   - The verdict's thesis and falsifier
   - The gathered events
   - The price outcome (if already linked in Step 1)
   - Instruction: return `{"falsifier_triggered": true/false, "confidence": 0.0-1.0, "reasoning": "..."}`
3. If `falsifier_triggered: true` with `confidence >= 0.7`:
   - Update the truth record: set `truth_source: "event"` and flip the truth bucket to opposite of predicted direction

### Step 3: Posterior Weight Calculation

```bash
calibrate-posteriors.sh --home "$OPC_IR_HOME"
```

This computes:
- Per-role Brier scores
- N>=30 cold-start gating
- Posterior = clamp(prior_brier / role_brier, 0.5, 1.5)
- Regime detection (30d rolling Brier deterioration > 1.5x)
- Anomaly rejection (all-same, NaN/Inf, all-boundary)

### Step 4: Status Report

Read `$OPC_IR_HOME/calibration/calibration-report.json` and render:

```
## Calibration Report

**Records linked this run:** {new_records}
**Total truth records:** {total_records}
**Consensus Brier:** {consensus_brier}

### Per-Role Results
| Role | N | Brier | Posterior | Status |
|------|---|-------|-----------|--------|
| macro-strategist | 45 | 0.89 | 1.12 | calibrated |
| fundamental-analyst | 18 | null | 1.00 | cold_start (n=18 < 30) |

### Warnings
- ⚠️ Regime warning: {role} recent Brier 50%+ worse than historical
- ℹ️ {role} approaching N=30 threshold (currently N={n})
```

## Brier Score

```
Brier = (1/N) × Σ (forecast_probability - outcome)²
```

Where outcome ∈ {0, 1} for each tier bucket.

## Configuration

- Cold-start floor: N >= 30
- Posterior cap: [0.5, 1.5] × prior
- Recalibration trigger: after each ground-truth resolution
