#!/usr/bin/env bash
set -euo pipefail

# forecast-render.sh — Render forecast.jsonl to human-readable forecast.md with ASCII bars
# Usage: forecast-render.sh <opc-ir-home>

OPC_IR_HOME="${1:?Usage: forecast-render.sh <opc-ir-home>}"
FORECAST_JSONL="$OPC_IR_HOME/forecast/forecast.jsonl"
FORECAST_MD="$OPC_IR_HOME/forecast/forecast.md"

if [[ ! -f "$FORECAST_JSONL" ]]; then
  echo "Error: $FORECAST_JSONL not found" >&2
  exit 1
fi

# Read last line and render entirely in Python (avoids 480+ subprocess spawns)
export FORECAST_JSONL FORECAST_MD
python3 << 'PYEOF'
import json, os

forecast_jsonl = os.environ["FORECAST_JSONL"]
forecast_md = os.environ["FORECAST_MD"]

# Read last non-empty line
with open(forecast_jsonl) as f:
    lines = [l.strip() for l in f if l.strip()]
if not lines:
    raise SystemExit("Error: forecast.jsonl is empty")

latest = json.loads(lines[-1])
timestamp = latest.get("timestamp", "unknown")
run_id = latest.get("run_id", "unknown")
wm_ref = latest.get("world_model_ref", "unknown")

tiers = ["strongly_bearish", "bearish", "neutral", "bullish", "strongly_bullish"]
BAR_WIDTH = 20

out = []
out.append(f"---")
out.append(f"generated_at: {timestamp}")
out.append(f"run_id: {run_id}")
out.append(f"world_model_ref: {wm_ref}")
out.append(f"---")
out.append(f"")
out.append(f"# Macro Forecast")
out.append(f"")
out.append(f"> Generated: {timestamp}")
out.append(f"> World-Model reference: {wm_ref}")
out.append(f"")

for asset in sorted(latest.get("forecasts", {}).keys()):
    out.append(f"## {asset}")
    out.append(f"")
    horizons = latest["forecasts"][asset]
    for horizon in sorted(horizons.keys()):
        out.append(f"### {horizon}")
        out.append("```")
        for tier in tiers:
            prob = horizons[horizon].get(tier, 0.0)
            bar_len = int(round(prob * BAR_WIDTH))
            bar = "▓" * bar_len + "░" * (BAR_WIDTH - bar_len)
            out.append(f"{tier:<18s} {bar} {prob*100:5.1f}%")
        out.append("```")
        out.append("")

    inv = latest.get("invalidators", {}).get(asset)
    if inv:
        out.append(f"**Invalidator:** {inv}")
        out.append("")

dissent = latest.get("strategist_dissent", [])
if dissent:
    out.append("---")
    out.append("")
    out.append("## Strategist Dissent")
    out.append("")
    for d in dissent:
        out.append(f"- **{d['strategist']}** on {d['asset']}/{d['horizon']}: L1 distance {d['l1_distance']}")
    out.append("")

with open(forecast_md, "w") as f:
    f.write("\n".join(out))

print(f"Forecast rendered to {forecast_md}")
PYEOF
