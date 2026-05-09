---
name: opc-ir-evolve
description: "Evolve world-model: fetch → triage → watchers → synthesize → triggers"
allowed-tools: Bash, Read, Write, Agent
---

# /opc-ir-evolve

## Preflight

Before doing anything, verify that `$CLAUDE_PLUGIN_ROOT/pipeline/evolve-protocol.md` exists. If it does not, **FAIL immediately** with: `❌ Pipeline file not found: pipeline/evolve-protocol.md`. Do NOT proceed, do NOT improvise.

## Procedure

See `pipeline/evolve-protocol.md` for the full procedure.

## Style Rules

- **No abbreviations in user-facing output** (Report, Summary, Key Developments). Use full names: 欧洲央行 (not ECB), 美联储 (not Fed), 中国人民银行 (not PBOC), 日本央行 (not BOJ), 政府支持企业 (not GSE). Abbreviations are fine in internal data files (triage JSON, world-model.jsonl).
- **Triage table must include Published date and Source columns.** Format: `| 2026-05-08 15:25 | ft-markets | "Markets banking on Bliss trade" | ... |`
