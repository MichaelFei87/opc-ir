# OPC-IR Architecture

## System Overview

```
Events → Triage → Watchers → World-Model
                                 ↓
                            Forecast (5 strategists)
                                 ↓
                            Verdict (5 schools + 2 advocates)
                                 ↓
                            Calibration (Brier score → posterior weights)
```

## Output Streams

| Stream | Frequency | Roles | Output |
|--------|-----------|-------|--------|
| World-Model | On event | 7 watchers | `world-model.md` snapshot |
| Forecast | Daily/Weekly | 5 strategists | `forecast.jsonl` + `forecast.md` |
| Verdict | On demand | 5 schools + 2 advocates | `verdicts.jsonl` + `digest.md` |

## Role Categories

| Category | Count | Weight | Output Format |
|----------|-------|--------|---------------|
| Schools | 5 | 1.0 | Stance + thesis + falsifier |
| Advocates | 2 | 0.5 | Stance + thesis + falsifier |
| Strategists | 5 | 1.0 | 5-tier probability distribution |
| Watchers | 7 | 1.0 | World-model delta |

## Risk Mitigation Cross-Reference

| Risk ID | Description | Severity | Mitigated In | File |
|---------|-------------|----------|--------------|------|
| M3 | Posterior weight explosion | High | Phase 1 | `bin/vote-aggregate.sh` — clamp to [0.5, 1.5] |
| M4 | Vague invalidators | High | Phase 1 | `bin/invalidator-lint.sh` — 3-component specificity check |
| P1 | Misuse as investment advice | High | Phase 1 | `bin/verdict-render-digest.sh` — disclaimer banner |
| P2 | Unknown regime performance | Medium | Phase 1 | `tests/schemas/forecast.schema.json` — `regime_marker` field |
| D2 | Public-RSS data density gap | High | Phase 1 | `README.md` — Limitations section |

## Key Design Decisions

1. **Independence** — no role sees another's output during evaluation
2. **Falsifier-first** — predictions without specific invalidators are rejected
3. **Cold-start safety** — posterior weights locked at 1.0 until N≥30 calibration samples
4. **Posterior cap** — even after calibration, weights clamped to [0.5, 1.5] × prior
5. **Split detection** — verdicts with weighted spread < 0.15 marked as "split" with warning
