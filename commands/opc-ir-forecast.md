---
name: opc-ir-forecast
description: Generate macro forecast across 14 watch-assets using 5 strategist roles
allowed-tools: Bash, Read, Write, Agent
---

# /opc-ir-forecast

## Preflight

Before doing anything, verify that `$CLAUDE_PLUGIN_ROOT/pipeline/forecast-protocol.md` exists. If it does not, **FAIL immediately** with: `❌ Pipeline file not found: pipeline/forecast-protocol.md`. Do NOT proceed, do NOT improvise.

## Procedure

See `pipeline/forecast-protocol.md` for the full procedure.

## Style Rules

- **No abbreviations in user-facing output.** Use full names: 欧洲央行 (not ECB), 美联储 (not Fed), 中国人民银行 (not PBOC), 日本央行 (not BOJ), 政府支持企业 (not GSE). Abbreviations are fine in internal data fields.
