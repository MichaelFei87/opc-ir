---
name: opc-ir-verdict
description: "Generate single-asset verdict using 5 schools + 2 advocates"
allowed-tools: Bash, Read, Write, Agent
---

# /opc-ir-verdict

## Preflight

Before doing anything, verify that `$CLAUDE_PLUGIN_ROOT/pipeline/verdict-protocol.md` exists. If it does not, **FAIL immediately** with: `❌ Pipeline file not found: pipeline/verdict-protocol.md`. Do NOT proceed, do NOT improvise.

## Procedure

See `pipeline/verdict-protocol.md` for the full procedure.

## Arguments

- `<ticker>` — required, e.g. NDX, SPX, BTC

## Style Rules

- **No abbreviations in user-facing output** (verdict thesis, scenario analysis, catalyst tables). Use full names: 欧洲央行 (not ECB), 美联储 (not Fed), 中国人民银行 (not PBOC), 日本央行 (not BOJ), 政府支持企业 (not GSE). Abbreviations are fine in internal data fields.
