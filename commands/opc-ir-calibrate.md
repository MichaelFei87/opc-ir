---
name: opc-ir-calibrate
description: "Daily calibration: align predictions to ground truth, update posterior role-weights"
allowed-tools: Bash, Read, Write, Agent
---

# /opc-ir-calibrate

## Preflight

Before doing anything, verify that `$CLAUDE_PLUGIN_ROOT/pipeline/calibration-protocol.md` exists. If it does not, **FAIL immediately** with: `❌ Pipeline file not found: pipeline/calibration-protocol.md`. Do NOT proceed, do NOT improvise.

## Procedure

See `pipeline/calibration-protocol.md` for the full procedure.
