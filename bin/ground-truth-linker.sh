#!/usr/bin/env bash
set -euo pipefail

# ground-truth-linker.sh — Link matured predictions to price truth
# Usage: ground-truth-linker.sh [--home <path>]
# Reads forecast.jsonl + verdicts.jsonl, fetches prices, writes predictions-vs-truth.jsonl

OPC_IR_HOME="${OPC_IR_HOME:-$HOME/.opc-ir}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --home) OPC_IR_HOME="$2"; shift 2 ;;
    *) shift ;;
  esac
done

FORECAST_JSONL="$OPC_IR_HOME/forecast/forecast.jsonl"
VERDICTS_JSONL="$OPC_IR_HOME/verdict/verdicts.jsonl"
TRUTH_JSONL="$OPC_IR_HOME/calibration/predictions-vs-truth.jsonl"
LOG_FILE="$OPC_IR_HOME/logs/$(date +%Y-%m-%d).log"
FETCH_PRICES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fetch-prices.sh"

mkdir -p "$OPC_IR_HOME/calibration" "$(dirname "$LOG_FILE")"
touch "$TRUTH_JSONL"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ground-truth-linker: $*" >> "$LOG_FILE"; }

# Use python for the linking logic (complex data processing, avoids bash 4+ features)
export OPC_IR_HOME FORECAST_JSONL VERDICTS_JSONL TRUTH_JSONL FETCH_PRICES
python3 << 'PYEOF'
import json, os, subprocess, sys, time
from datetime import datetime, timedelta, timezone

truth_file = os.environ["TRUTH_JSONL"]
forecast_file = os.environ.get("FORECAST_JSONL", "")
verdicts_file = os.environ.get("VERDICTS_JSONL", "")
fetch_prices = os.environ["FETCH_PRICES"]

HORIZON_DAYS = {"1d": 1, "1w": 7, "1m": 30, "3m": 90}

def bucket_from_pct(pct):
    if pct <= -5: return "strong_down"
    if pct <= -1: return "down"
    if pct <= 1: return "neutral"
    if pct <= 5: return "up"
    return "strong_up"

BUCKET_INDEX = {"strong_down": 0, "down": 1, "neutral": 2, "up": 3, "strong_up": 4}

def onehot(bucket):
    v = [0,0,0,0,0]
    idx = BUCKET_INDEX.get(bucket)
    if idx is not None: v[idx] = 1
    return v

def parse_ts(ts_str):
    """Parse ISO timestamp to epoch, always UTC."""
    try:
        dt = datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
        return dt.timestamp()
    except Exception:
        return None

# Load already-linked keys
already_linked = set()
try:
    with open(truth_file) as f:
        for line in f:
            line = line.strip()
            if not line: continue
            obj = json.loads(line)
            key = f"{obj.get('run_id')}|{obj.get('asset')}|{obj.get('horizon')}|{obj.get('role','')}"
            already_linked.add(key)
except FileNotFoundError:
    pass

def fetch_price(asset, date_str):
    """Call fetch-prices.sh, return close price or None."""
    try:
        result = subprocess.run([fetch_prices, asset, date_str],
                                capture_output=True, text=True, timeout=30)
        if result.returncode == 0:
            data = json.loads(result.stdout.strip())
            return data.get("close")
    except Exception:
        pass
    return None

def link_prediction(run_id, asset, horizon, role, stream, dist, ts_epoch):
    """Link a single prediction to price truth. Returns True if linked."""
    days = HORIZON_DAYS.get(horizon)
    if days is None: return False

    maturity_epoch = ts_epoch + days * 86400
    if time.time() < maturity_epoch: return False  # not matured

    key = f"{run_id}|{asset}|{horizon}|{role}"
    if key in already_linked: return False

    pred_date = datetime.fromtimestamp(ts_epoch, tz=timezone.utc).strftime("%Y-%m-%d")
    target_date = datetime.fromtimestamp(maturity_epoch, tz=timezone.utc).strftime("%Y-%m-%d")

    p0 = fetch_price(asset, pred_date)
    p1 = fetch_price(asset, target_date)
    if p0 is None or p1 is None or p0 == 0: return False

    pct = (p1 - p0) / p0 * 100
    bucket = bucket_from_pct(pct)

    record = {
        "run_id": run_id, "asset": asset, "horizon": horizon,
        "role": role, "stream": stream,
        "predicted_dist": dist, "truth_bucket": bucket,
        "truth_onehot": onehot(bucket), "truth_source": "price",
        "pred_date": pred_date, "target_date": target_date,
        "linked_at": datetime.now(timezone.utc).isoformat()
    }
    pending_records.append(json.dumps(record))
    already_linked.add(key)
    return True

new_records = 0
pending_records = []

# Process forecast predictions (consensus-level)
if os.path.isfile(forecast_file):
    with open(forecast_file) as f:
        for line in f:
            line = line.strip()
            if not line: continue
            try:
                row = json.loads(line)
            except Exception: continue

            run_id = row.get("run_id", "")
            ts = row.get("ts", row.get("timestamp", ""))
            forecasts = row.get("forecasts", {})
            ts_epoch = parse_ts(ts)
            if ts_epoch is None: continue

            for asset, horizons in forecasts.items():
                if not isinstance(horizons, dict): continue
                for horizon, dist in horizons.items():
                    if link_prediction(run_id, asset, horizon, "_consensus", "forecast", dist, ts_epoch):
                        new_records += 1

# Process verdict predictions (per-role)
if os.path.isfile(verdicts_file):
    with open(verdicts_file) as f:
        for line in f:
            line = line.strip()
            if not line: continue
            try:
                row = json.loads(line)
            except Exception: continue

            run_id = row.get("run_id", "")
            ts = row.get("ts", row.get("timestamp", ""))
            asset = row.get("asset", row.get("ticker", ""))
            ts_epoch = parse_ts(ts)
            if ts_epoch is None or not asset: continue

            # Process per-role votes if present
            votes = row.get("votes", [])
            if isinstance(votes, list):
                for vote in votes:
                    if not isinstance(vote, dict): continue
                    role = vote.get("role", "")
                    if not role: continue
                    dist = vote.get("distribution", vote.get("dist", None))
                    if dist is None: continue
                    horizon = vote.get("horizon", "1m")
                    if link_prediction(run_id, asset, horizon, role, "verdict", dist, ts_epoch):
                        new_records += 1

            # Also link consensus from verdict if present
            consensus = row.get("consensus", {})
            if isinstance(consensus, dict):
                dist = consensus.get("distribution", consensus.get("dist", None))
                horizon = consensus.get("horizon", "1m")
                if dist is not None:
                    if link_prediction(run_id, asset, horizon, "_consensus", "verdict", dist, ts_epoch):
                        new_records += 1

# Batch write all pending records
if pending_records:
    with open(truth_file, "a") as out:
        for rec in pending_records:
            out.write(rec + "\n")

print(f"{new_records}")
PYEOF

log "ground-truth-linker complete"
