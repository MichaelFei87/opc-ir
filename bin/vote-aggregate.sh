#!/usr/bin/env bash
set -euo pipefail

# vote-aggregate.sh — Weighted vote aggregation with posterior cap
#
# Batch mode (aggregates ALL asset/horizon pairs found in strategist outputs):
#   vote-aggregate.sh <strategist-outputs-dir> <role-weights-yaml> <output-dir>
#
# Single mode (one asset/horizon — backward-compatible):
#   vote-aggregate.sh <strategist-outputs-dir> <asset> <horizon> <role-weights-yaml> <output.json>

if [[ $# -eq 3 ]]; then
  MODE="batch"
  STRAT_DIR="${1:?}"
  WEIGHTS_FILE="${2:?}"
  OUTPUT_DIR="${3:?}"
  export STRAT_DIR WEIGHTS_FILE OUTPUT_DIR
elif [[ $# -eq 5 ]]; then
  MODE="single"
  STRAT_DIR="${1:?}"
  ASSET="${2:?}"
  HORIZON="${3:?}"
  WEIGHTS_FILE="${4:?}"
  OUTPUT_FILE="${5:?}"
  export STRAT_DIR ASSET HORIZON WEIGHTS_FILE OUTPUT_FILE
else
  echo "Usage:" >&2
  echo "  Batch:  vote-aggregate.sh <strat-dir> <weights.yaml> <output-dir>" >&2
  echo "  Single: vote-aggregate.sh <strat-dir> <asset> <horizon> <weights.yaml> <output.json>" >&2
  exit 1
fi

export MODE
python3 << 'PYEOF'
import json, os, glob, sys

try:
    import yaml
except ImportError:
    sys.exit("ERROR: PyYAML not installed")

mode = os.environ["MODE"]
strat_dir = os.environ["STRAT_DIR"]
weights_file = os.environ["WEIGHTS_FILE"]

with open(weights_file) as f:
    forecast_weights = yaml.safe_load(f).get("forecast", {})

tiers = ["strongly_bearish", "bearish", "neutral", "bullish", "strongly_bullish"]

# Load all strategist files once
strategists = {}
for fpath in sorted(glob.glob(os.path.join(strat_dir, "*.json"))):
    role = os.path.splitext(os.path.basename(fpath))[0]
    with open(fpath) as f:
        strategists[role] = json.load(f)

def aggregate_one(asset, horizon):
    """Aggregate a single (asset, horizon) pair across all strategists."""
    agg = {t: 0.0 for t in tiers}
    total_weight = 0.0
    weights_used = []
    votes_found = []

    for role, entries in strategists.items():
        prior = forecast_weights.get(role, {}).get("prior_weight", 1.0)
        match = next((e for e in entries if e["asset"] == asset and e["horizon"] == horizon), None)
        if match is None:
            continue

        posterior_raw = match.get("posterior_weight", 1.0)
        posterior = max(0.5, min(1.5, posterior_raw))
        effective = prior * posterior

        dist = match["distribution"]

        # Validate distribution sums to ~1.0
        dist_sum = sum(dist.get(t, 0.0) for t in tiers)
        if abs(dist_sum - 1.0) > 0.05:
            print(f"WARNING: {role} distribution for {asset}/{horizon} sums to {dist_sum:.4f}, normalizing", file=sys.stderr)
            if dist_sum > 0:
                dist = {t: dist.get(t, 0.0) / dist_sum for t in tiers}
            else:
                print(f"ERROR: {role} distribution for {asset}/{horizon} sums to 0, skipping", file=sys.stderr)
                continue

        for t in tiers:
            agg[t] += dist.get(t, 0.0) * effective
        total_weight += effective

        weights_used.append({
            "role": role, "prior": prior,
            "posterior_raw": posterior_raw, "posterior_clamped": posterior,
            "effective": effective
        })
        votes_found.append({"role": role, "distribution": dist})

    if not votes_found:
        return None

    # Normalize
    if total_weight > 0:
        for t in tiers:
            agg[t] /= total_weight

    # Dissent check
    dissent = []
    for v in votes_found:
        l1 = sum(abs(v["distribution"].get(t, 0.0) - agg[t]) for t in tiers)
        if l1 > 0.3:
            dissent.append({"role": v["role"], "l1_distance": round(l1, 4), "distribution": v["distribution"]})

    return {
        "asset": asset, "horizon": horizon,
        "aggregated": {t: round(v, 6) for t, v in agg.items()},
        "dissent": dissent, "weights_used": weights_used,
        "total_weight": round(total_weight, 4)
    }

if mode == "single":
    asset = os.environ["ASSET"]
    horizon = os.environ["HORIZON"]
    output_file = os.environ["OUTPUT_FILE"]

    result = aggregate_one(asset, horizon)
    if result is None:
        sys.exit(f"ERROR: no votes found for {asset}/{horizon} in {strat_dir}")

    os.makedirs(os.path.dirname(output_file) or ".", exist_ok=True)
    with open(output_file, "w") as f:
        json.dump(result, f, indent=2)

elif mode == "batch":
    output_dir = os.environ["OUTPUT_DIR"]
    os.makedirs(output_dir, exist_ok=True)

    # Discover all (asset, horizon) pairs from strategist outputs
    pairs = set()
    for entries in strategists.values():
        for e in entries:
            pairs.add((e["asset"], e["horizon"]))

    ok = 0
    fail = 0
    for asset, horizon in sorted(pairs):
        result = aggregate_one(asset, horizon)
        if result is None:
            print(f"SKIP: no votes for {asset}/{horizon}", file=sys.stderr)
            fail += 1
            continue
        out_path = os.path.join(output_dir, f"{asset}_{horizon}.json")
        with open(out_path, "w") as f:
            json.dump(result, f, indent=2)
        ok += 1

    print(f"Aggregated {ok} pairs ({fail} skipped) → {output_dir}")
PYEOF
