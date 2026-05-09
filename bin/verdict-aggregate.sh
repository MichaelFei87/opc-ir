#!/usr/bin/env bash
set -euo pipefail

# verdict-aggregate.sh — Weighted verdict aggregation (5 schools + 2 advocates)
# Usage: verdict-aggregate.sh <votes.json> <output.json>
#
# Schools have weight 1.0, advocates have weight 0.5
# Direction scoring: long=+1, neutral=0, short=-1
# Split detection: weighted spread < 0.15

VOTES_FILE="${1:?Usage: verdict-aggregate.sh <votes.json> <output.json>}"
OUTPUT_FILE="${2:?Usage: verdict-aggregate.sh <votes.json> <output.json>}"

export VOTES_FILE OUTPUT_FILE
python3 << 'PYEOF'
import json, os

votes_file = os.environ["VOTES_FILE"]
output_file = os.environ["OUTPUT_FILE"]

with open(votes_file) as f:
    votes = json.load(f)

direction_scores = {"long": 1.0, "neutral": 0.0, "short": -1.0}
total_weighted_score = 0.0
total_weight = 0.0
vote_records = []
dissent = []
falsifiers = []

for vote in votes:
    weight = vote.get("weight", 1.0)
    direction = vote["direction"]
    score = direction_scores.get(direction, 0.0)
    weighted_score = score * weight

    total_weighted_score += weighted_score
    total_weight += weight

    vote_records.append({
        "role": vote["role"],
        "direction": direction,
        "weight": weight,
        "weighted_score": round(weighted_score, 4)
    })

    if "falsifier" in vote and vote["falsifier"]:
        falsifiers.append({
            "role": vote["role"],
            "condition": vote["falsifier"]
        })

# Determine consensus direction
if total_weight > 0:
    avg_score = total_weighted_score / total_weight
else:
    avg_score = 0.0

# Split detection: if magnitude < 0.15, it's a split
if abs(avg_score) < 0.15:
    consensus_direction = "split"
elif avg_score > 0:
    consensus_direction = "long"
else:
    consensus_direction = "short"

conviction = abs(avg_score)

# Detect dissent: roles opposing the consensus
for vote in votes:
    direction = vote["direction"]
    if consensus_direction == "long" and direction == "short":
        dissent.append({
            "role": vote["role"],
            "direction": direction,
            "reasoning_summary": vote.get("thesis", "No thesis provided")
        })
    elif consensus_direction == "short" and direction == "long":
        dissent.append({
            "role": vote["role"],
            "direction": direction,
            "reasoning_summary": vote.get("thesis", "No thesis provided")
        })

result = {
    "consensus": {
        "direction": consensus_direction,
        "conviction": round(conviction, 4),
        "horizon": votes[0].get("horizon", "1m") if votes else "1m"
    },
    "votes": vote_records,
    "preserved_dissent": dissent,
    "falsifiers": falsifiers,
    "total_weight": round(total_weight, 4),
    "avg_score": round(avg_score, 4)
}

with open(output_file, "w") as f:
    json.dump(result, f, indent=2)
PYEOF
