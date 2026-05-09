---
title: Invalidator Lint
created: 2026-05-08
type: native
---

# Invalidator Lint

Mechanical specificity check for forecast invalidators.

> **🚫 HARD RULE — NO INLINE REIMPLEMENTATION**: The lint check MUST be performed by calling `invalidator-lint.sh`. Do NOT reimplement the regex checks in Python, bash, or any other form. If the script is missing, **fail**.

## Purpose

Every forecast MUST carry a specific invalidator — a condition that, if met, invalidates the forecast. This lint enforces specificity by checking for three required components.

## Required Components

An invalidator MUST contain all three:

1. **Numeric threshold** — a specific number (price level, percentage, rate, count)
2. **Temporal bound** — a date, quarter, or time window
3. **Asset or event reference** — a specific asset symbol, index, or named event

## Examples

### PASS

- "If SPX drops below 4200 by Q3 2026, this forecast is invalidated"
  - Numeric: 4200 ✓ | Temporal: Q3 2026 ✓ | Asset: SPX ✓
- "Invalidated if Fed cuts rates by more than 50bps before December 2026"
  - Numeric: 50bps ✓ | Temporal: December 2026 ✓ | Event: Fed rate cut ✓

### FAIL

- "If market conditions significantly change"
  - Numeric: ✗ | Temporal: ✗ | Asset: vague ✗
- "If SPX drops by Q3 2026"
  - Numeric: ✗ (no threshold) | Temporal: Q3 2026 ✓ | Asset: SPX ✓

## Implementation

`invalidator-lint.sh` performs regex-based checks:
- Numeric: `/\d+(\.\d+)?(%|bps|bp|pts?|k|m|b)?/i`
- Temporal: `/(20\d{2}|Q[1-4]|January|February|...|December|\d+\s*(day|week|month|quarter|year)s?)/i`
- Asset: match against `$CLAUDE_PLUGIN_ROOT/defaults/watch-assets.yaml` symbols OR known event patterns

Exit 0 + "PASS" if all three present. Exit 1 + "FAIL" with missing component names otherwise.
