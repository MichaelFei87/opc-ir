# OPC-IR: Inheritance from OPC

This document tracks which files in OPC-IR are forked from the upstream OPC skill and which are native to OPC-IR.

## Forked Files (from OPC)

These files carry `forked-from` and `forked-at` frontmatter tracking their lineage:

| File | Forked From | Modifications |
|------|-------------|---------------|
| `pipeline/discussion-protocol.md` | `opc/pipeline/discussion-protocol.md` | Verbatim fork for plugin independence |
| `pipeline/role-evaluator-prompt.md` | `opc/pipeline/role-evaluator-prompt.md` | Added OPC-IR context injection (world-model, forecast, thesis), falsifier/invalidator output requirement |
| `pipeline/gate-protocol.md` | `opc/pipeline/gate-protocol.md` | Added invalidator-lint and falsifier-lint gate checks, retry counter |
| `pipeline/role-spec.md` | `opc/pipeline/role-spec.md` | Added OPC-IR role categories, output format requirements |

## Native Files (OPC-IR only)

These files are original to OPC-IR and do NOT have `forked-from` frontmatter:

- `pipeline/forecast-protocol.md` — Multi-strategist forecast generation
- `pipeline/vote-protocol.md` — Weighted vote aggregation
- `pipeline/verdict-protocol.md` — Single-asset verdict synthesis
- `pipeline/invalidator-lint.md` — Forecast invalidator specificity check
- `pipeline/triage-protocol.md` — Event classification and routing (stub)
- `pipeline/evolve-protocol.md` — World-model evolution (stub)
- `pipeline/calibration-protocol.md` — Brier score calibration (stub)

## Fork Policy

- Forked files may diverge from upstream OPC but should document modifications in frontmatter
- If upstream OPC changes significantly, review forked files for needed updates
- Native files are independently versioned and have no upstream dependency
