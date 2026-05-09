#!/usr/bin/env bash
set -euo pipefail

# forecast-assemble.sh — Assemble aggregated vote results + invalidators into forecast.jsonl
#
# Usage: forecast-assemble.sh <forecast-run-dir> <opc-ir-home>
#
# Reads:
#   <forecast-run-dir>/aggregated/*.json        — vote-aggregate.sh output
#   <forecast-run-dir>/strategist-outputs/*.json — strategist raw outputs (for invalidators)
#
# Appends one JSON line to: <opc-ir-home>/forecast/forecast.jsonl

FORECAST_RUN="${1:?Usage: forecast-assemble.sh <forecast-run-dir> <opc-ir-home>}"
OPC_IR_HOME="${2:?Usage: forecast-assemble.sh <forecast-run-dir> <opc-ir-home>}"

AGGREGATED_DIR="$FORECAST_RUN/aggregated"
STRAT_DIR="$FORECAST_RUN/strategist-outputs"
FORECAST_JSONL="$OPC_IR_HOME/forecast/forecast.jsonl"

if [[ ! -d "$AGGREGATED_DIR" ]]; then
  echo "Error: aggregated directory not found: $AGGREGATED_DIR" >&2
  exit 1
fi

if [[ ! -d "$STRAT_DIR" ]]; then
  echo "Error: strategist-outputs directory not found: $STRAT_DIR" >&2
  exit 1
fi

RUN_ID=$(basename "$FORECAST_RUN")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Find world-model ref
WM_FILE="$OPC_IR_HOME/world/world-model.md"
if [[ -f "$WM_FILE" ]]; then
  WM_REF=$(head -20 "$WM_FILE" | grep -E '^(updated|modified|date):' | head -1 | sed 's/^[^:]*: *//' || true)
  [[ -z "$WM_REF" ]] && WM_REF=$(stat -f "%Sm" -t "%Y-%m-%dT%H:%M:%SZ" "$WM_FILE" 2>/dev/null || date -r "$WM_FILE" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown")
else
  WM_REF="unknown"
fi

export AGGREGATED_DIR STRAT_DIR RUN_ID TIMESTAMP WM_REF FORECAST_JSONL

python3 << 'PYEOF'
import json, os, glob

aggregated_dir = os.environ["AGGREGATED_DIR"]
strat_dir = os.environ["STRAT_DIR"]
run_id = os.environ["RUN_ID"]
timestamp = os.environ["TIMESTAMP"]
wm_ref = os.environ["WM_REF"]
forecast_jsonl = os.environ["FORECAST_JSONL"]

# Build forecasts: {asset: {horizon: distribution}}
forecasts = {}
for fpath in sorted(glob.glob(os.path.join(aggregated_dir, "*.json"))):
    with open(fpath) as f:
        data = json.load(f)
    asset = data.get("asset", os.path.basename(fpath).rsplit("_", 1)[0])
    horizon = data.get("horizon", os.path.basename(fpath).rsplit("_", 1)[1].replace(".json", ""))
    dist = data.get("aggregated", data.get("distribution", {}))
    forecasts.setdefault(asset, {})[horizon] = dist

# Build invalidators: per asset, pick the longest-horizon invalidator
horizon_rank = {"3m": 4, "1m": 3, "1w": 2, "1d": 1}
invalidators = {}
for fpath in sorted(glob.glob(os.path.join(strat_dir, "*.json"))):
    with open(fpath) as f:
        entries = json.load(f)
    for e in entries:
        asset = e["asset"]
        inv = e.get("invalidator", "")
        if not inv:
            continue
        rank = horizon_rank.get(e.get("horizon", "1d"), 0)
        if asset not in invalidators or rank > invalidators[asset][1]:
            invalidators[asset] = (inv, rank)

invalidators_out = {a: v[0] for a, v in invalidators.items()}

# Build dissent from aggregated files
dissent = []
for fpath in sorted(glob.glob(os.path.join(aggregated_dir, "*.json"))):
    with open(fpath) as f:
        data = json.load(f)
    for d in data.get("dissent", []):
        dissent.append({
            "strategist": d["role"],
            "asset": data.get("asset", ""),
            "horizon": data.get("horizon", ""),
            "l1_distance": d.get("l1_distance", 0)
        })

row = {
    "timestamp": timestamp,
    "run_id": run_id,
    "world_model_ref": wm_ref,
    "forecasts": forecasts,
    "invalidators": invalidators_out,
    "strategist_dissent": dissent
}

os.makedirs(os.path.dirname(forecast_jsonl), exist_ok=True)
with open(forecast_jsonl, "a") as f:
    f.write(json.dumps(row, ensure_ascii=False) + "\n")

print(f"Forecast assembled → {forecast_jsonl} (run: {run_id})")
PYEOF
