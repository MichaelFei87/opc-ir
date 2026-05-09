---
name: opc-ir
description: OPC-IR Investment Research — multi-role independent voting for macro forecasts, single-asset verdicts, and world-model evolution
---

# OPC-IR Skill

This plugin applies the OPC multi-role independent voting methodology to investment research. It produces three outputs:

1. **World-Model** — continuously-updated macro snapshot across 7 weighted dimensions
2. **Macro Forecast** — 5-tier probability distribution across watch-assets at 4 horizons
3. **Verdict** — single-asset judgment using 5 analytical schools + 2 advocates

## Commands

- `/opc-ir-init` — Initialize runtime directory at `~/.opc-ir/`
- `/opc-ir-evolve` — Fetch events, triage, update world-model (run via `/loop 1h`)
- `/opc-ir-forecast` — Generate macro forecast using 5 strategist roles
- `/opc-ir-verdict <ticker>` — Generate single-asset verdict
- `/opc-ir-calibrate` — Align predictions with ground truth, update role weights
- `/opc-ir-digest` — Regenerate verdict digest
- `/opc-ir-status` — System health dashboard

## Methodology

Based on OPC (One Person Company) methodology, forked at commit `6f83dde`:
- Multi-role independent evaluation (no echo chamber)
- Harness-based file state (all data in `~/.opc-ir/`)
- Falsifier-first: every thesis must carry a specific invalidator
- Calibration-informed weights (after N≥30 samples per role)

## Quick Start

```
/opc-ir-init
/opc-ir-forecast           # macro forecast with sample world-model
/opc-ir-verdict NDX        # single-asset verdict
/opc-ir-status             # check health
```

## Critical: Script Execution Policy

> **🚫 NO INLINE REIMPLEMENTATION — MANDATORY FOR ALL COMMANDS**
>
> Plugin `bin/` scripts are auto-added to `PATH` by Claude Code. Call them as bare commands.
> Config files (`defaults/*.yaml`) live in `$CLAUDE_PLUGIN_ROOT/defaults/`.
>
> **Rules:**
> 1. **ALL external data MUST come from `bin/` scripts.** Events from `fetch-rss.sh`, market data from `fetch-market-data.sh`, earnings from `fetch-earnings.sh`, prices from `fetch-prices.sh`.
> 2. **Do NOT use WebSearch, WebFetch, curl, wget, or any other tool** to fetch external data.
> 3. **Do NOT fabricate or guess data.** If a script fails, FAIL the command.
> 4. **Never** rewrite, inline, or approximate a script's logic.
> 5. If a script exits non-zero, **FAIL** — do not suppress or substitute.
