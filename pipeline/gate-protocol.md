---
forked-from: opc/pipeline/gate-protocol.md
forked-at: 2026-05-08
modifications:
  - "Added invalidator-lint and falsifier-lint as gate checks"
  - "Added retry counter (max 2) for lint failures"
---

# Gate Protocol

Mechanical verdict aggregation and routing for OPC-IR pipelines.

> **🚫 HARD RULE — NO INLINE REIMPLEMENTATION**: `bin/invalidator-lint.sh` and `bin/falsifier-lint.sh` MUST be executed as bare commands (on PATH). Do NOT reimplement regex checks or lint logic inline. If the script is missing, **fail the gate**.

## Preflight — Required Binaries

Before executing any gate, verify ALL required scripts exist on PATH. Run `which invalidator-lint.sh falsifier-lint.sh`. If ANY script is missing, **FAIL immediately** with: `❌ Missing required bin: <name>`. Do NOT proceed.

## Gate Types

### Invalidator-Lint Gate (Forecast)

After forecast synthesis, check each invalidator for specificity:
1. Run `invalidator-lint.sh` on each invalidator text
2. If any fail → ITERATE (retry max 2, then FAIL)
3. If all pass → PASS

### Falsifier-Lint Gate (Verdict)

After verdict synthesis, check each falsifier:
1. Run `falsifier-lint.sh` on each falsifier text
2. If any fail → ITERATE with retry counter
3. Retry counter >= 2 → FAIL (verdict rejected)
4. If all pass → PASS

## Verdict Computation

Read all evaluation files for the upstream node:

| Condition | Verdict |
|---|---|
| Any 🔴 finding | FAIL |
| Any 🟡 finding | ITERATE |
| All 🔵 or LGTM | PASS |
| Any BLOCKED | BLOCKED |

## Routing

| Verdict | Action |
|---|---|
| PASS | Advance to next node |
| ITERATE | Loop back to upstream (with prior findings as context) |
| FAIL | Loop back to upstream (max 3 loops per edge) |
| BLOCKED | Stop, surface to user |
