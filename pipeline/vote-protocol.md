---
title: Vote Protocol
created: 2026-05-08
type: native
---

# Vote Protocol

Weighted vote aggregation for OPC-IR multi-role outputs.

> **🚫 HARD RULE — NO INLINE REIMPLEMENTATION**: Vote aggregation MUST be performed by calling `vote-aggregate.sh` (forecast) or `verdict-aggregate.sh` (verdict). Do NOT reimplement the weighted averaging logic inline.

## Preflight — Required Binaries

Before executing any aggregation, verify ALL required scripts exist on PATH. Run `which vote-aggregate.sh verdict-aggregate.sh`. If ANY script is missing, **FAIL immediately** with: `❌ Missing required bin: <name>`. Do NOT proceed.

## Overview

Combines independent role outputs into a single consensus distribution using weighted averaging. Used in both forecast and verdict flows.

## Algorithm

### Input

- `votes.json` — array of role outputs, each with a 5-tier distribution
- `role-weights.yaml` — prior (and optionally posterior) weights per role

### Weight Resolution

For each role:
1. Look up `posterior_weight` in role-weights.yaml
2. If absent (cold-start), use `prior_weight`
3. If posterior exists, apply Bayesian cap: clamp to [0.5, 1.5] × prior

### Aggregation

For each asset × horizon:
1. Collect all role distributions
2. Multiply each distribution bucket by the role's resolved weight
3. Sum weighted distributions
4. Normalize so buckets sum to 1.0

### Output

```json
{
  "asset": "<symbol>",
  "horizon": "<horizon>",
  "distribution": {
    "strongly_bearish": 0.05,
    "bearish": 0.15,
    "neutral": 0.40,
    "bullish": 0.30,
    "strongly_bullish": 0.10
  },
  "contributing_roles": ["role-a", "role-b"],
  "aggregation_method": "weighted_average"
}
```

## Edge Cases

- If a role's distribution doesn't sum to 1.0 (tolerance ±0.01), normalize it before aggregation
- If a role is missing a distribution for an asset/horizon pair, exclude it from aggregation for that pair
- If no roles provide a distribution for a pair, emit a "no_data" sentinel
