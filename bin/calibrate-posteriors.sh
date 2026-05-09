#!/usr/bin/env bash
set -euo pipefail

# calibrate-posteriors.sh — Compute Brier scores and update role weights
# Usage: calibrate-posteriors.sh [--home <path>]
# Reads: predictions-vs-truth.jsonl, role-weights.yaml
# Writes: role-weights.yaml (with posterior_weight), calibration-report.json

OPC_IR_HOME="${OPC_IR_HOME:-$HOME/.opc-ir}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --home) OPC_IR_HOME="$2"; shift 2 ;;
    *) shift ;;
  esac
done

TRUTH_JSONL="$OPC_IR_HOME/calibration/predictions-vs-truth.jsonl"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEIGHTS_FILE="$SCRIPT_DIR/defaults/role-weights.yaml"
REPORT_FILE="$OPC_IR_HOME/calibration/calibration-report.json"
LOG_FILE="$OPC_IR_HOME/logs/$(date +%Y-%m-%d).log"

mkdir -p "$OPC_IR_HOME/calibration" "$(dirname "$LOG_FILE")"
log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] calibrate: $*" >> "$LOG_FILE"; }

if [[ ! -f "$TRUTH_JSONL" ]]; then
  log "No predictions-vs-truth.jsonl found"
  echo '{"status":"no_data","message":"No truth records to calibrate against"}'
  exit 0
fi

# Use python for Brier score computation and posterior calculation
export TRUTH_JSONL WEIGHTS_FILE REPORT_FILE
python3 << 'PYEOF'
import json, os, sys, math
from datetime import datetime, timezone

truth_file = os.environ["TRUTH_JSONL"]
weights_file = os.environ["WEIGHTS_FILE"]
report_file = os.environ["REPORT_FILE"]

# Load truth records
records = []
with open(truth_file) as f:
    for line in f:
        line = line.strip()
        if not line: continue
        try:
            records.append(json.loads(line))
        except Exception: pass

if not records:
    report = {"status": "no_data", "message": "No truth records"}
    with open(report_file, "w") as f:
        json.dump(report, f, indent=2)
    print(json.dumps(report))
    sys.exit(0)

# Group by role
from collections import defaultdict
role_records = defaultdict(list)
for r in records:
    role = r.get("role", "_unknown")
    role_records[role].append(r)

# Compute Brier score per role
# Brier = (1/N) * sum( sum( (predicted_i - actual_i)^2 ) for each bucket )
def brier_score(predicted_dist, truth_onehot):
    """Compute Brier score for a single prediction."""
    if not predicted_dist or not truth_onehot:
        return None
    # Normalize predicted_dist keys to ordered list
    buckets = ["strongly_bearish", "bearish", "neutral", "bullish", "strongly_bullish"]
    alt_buckets = ["strong_down", "down", "neutral", "up", "strong_up"]

    pred = []
    if isinstance(predicted_dist, dict):
        for b in buckets:
            pred.append(predicted_dist.get(b, 0))
        if sum(pred) == 0:
            for b in alt_buckets:
                pred.append(predicted_dist.get(b, 0))
            pred = pred[5:]  # take alt_buckets values
    elif isinstance(predicted_dist, list):
        pred = predicted_dist[:5]
    else:
        return None

    if len(pred) != 5 or len(truth_onehot) != 5:
        return None

    total = sum(pred)
    if total > 0:
        pred = [p / total for p in pred]  # normalize

    return sum((p - t) ** 2 for p, t in zip(pred, truth_onehot))

role_briers = {}
role_counts = {}
for role, recs in role_records.items():
    scores = []
    for r in recs:
        bs = brier_score(r.get("predicted_dist"), r.get("truth_onehot"))
        if bs is not None:
            scores.append(bs)
    if scores:
        role_briers[role] = sum(scores) / len(scores)
        role_counts[role] = len(scores)

# Load existing weights
try:
    import subprocess
    result = subprocess.run(["yq", "e", "-o=json", ".", weights_file],
                           capture_output=True, text=True)
    weights_data = json.loads(result.stdout) if result.stdout.strip() else {}
except Exception:
    weights_data = {}

# N >= 30 gate
MIN_SAMPLES = 30
POSTERIOR_FLOOR = 0.5
POSTERIOR_CAP = 1.5

# Build a flat role→prior_weight lookup from the nested YAML structure
role_priors = {}
for cat_name, cat_data in weights_data.items():
    if isinstance(cat_data, dict):
        for role_name, role_data in cat_data.items():
            if isinstance(role_data, dict):
                pw = role_data.get("prior_weight", 1.0)
                if pw is not None:
                    role_priors[role_name] = pw

# Compute consensus (baseline) Brier
consensus_brier = role_briers.get("_consensus", None)

# Compute posteriors
posteriors = {}
for role, brier in role_briers.items():
    if role == "_consensus": continue
    n = role_counts.get(role, 0)

    if n < MIN_SAMPLES:
        # Cold start — keep prior
        posteriors[role] = {
            "brier": round(brier, 4),
            "n": n,
            "posterior_weight": None,
            "reason": f"cold_start (n={n} < {MIN_SAMPLES})"
        }
        continue

    # Posterior = prior * (consensus_brier / role_brier)
    # Better than consensus → weight goes up; worse → weight goes down
    prior = role_priors.get(role, 1.0)

    if consensus_brier and brier > 0:
        raw_posterior = prior * (consensus_brier / brier)
    else:
        raw_posterior = prior

    # Clamp to [0.5, 1.5]
    clamped = max(POSTERIOR_FLOOR, min(POSTERIOR_CAP, raw_posterior))

    posteriors[role] = {
        "brier": round(brier, 4),
        "n": n,
        "raw_posterior": round(raw_posterior, 4),
        "posterior_weight": round(clamped, 4),
        "reason": "calibrated"
    }

# Regime detection: 30d rolling Brier deterioration (consensus records only)
consensus_records = [r for r in records if r.get("role") == "_consensus"]
recent_30 = consensus_records[-30:] if len(consensus_records) >= 30 else consensus_records
recent_scores = []
for r in recent_30:
    bs = brier_score(r.get("predicted_dist"), r.get("truth_onehot"))
    if bs is not None:
        recent_scores.append(bs)

regime_warning = False
if recent_scores and consensus_brier:
    recent_avg = sum(recent_scores) / len(recent_scores)
    if recent_avg > consensus_brier * 1.5:
        regime_warning = True

# Build report
report = {
    "timestamp": datetime.now(timezone.utc).isoformat(),
    "total_records": len(records),
    "roles_evaluated": len(posteriors),
    "consensus_brier": round(consensus_brier, 4) if consensus_brier else None,
    "regime_warning": regime_warning,
    "role_results": posteriors
}

with open(report_file, "w") as f:
    json.dump(report, f, indent=2)

print(json.dumps(report, indent=2))
PYEOF

log "calibrate-posteriors complete"
