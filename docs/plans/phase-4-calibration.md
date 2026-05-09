# Phase 4: Calibration — Implementation Plan

> **Status**: Draft
> **Date**: 2026-05-08
> **Prerequisite**: Phases 1–3 complete (forecast.jsonl, verdicts.jsonl, events.jsonl populated with live data; role-weights.yaml contains prior weights only; world-model + thesis persistence operational; auto-loop with ingestion running)
> **Effort**: 6–8 days (4–6 hrs/day)
> **Spec reference**: `docs/specs/2026-05-08-opc-ir-overview-design.md` §3.7, §4.4, §6 Phase 4

---

## Overview

Phase 4 closes the learning loop. Prior phases produce predictions; Phase 4 measures them against reality and adjusts role weights accordingly. The system transitions from equal-weight voting to calibration-informed voting, with safeguards against small-sample bias, anomalous distributions, and regime change.

**Milestone summary**:

| Milestone | Scope | Days |
|---|---|---|
| M4.1 | Price truth (fetch-prices.sh + ground-truth-linker.sh) | 1.5 |
| M4.2 | Event truth (verdict-judge calibration mode) | 1.5 |
| M4.3 | Posterior calculation (Brier + N≥30 + anomaly rejection) | 1.5 |
| M4.4 | Regime detection (30d rolling Brier deterioration) | 1 |
| M4.5 | events.jsonl monthly rolling | 0.5 |

**Dependency within Phase 4**:

```
M4.1 ──┐
       ├── M4.3 ── M4.4
M4.2 ──┘
M4.5 (independent, parallelizable with any)
```

---

## M4.1: Price Truth

### Goal

Fetch historical prices for assets at prediction time + horizon, map price movements to the 5-tier bucket system used in forecasts, and link each forecast row to its ground-truth outcome.

### M4.1.1: `bin/fetch-prices.sh`

Multi-source price fetcher with fallback chain. Pure shell, no LLM.

**File**: `bin/fetch-prices.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# fetch-prices.sh — Fetch historical close prices for OPC-IR calibration.
# Usage: fetch-prices.sh <asset> <date-YYYY-MM-DD>
# Output: JSON to stdout: {"asset":"NDX","date":"2026-05-08","close":18542.30,"source":"yahoo"}
# Exit 0 = success, Exit 1 = all sources failed.

ASSET="$1"
DATE="$2"
LOG_DIR="${OPC_IR_HOME:-$HOME/.opc-ir}/logs"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).log"
mkdir -p "$LOG_DIR"

# Asset → ticker mapping for each source
declare -A YAHOO_MAP=(
  [NDX]="^IXIC" [SPX]="^GSPC" [RUT]="^RUT" [VIX]="^VIX"
  [HSI]="^HSI" [HSCEI]="^HSCE" [CSI300]="000300.SS"
  [CYB]="CYB" [DXY]="DX-Y.NYB" [CNH]="CNH=X"
  [GLD]="GC=F" [ZB]="ZB=F" [WTI]="CL=F" [BTC]="BTC-USD"
)

declare -A FRED_MAP=(
  [DXY]="DTWEXBGS" [VIX]="VIXCLS" [GLD]="GOLDAMGBD228NLBM"
  [WTI]="DCOILWTICO" [ZB]="DGS30"
)

declare -A ALPHAVANTAGE_MAP=(
  [NDX]="NDX" [SPX]="SPX" [RUT]="RUT" [BTC]="BTC"
  [GLD]="GLD" [WTI]="WTI" [DXY]="DXY"
)

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] fetch-prices: $*" >> "$LOG_FILE"; }

# Source 1: Yahoo Finance (via yfinance-style curl)
fetch_yahoo() {
  local ticker="${YAHOO_MAP[$ASSET]:-}"
  [[ -z "$ticker" ]] && return 1

  local period1 period2
  period1=$(date -d "$DATE" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$DATE" +%s 2>/dev/null) || return 1
  period2=$((period1 + 86400))

  local url="https://query1.finance.yahoo.com/v8/finance/chart/${ticker}?period1=${period1}&period2=${period2}&interval=1d"
  local resp
  resp=$(curl -sf --max-time 10 -H "User-Agent: Mozilla/5.0" "$url" 2>/dev/null) || return 1

  local close
  close=$(echo "$resp" | jq -r '.chart.result[0].indicators.quote[0].close[0] // empty' 2>/dev/null) || return 1
  [[ -z "$close" || "$close" == "null" ]] && return 1

  echo "{\"asset\":\"$ASSET\",\"date\":\"$DATE\",\"close\":$close,\"source\":\"yahoo\"}"
}

# Source 2: FRED (US economic data — limited asset coverage)
fetch_fred() {
  local series="${FRED_MAP[$ASSET]:-}"
  [[ -z "$series" ]] && return 1

  local api_key="${FRED_API_KEY:-}"
  [[ -z "$api_key" ]] && return 1

  local url="https://api.stlouisfed.org/fred/series/observations?series_id=${series}&observation_start=${DATE}&observation_end=${DATE}&api_key=${api_key}&file_type=json"
  local resp
  resp=$(curl -sf --max-time 10 "$url" 2>/dev/null) || return 1

  local value
  value=$(echo "$resp" | jq -r '.observations[0].value // empty' 2>/dev/null) || return 1
  [[ -z "$value" || "$value" == "." ]] && return 1

  echo "{\"asset\":\"$ASSET\",\"date\":\"$DATE\",\"close\":$value,\"source\":\"fred\"}"
}

# Source 3: Alpha Vantage (requires free API key)
fetch_alphavantage() {
  local ticker="${ALPHAVANTAGE_MAP[$ASSET]:-}"
  [[ -z "$ticker" ]] && return 1

  local api_key="${ALPHAVANTAGE_API_KEY:-}"
  [[ -z "$api_key" ]] && return 1

  local url="https://www.alphavantage.co/query?function=TIME_SERIES_DAILY&symbol=${ticker}&apikey=${api_key}&outputsize=compact"
  local resp
  resp=$(curl -sf --max-time 15 "$url" 2>/dev/null) || return 1

  local close
  close=$(echo "$resp" | jq -r ".\"Time Series (Daily)\".\"${DATE}\".\"4. close\" // empty" 2>/dev/null) || return 1
  [[ -z "$close" ]] && return 1

  echo "{\"asset\":\"$ASSET\",\"date\":\"$DATE\",\"close\":$close,\"source\":\"alphavantage\"}"
}

# Try sources in priority order
for fetcher in fetch_yahoo fetch_fred fetch_alphavantage; do
  result=$($fetcher 2>/dev/null) && {
    log "OK: $ASSET $DATE via $fetcher"
    echo "$result"
    exit 0
  }
  log "FAIL: $ASSET $DATE via $fetcher"
done

log "ALL_FAILED: $ASSET $DATE"
exit 1
```

**Design decisions**:
- Yahoo Finance first (broadest coverage, no key required).
- FRED second (reliable for US macro, requires free key).
- Alpha Vantage third (requires free key, rate-limited).
- Each source has its own ticker mapping — not all assets available at all sources.
- Timeout 10–15s per source. Total worst-case: ~45s per asset/date pair.
- Output is single-line JSON to stdout; caller parses.
- Failures logged but never fatal to the caller — missing price = skip sample.

### M4.1.2: `bin/ground-truth-linker.sh`

Aligns matured predictions to fetched prices and produces ground-truth records.

**File**: `bin/ground-truth-linker.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# ground-truth-linker.sh — Link matured forecast/verdict predictions to price truth.
# Usage: ground-truth-linker.sh
# Reads: forecast.jsonl, verdicts.jsonl, predictions-vs-truth.jsonl, human-overrides.jsonl
# Writes: appends to predictions-vs-truth.jsonl
# Exit 0 = success (possibly 0 new links)

OPC_IR_HOME="${OPC_IR_HOME:-$HOME/.opc-ir}"
FORECAST_JSONL="$OPC_IR_HOME/forecast/forecast.jsonl"
VERDICTS_JSONL="$OPC_IR_HOME/verdict/verdicts.jsonl"
TRUTH_JSONL="$OPC_IR_HOME/calibration/predictions-vs-truth.jsonl"
OVERRIDES_JSONL="$OPC_IR_HOME/calibration/human-overrides.jsonl"
LOG_FILE="$OPC_IR_HOME/logs/$(date +%Y-%m-%d).log"
FETCH_PRICES="$(dirname "$0")/fetch-prices.sh"

mkdir -p "$OPC_IR_HOME/calibration" "$(dirname "$LOG_FILE")"
touch "$TRUTH_JSONL"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ground-truth-linker: $*" >> "$LOG_FILE"; }

NOW_EPOCH=$(date +%s)

# Horizons mapping (from defaults/horizons.yaml convention)
declare -A HORIZON_DAYS=([1d]=1 [1w]=7 [1m]=30 [3m]=90)

# 5-tier bucket mapping: price % change → tier
# Tiers: strong_down (<-5%), down (-5% to -1%), neutral (-1% to +1%), up (+1% to +5%), strong_up (>+5%)
bucket_from_pct() {
  local pct="$1"
  awk -v p="$pct" 'BEGIN {
    if (p <= -5) print "strong_down"
    else if (p <= -1) print "down"
    else if (p <= 1) print "neutral"
    else if (p <= 5) print "up"
    else print "strong_up"
  }'
}

# One-hot vector from bucket (for Brier score calculation)
onehot_from_bucket() {
  case "$1" in
    strong_down) echo '[1,0,0,0,0]' ;;
    down)        echo '[0,1,0,0,0]' ;;
    neutral)     echo '[0,0,1,0,0]' ;;
    up)          echo '[0,0,0,1,0]' ;;
    strong_up)   echo '[0,0,0,0,1]' ;;
    *)           echo 'null' ;;
  esac
}

# Collect already-linked (run_id, asset, horizon) to avoid double-linking
declare -A ALREADY_LINKED
while IFS= read -r line; do
  key=$(echo "$line" | jq -r '"\(.run_id)|\(.asset)|\(.horizon)"' 2>/dev/null) || continue
  ALREADY_LINKED["$key"]=1
done < "$TRUTH_JSONL"

NEW_RECORDS=0

# Process forecast predictions
process_forecast_row() {
  local line="$1"
  local run_id ts
  run_id=$(echo "$line" | jq -r '.run_id') || return
  ts=$(echo "$line" | jq -r '.ts') || return

  local ts_epoch
  ts_epoch=$(date -d "$ts" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null) || return

  # Iterate each asset × horizon in the forecast
  local assets horizons
  assets=$(echo "$line" | jq -r '.forecasts | keys[]' 2>/dev/null) || return

  for asset in $assets; do
    horizons=$(echo "$line" | jq -r ".forecasts.\"$asset\" | keys[]" 2>/dev/null) || continue
    for horizon in $horizons; do
      local key="${run_id}|${asset}|${horizon}"
      [[ -n "${ALREADY_LINKED[$key]:-}" ]] && continue

      local horizon_days="${HORIZON_DAYS[$horizon]:-}"
      [[ -z "$horizon_days" ]] && continue

      local maturity_epoch=$((ts_epoch + horizon_days * 86400))
      [[ $NOW_EPOCH -lt $maturity_epoch ]] && continue  # not yet matured

      local pred_date target_date
      pred_date=$(date -d "@$ts_epoch" +%Y-%m-%d 2>/dev/null || date -r "$ts_epoch" +%Y-%m-%d 2>/dev/null)
      target_date=$(date -d "@$maturity_epoch" +%Y-%m-%d 2>/dev/null || date -r "$maturity_epoch" +%Y-%m-%d 2>/dev/null)

      # Check human override first
      local human_truth=""
      if [[ -f "$OVERRIDES_JSONL" ]]; then
        human_truth=$(jq -r --arg rid "$run_id" --arg a "$asset" --arg h "$horizon" \
          'select(.run_id == $rid and .asset == $a and .horizon == $h) | .truth_bucket' \
          "$OVERRIDES_JSONL" 2>/dev/null | head -1)
      fi

      local truth_bucket truth_source truth_onehot
      if [[ -n "$human_truth" && "$human_truth" != "null" ]]; then
        truth_bucket="$human_truth"
        truth_source="human"
      else
        # Fetch prices at prediction time and at maturity
        local price_pred price_truth
        price_pred=$("$FETCH_PRICES" "$asset" "$pred_date" 2>/dev/null) || { log "SKIP: no pred-date price $asset $pred_date"; continue; }
        price_truth=$("$FETCH_PRICES" "$asset" "$target_date" 2>/dev/null) || { log "SKIP: no truth-date price $asset $target_date"; continue; }

        local close_pred close_truth pct_change
        close_pred=$(echo "$price_pred" | jq -r '.close')
        close_truth=$(echo "$price_truth" | jq -r '.close')

        pct_change=$(awk -v a="$close_pred" -v b="$close_truth" 'BEGIN { if (a==0) print "NaN"; else printf "%.4f", (b-a)/a*100 }')
        [[ "$pct_change" == "NaN" ]] && { log "SKIP: zero pred price $asset $pred_date"; continue; }

        truth_bucket=$(bucket_from_pct "$pct_change")
        truth_source="price"
      fi

      truth_onehot=$(onehot_from_bucket "$truth_bucket")

      # Extract per-role predictions from the forecast (strategists)
      local strategist_votes
      strategist_votes=$(echo "$line" | jq -c ".votes // []" 2>/dev/null)

      # Extract the consensus distribution for this asset/horizon
      local predicted_dist
      predicted_dist=$(echo "$line" | jq -c ".forecasts.\"$asset\".\"$horizon\"" 2>/dev/null)

      # Write one record per role that voted on this asset/horizon
      local n_roles
      n_roles=$(echo "$strategist_votes" | jq 'length' 2>/dev/null || echo 0)

      if [[ "$n_roles" -gt 0 ]]; then
        for i in $(seq 0 $((n_roles - 1))); do
          local role role_dist
          role=$(echo "$strategist_votes" | jq -r ".[$i].role" 2>/dev/null) || continue
          role_dist=$(echo "$strategist_votes" | jq -c ".[$i].forecasts.\"$asset\".\"$horizon\" // null" 2>/dev/null)
          [[ "$role_dist" == "null" ]] && continue

          local record
          record=$(jq -nc \
            --arg rid "$run_id" \
            --arg asset "$asset" \
            --arg horizon "$horizon" \
            --arg role "$role" \
            --arg stream "forecast" \
            --arg truth_bucket "$truth_bucket" \
            --arg truth_source "$truth_source" \
            --argjson truth_onehot "$truth_onehot" \
            --argjson predicted_dist "$role_dist" \
            --arg pred_date "$pred_date" \
            --arg target_date "$target_date" \
            '{
              run_id: $rid, asset: $asset, horizon: $horizon, role: $role,
              stream: $stream, predicted_dist: $predicted_dist,
              truth_bucket: $truth_bucket, truth_onehot: $truth_onehot,
              truth_source: $truth_source,
              pred_date: $pred_date, target_date: $target_date,
              linked_at: (now | todate)
            }')
          echo "$record" >> "$TRUTH_JSONL"
          ALREADY_LINKED["${run_id}|${asset}|${horizon}|${role}"]=1
          ((NEW_RECORDS++))
        done
      fi

      # Also record consensus-level for aggregate tracking
      if [[ "$predicted_dist" != "null" ]]; then
        local record
        record=$(jq -nc \
          --arg rid "$run_id" \
          --arg asset "$asset" \
          --arg horizon "$horizon" \
          --arg role "_consensus" \
          --arg stream "forecast" \
          --arg truth_bucket "$truth_bucket" \
          --arg truth_source "$truth_source" \
          --argjson truth_onehot "$truth_onehot" \
          --argjson predicted_dist "$predicted_dist" \
          --arg pred_date "$pred_date" \
          --arg target_date "$target_date" \
          '{
            run_id: $rid, asset: $asset, horizon: $horizon, role: $role,
            stream: $stream, predicted_dist: $predicted_dist,
            truth_bucket: $truth_bucket, truth_onehot: $truth_onehot,
            truth_source: $truth_source,
            pred_date: $pred_date, target_date: $target_date,
            linked_at: (now | todate)
          }')
        echo "$record" >> "$TRUTH_JSONL"
      fi
    done
  done
}

# Process each forecast row
while IFS= read -r line; do
  process_forecast_row "$line"
done < "$FORECAST_JSONL"

# Process verdict predictions (similar but uses schools/advocates and verdict buckets)
while IFS= read -r line; do
  local run_id ts asset
  run_id=$(echo "$line" | jq -r '.run_id' 2>/dev/null) || continue
  ts=$(echo "$line" | jq -r '.ts' 2>/dev/null) || continue
  asset=$(echo "$line" | jq -r '.asset // .ticker' 2>/dev/null) || continue

  # Verdicts may carry per-role horizon predictions; process similarly
  local votes
  votes=$(echo "$line" | jq -c '.votes // []' 2>/dev/null) || continue

  local n_votes
  n_votes=$(echo "$votes" | jq 'length' 2>/dev/null || echo 0)
  [[ "$n_votes" -eq 0 ]] && continue

  for i in $(seq 0 $((n_votes - 1))); do
    local role horizon predicted_dist
    role=$(echo "$votes" | jq -r ".[$i].role" 2>/dev/null) || continue
    horizon=$(echo "$votes" | jq -r ".[$i].horizon // \"1m\"" 2>/dev/null)

    local key="${run_id}|${asset}|${horizon}|${role}"
    [[ -n "${ALREADY_LINKED[$key]:-}" ]] && continue

    predicted_dist=$(echo "$votes" | jq -c ".[$i].distribution // null" 2>/dev/null)
    [[ "$predicted_dist" == "null" ]] && continue

    local ts_epoch horizon_days maturity_epoch
    ts_epoch=$(date -d "$ts" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null) || continue
    horizon_days="${HORIZON_DAYS[$horizon]:-30}"
    maturity_epoch=$((ts_epoch + horizon_days * 86400))
    [[ $NOW_EPOCH -lt $maturity_epoch ]] && continue

    local pred_date target_date
    pred_date=$(date -d "@$ts_epoch" +%Y-%m-%d 2>/dev/null || date -r "$ts_epoch" +%Y-%m-%d 2>/dev/null)
    target_date=$(date -d "@$maturity_epoch" +%Y-%m-%d 2>/dev/null || date -r "$maturity_epoch" +%Y-%m-%d 2>/dev/null)

    # Human override check
    local human_truth=""
    if [[ -f "$OVERRIDES_JSONL" ]]; then
      human_truth=$(jq -r --arg rid "$run_id" --arg a "$asset" --arg h "$horizon" \
        'select(.run_id == $rid and .asset == $a and .horizon == $h) | .truth_bucket' \
        "$OVERRIDES_JSONL" 2>/dev/null | head -1)
    fi

    local truth_bucket truth_source
    if [[ -n "$human_truth" && "$human_truth" != "null" ]]; then
      truth_bucket="$human_truth"
      truth_source="human"
    else
      local price_pred price_truth
      price_pred=$("$FETCH_PRICES" "$asset" "$pred_date" 2>/dev/null) || continue
      price_truth=$("$FETCH_PRICES" "$asset" "$target_date" 2>/dev/null) || continue

      local close_pred close_truth pct_change
      close_pred=$(echo "$price_pred" | jq -r '.close')
      close_truth=$(echo "$price_truth" | jq -r '.close')
      pct_change=$(awk -v a="$close_pred" -v b="$close_truth" 'BEGIN { if (a==0) print "NaN"; else printf "%.4f", (b-a)/a*100 }')
      [[ "$pct_change" == "NaN" ]] && continue

      truth_bucket=$(bucket_from_pct "$pct_change")
      truth_source="price"
    fi

    local truth_onehot
    truth_onehot=$(onehot_from_bucket "$truth_bucket")

    local record
    record=$(jq -nc \
      --arg rid "$run_id" \
      --arg asset "$asset" \
      --arg horizon "$horizon" \
      --arg role "$role" \
      --arg stream "verdict" \
      --arg truth_bucket "$truth_bucket" \
      --arg truth_source "$truth_source" \
      --argjson truth_onehot "$truth_onehot" \
      --argjson predicted_dist "$predicted_dist" \
      --arg pred_date "$pred_date" \
      --arg target_date "$target_date" \
      '{
        run_id: $rid, asset: $asset, horizon: $horizon, role: $role,
        stream: $stream, predicted_dist: $predicted_dist,
        truth_bucket: $truth_bucket, truth_onehot: $truth_onehot,
        truth_source: $truth_source,
        pred_date: $pred_date, target_date: $target_date,
        linked_at: (now | todate)
      }')
    echo "$record" >> "$TRUTH_JSONL"
    ALREADY_LINKED["$key"]=1
    ((NEW_RECORDS++))
  done
done < "$VERDICTS_JSONL"

log "ground-truth-linker complete: $NEW_RECORDS new records"
echo "{\"new_records\": $NEW_RECORDS}"
exit 0
```

### M4.1.3: 5-tier bucket thresholds

Added to `defaults/horizons.yaml`:

```yaml
horizons:
  1d: { days: 1 }
  1w: { days: 7 }
  1m: { days: 30 }
  3m: { days: 90 }

# 5-tier bucket thresholds (% price change)
# Used by ground-truth-linker.sh and forecast roles
bucket_thresholds:
  strong_down: "< -5%"
  down: "-5% to -1%"
  neutral: "-1% to +1%"
  up: "+1% to +5%"
  strong_up: "> +5%"
```

### M4.1 Exit Criteria

1. `bin/fetch-prices.sh NDX 2026-04-01` returns valid JSON with a close price from at least one source.
2. `bin/fetch-prices.sh` gracefully fails (exit 1, no crash) when all sources are down or asset is unknown.
3. `bin/ground-truth-linker.sh` links at least one matured forecast to a price truth record in `predictions-vs-truth.jsonl`.
4. Already-linked records are not duplicated on re-run.
5. Human overrides in `human-overrides.jsonl` take priority over price truth.

---

## M4.2: Event Truth

### Goal

For verdict predictions that carry falsifiers, use `verdict-judge` in calibration mode to evaluate whether the falsifier was triggered by events that occurred between prediction and maturity.

### M4.2.1: Calibration mode for `agents/verdict-judge.md`

The existing `verdict-judge.md` agent is dual-purpose (spec §3.6 note). We add a calibration-mode section to the agent file.

**Append to `agents/verdict-judge.md`**:

```markdown
---

## Calibration Mode

When invoked with `mode: calibration`, the verdict-judge evaluates whether a thesis's falsifier was triggered by subsequent events. This is NOT a new verdict — it is a post-hoc binary judgment.

### Input (calibration mode)

- `thesis`: The original thesis text from the verdict
- `falsifier`: The specific falsifier condition from the verdict
- `events_since`: Events from events.jsonl between verdict date and maturity date
- `price_outcome`: The price truth bucket (from ground-truth-linker) if available

### Output (calibration mode)

JSON to stdout:

```json
{
  "falsifier_triggered": true | false,
  "confidence": 0.85,
  "reasoning": "The falsifier specified 'Fed cuts rates below 4.5% before 2026-06-01'. On 2026-05-15, the Fed announced a 25bp cut to 4.25%, satisfying the condition.",
  "supporting_events": ["event-id-1", "event-id-2"]
}
```

### Rules (calibration mode)

1. Evaluate ONLY the specific falsifier condition — not whether the thesis was "right" in general.
2. A falsifier is triggered if its specific numeric/temporal/asset condition was met.
3. If the falsifier references a price level, check against the price_outcome.
4. If insufficient information to judge, set `falsifier_triggered: false` and `confidence: < 0.5`.
5. Do NOT consider information that arrived after the maturity date.
```

### M4.2.2: Calibration event-truth runner

This logic lives in the `/opc-ir-calibrate` command. The command invokes `verdict-judge` in calibration mode for each matured verdict that has a falsifier.

**Addition to `commands/opc-ir-calibrate.md`** (event truth section):

```markdown
## Step 2: Event Truth (Verdict Falsifier Evaluation)

For each matured verdict in `verdicts.jsonl` that:
- Has matured (ts + horizon < now)
- Has not yet been linked in `predictions-vs-truth.jsonl`
- Contains at least one falsifier

Do:

1. Gather events from `events.jsonl` between the verdict's `ts` and `ts + horizon_days`.
2. Dispatch `verdict-judge` with `mode: calibration`, passing:
   - The verdict's thesis and falsifier
   - The gathered events
   - The price outcome (if already computed in Step 1)
3. If `falsifier_triggered: true` with `confidence >= 0.7`:
   - The truth is the **opposite** of the predicted direction (the thesis was invalidated).
   - Record `truth_source: "event"` in predictions-vs-truth.jsonl.
4. If `falsifier_triggered: false` or `confidence < 0.7`:
   - Fall through to price truth (already handled by ground-truth-linker in Step 1).

### Truth source priority merge

For each (run_id, asset, horizon, role) tuple, the final truth record uses:
1. `human` — if present in `human-overrides.jsonl` (already applied in Step 1)
2. `event` — if falsifier was triggered with high confidence (this step)
3. `price` — price bucket from ground-truth-linker (Step 1 default)

If event truth disagrees with price truth, event truth wins (spec §3.7: human > event > price).
```

### M4.2 Exit Criteria

1. A verdict with a clear falsifier (e.g., "NDX drops below 17000 by 2026-06-01") is correctly judged as triggered or not.
2. Event truth records are written to `predictions-vs-truth.jsonl` with `truth_source: "event"`.
3. Event truth overrides price truth for the same (run_id, asset, horizon, role) tuple.
4. Verdicts without falsifiers fall through to price truth only.

---

## M4.3: Posterior Calculation

### Goal

Compute Brier scores per role, derive posterior weights, enforce N≥30 floor, anomaly rejection, and write `role-weights.yaml`.

### M4.3.1: Brier score computation

**Addition to `commands/opc-ir-calibrate.md`** (Step 3):

```markdown
## Step 3: Posterior Weight Calculation

### 3a. Compute Brier scores

For each role `r` across all linked records in `predictions-vs-truth.jsonl`:

```
brier(r) = (1/N_r) * Σ_i Σ_k (predicted_dist[i][k] - truth_onehot[i][k])²
```

Where:
- `N_r` = number of linked samples for role `r`
- `k` = tier index (0..4 for the 5 tiers)
- `i` = sample index

Also compute the prior Brier (equal-weight consensus):

```
prior_brier = (1/N_total) * Σ_i Σ_k (consensus_dist[i][k] - truth_onehot[i][k])²
```

Where `consensus_dist` uses equal (prior) weights across all roles.

### 3b. N≥30 gate

For each role `r`:
- If `N_r < 30`: posterior weight remains `1.0` (cold-start; spec principle #4)
- If `N_r >= 30`: proceed to posterior calculation

### 3c. Posterior calculation

```
raw_posterior(r) = prior_brier / brier(r)
posterior(r) = clamp(raw_posterior, 0.5, 1.5)
```

Interpretation:
- `posterior > 1.0` → role is better-calibrated than equal-weight consensus → upweighted
- `posterior < 1.0` → role is worse-calibrated → downweighted
- Clamped to [0.5, 1.5] to prevent weight collapse (spec M3 mitigation)

### 3d. Anomaly rejection

Before writing `role-weights.yaml`, check:

1. **All-same rejection**: If ALL posterior values are identical (within ε=0.001), reject. This indicates a data or computation bug.
2. **NaN/Inf rejection**: If ANY posterior is NaN or Inf, reject entire write.
3. **All-boundary rejection**: If ALL posteriors are at the clamp boundary (all 0.5 or all 1.5), reject. This indicates extreme miscalibration or bad data.

On rejection: log warning, retain previous `role-weights.yaml`, write `anomaly_rejected: true` + reason to log.

### 3e. Write role-weights.yaml

Only if all checks pass:
```

**File**: `pipeline/calibration-protocol.md` (Brier computation logic, invoked by opc-ir-calibrate):

```markdown
---
forked-from: none (OPC-IR native)
created: 2026-05-08
---

# Calibration Protocol

## Purpose

Compute posterior role weights from ground-truth-aligned prediction records. This protocol is the core math of the calibration loop.

## Input

- `~/.opc-ir/calibration/predictions-vs-truth.jsonl` — all linked records
- `defaults/role-weights.yaml` — prior weights

## Algorithm

### Step 1: Group records by role

Group all records from `predictions-vs-truth.jsonl` by the `role` field. Exclude `_consensus` records (used for prior_brier only).

### Step 2: Compute per-role Brier score

For each role `r` with records `R_r`:

```
N_r = |R_r|
brier_r = (1 / N_r) * sum over i in R_r of sum over k=0..4 of (predicted_dist[i][k] - truth_onehot[i][k])^2
```

A perfect predictor has brier = 0. A maximally wrong predictor has brier = 2.0. Random uniform guessing has brier ≈ 1.6.

### Step 3: Compute prior Brier

Using `_consensus` records (which reflect equal-weight aggregation):

```
prior_brier = (1 / N_consensus) * sum over i of sum over k=0..4 of (consensus_dist[i][k] - truth_onehot[i][k])^2
```

### Step 4: Compute posteriors

For each role `r` where `N_r >= 30`:

```
raw = prior_brier / brier_r
posterior_r = max(0.5, min(1.5, raw))
```

For roles with `N_r < 30`: `posterior_r = 1.0`

### Step 5: Anomaly check

Reject the entire posterior vector if:
- Any value is NaN or Inf
- All values are equal (within 0.001)
- All values are at clamp boundaries (all 0.5 or all 1.5)

### Step 6: Write

Write `~/.opc-ir/calibration/role-weights.yaml`:

```yaml
# Auto-generated by /opc-ir-calibrate. Do not hand-edit.
# Last updated: {timestamp}
# Total samples: {N_total}
# Prior Brier: {prior_brier}

strategists:
  macro-strategist:     { prior: 1.0, posterior: 1.12, N: 45, brier: 0.89 }
  cross-asset-allocator: { prior: 1.0, posterior: 0.95, N: 42, brier: 1.05 }
  regime-detector:      { prior: 1.0, posterior: 1.08, N: 38, brier: 0.93 }
  historical-analogist: { prior: 1.0, posterior: 0.87, N: 41, brier: 1.15 }
  contrarian-strategist: { prior: 1.0, posterior: 1.03, N: 39, brier: 0.97 }

schools:
  fundamental-school:   { prior: 1.0, posterior: 1.0, N: 18, brier: null }  # N<30
  technical-school:     { prior: 1.0, posterior: 1.0, N: 22, brier: null }
  macro-school:         { prior: 1.0, posterior: 1.0, N: 15, brier: null }
  sentiment-school:     { prior: 1.0, posterior: 1.0, N: 12, brier: null }
  geopolitical-school:  { prior: 1.0, posterior: 1.0, N: 8,  brier: null }

advocates:
  bull-advocate:        { prior: 0.5, posterior: 1.0, N: 12, brier: null }
  bear-advocate:        { prior: 0.5, posterior: 1.0, N: 12, brier: null }

metadata:
  last_calibrated: "2026-06-15T00:00:00Z"
  prior_brier: 1.02
  total_samples: 312
  anomaly_rejected: false
  regime_warning: false
```

## Invariants

- `role-weights.yaml` is the ONLY file that calibration writes outside of calibration/.
- Vote-protocol reads `prior * posterior` as the effective weight.
- If `role-weights.yaml` is deleted, system degenerates to defaults/ (all posteriors 1.0).
```

### M4.3 Exit Criteria

1. With 30+ synthetic records per role, `role-weights.yaml` is written with differentiated posteriors.
2. With <30 records for a role, that role's posterior remains 1.0.
3. Injecting all-identical predictions → anomaly rejection fires, previous weights retained.
4. Injecting NaN predictions → anomaly rejection fires.
5. Posterior values are within [0.5, 1.5] for all roles.
6. Re-running calibrate with no new matured predictions produces identical output.

---

## M4.4: Regime Detection

### Goal

Detect when a role's calibration is deteriorating (30-day rolling Brier worsening), indicating a possible regime change. On detection: reset that role's posterior to 1.0 and inject a warning into digest.md.

### M4.4.1: Rolling Brier computation

**Addition to `pipeline/calibration-protocol.md`** (after Step 6):

```markdown
### Step 7: Regime Detection

For each role `r` where `N_r >= 30`:

1. Compute `brier_30d(r)`: Brier score using ONLY records from the last 30 days.
2. Compute `brier_full(r)`: Brier score using ALL records (already computed in Step 2).
3. Compute deterioration ratio: `deterioration = brier_30d(r) / brier_full(r)`

If `deterioration > 1.5` (recent 30-day Brier is 50%+ worse than historical):
- Reset `posterior_r = 1.0`
- Set `regime_warning: true` in metadata
- Record `regime_reset` event in predictions-vs-truth.jsonl:
  ```json
  {
    "type": "regime_reset",
    "role": "macro-strategist",
    "ts": "2026-06-15T00:00:00Z",
    "brier_30d": 1.45,
    "brier_full": 0.89,
    "deterioration": 1.63,
    "action": "posterior_reset_to_1.0"
  }
  ```

### Step 8: Digest warning injection

If any role had a regime reset in this calibration run:

Append to the `regime_warnings` section of `role-weights.yaml`:

```yaml
regime_warnings:
  - role: macro-strategist
    detected_at: "2026-06-15T00:00:00Z"
    deterioration: 1.63
    action: "Posterior reset to 1.0. Recent predictions significantly worse than historical."
```

The `/opc-ir-digest` command reads `regime_warnings` and renders them in `digest.md`:

```markdown
## ⚠️ Regime Warnings

**macro-strategist** calibration deteriorating (recent Brier 63% worse than historical).
Posterior weight has been reset to 1.0 (equal weight). This may indicate a structural
market regime change that this role's methodology is not adapted to.

> Last detected: 2026-06-15
```
```

### M4.4.2: Deterioration threshold configuration

**Addition to `defaults/role-weights.yaml`**:

```yaml
calibration_config:
  n_floor: 30
  posterior_clamp: [0.5, 1.5]
  regime_deterioration_threshold: 1.5   # 30d brier / full brier
  regime_lookback_days: 30
  regime_min_samples_30d: 10            # need at least 10 samples in 30d window to judge
```

### M4.4 Exit Criteria

1. Injecting a role with good historical Brier (0.8) but terrible recent 30-day Brier (1.4) triggers regime detection.
2. The role's posterior is reset to 1.0 in `role-weights.yaml`.
3. `regime_warning: true` appears in metadata.
4. `digest.md` renders the warning banner.
5. Roles with fewer than 10 samples in the 30-day window are not subject to regime detection (insufficient data).

---

## M4.5: events.jsonl Monthly Rolling

### Goal

Prevent unbounded growth of `events.jsonl` by splitting into monthly files. Cross-month queries still work via a grep wrapper.

### M4.5.1: Monthly file layout

```
~/.opc-ir/events/
├── events.jsonl              → symlink to current month
├── 2026-04-events.jsonl
├── 2026-05-events.jsonl
└── 2026-06-events.jsonl
```

### M4.5.2: Rolling logic in `bin/fetch-rss.sh`

**Modification to `bin/fetch-rss.sh`** (replace the single events.jsonl write with monthly routing):

```bash
# At the top of fetch-rss.sh, replace the EVENTS_FILE assignment:

EVENTS_DIR="${OPC_IR_HOME:-$HOME/.opc-ir}/events"
CURRENT_MONTH=$(date +%Y-%m)
EVENTS_FILE="$EVENTS_DIR/${CURRENT_MONTH}-events.jsonl"
EVENTS_SYMLINK="$EVENTS_DIR/events.jsonl"

mkdir -p "$EVENTS_DIR"
touch "$EVENTS_FILE"

# Update symlink to point to current month
ln -sf "${CURRENT_MONTH}-events.jsonl" "$EVENTS_SYMLINK"
```

### M4.5.3: Cross-month grep utility

**File**: `bin/events-grep.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# events-grep.sh — Search across monthly events files.
# Usage: events-grep.sh [--after YYYY-MM-DD] [--before YYYY-MM-DD] [--months N] [--jq FILTER]
# Default: last 3 months

EVENTS_DIR="${OPC_IR_HOME:-$HOME/.opc-ir}/events"
AFTER=""
BEFORE=""
MONTHS=3
JQ_FILTER="."

while [[ $# -gt 0 ]]; do
  case "$1" in
    --after)  AFTER="$2"; shift 2 ;;
    --before) BEFORE="$2"; shift 2 ;;
    --months) MONTHS="$2"; shift 2 ;;
    --jq)     JQ_FILTER="$2"; shift 2 ;;
    *)        echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

# Determine which monthly files to search
files=()
if [[ -n "$AFTER" || -n "$BEFORE" ]]; then
  # Date range mode: find files whose month overlaps the range
  for f in "$EVENTS_DIR"/*-events.jsonl; do
    [[ -f "$f" ]] || continue
    month=$(basename "$f" | grep -oE '^[0-9]{4}-[0-9]{2}')
    [[ -z "$month" ]] && continue
    month_start="${month}-01"
    # Crude overlap check
    if [[ -n "$BEFORE" && "$month_start" > "$BEFORE" ]]; then continue; fi
    if [[ -n "$AFTER" ]]; then
      # Month end is approximately month_start + 31 days
      month_end="${month}-31"
      [[ "$month_end" < "$AFTER" ]] && continue
    fi
    files+=("$f")
  done
else
  # Last N months mode
  for i in $(seq 0 $((MONTHS - 1))); do
    month=$(date -d "-${i} months" +%Y-%m 2>/dev/null || date -v-${i}m +%Y-%m 2>/dev/null)
    f="$EVENTS_DIR/${month}-events.jsonl"
    [[ -f "$f" ]] && files+=("$f")
  done
fi

if [[ ${#files[@]} -eq 0 ]]; then
  echo "[]"
  exit 0
fi

# Concatenate and apply date filters + jq
cat "${files[@]}" | jq -c "$JQ_FILTER" 2>/dev/null | \
  if [[ -n "$AFTER" ]]; then
    jq -c --arg after "$AFTER" 'select(.published_at >= $after)'
  else
    cat
  fi | \
  if [[ -n "$BEFORE" ]]; then
    jq -c --arg before "$BEFORE" 'select(.published_at <= $before)'
  else
    cat
  fi
```

### M4.5.4: Migration for existing events.jsonl

**One-time migration** (added to `/opc-ir-calibrate` first-run or as a standalone step):

```bash
# If events.jsonl exists and is not a symlink, split it into monthly files
EVENTS_FILE="$EVENTS_DIR/events.jsonl"
if [[ -f "$EVENTS_FILE" && ! -L "$EVENTS_FILE" ]]; then
  # Split by published_at month
  while IFS= read -r line; do
    month=$(echo "$line" | jq -r '.published_at[0:7]' 2>/dev/null) || continue
    [[ -z "$month" || "$month" == "null" ]] && continue
    echo "$line" >> "$EVENTS_DIR/${month}-events.jsonl"
  done < "$EVENTS_FILE"

  # Replace with symlink to current month
  CURRENT_MONTH=$(date +%Y-%m)
  touch "$EVENTS_DIR/${CURRENT_MONTH}-events.jsonl"
  mv "$EVENTS_FILE" "$EVENTS_FILE.bak"
  ln -sf "${CURRENT_MONTH}-events.jsonl" "$EVENTS_FILE"
fi
```

### M4.5.5: Update callers

All scripts that previously read `events.jsonl` directly must be updated:

| Caller | Change |
|---|---|
| `bin/fetch-rss.sh` | Write to monthly file via symlink (M4.5.2) |
| `agents/triage-classifier.md` | Reads via symlink (no change needed — symlink is transparent) |
| `ground-truth-linker.sh` | Uses `events-grep.sh --after $PRED_DATE --before $TARGET_DATE` for event gathering |
| `verdict-judge` (calibration mode) | Uses `events-grep.sh` for `events_since` input |
| Dedup in `fetch-rss.sh` | Reads last 500 lines from symlink (covers current month; cross-month dedup not critical) |

### M4.5 Exit Criteria

1. After running for 2+ months, `events/` contains separate monthly files.
2. `events.jsonl` symlink points to current month's file.
3. `events-grep.sh --months 2` returns events from both months.
4. `events-grep.sh --after 2026-04-15 --before 2026-05-15` correctly spans two monthly files.
5. One-time migration splits a pre-existing monolithic `events.jsonl` without data loss.

---

## `/opc-ir-calibrate` Command Integration

**File**: `commands/opc-ir-calibrate.md`

This is the orchestrating command that ties M4.1–M4.4 together in a single daily run.

```markdown
---
description: "Daily calibration: align predictions to ground truth, update role weights"
---

# /opc-ir-calibrate

Run the calibration loop. Safe to run anytime; idempotent on already-linked records.

## Execution Steps

### Step 1: Price Truth + Ground Truth Linking
Run `bin/ground-truth-linker.sh`. This:
- Scans forecast.jsonl and verdicts.jsonl for matured predictions
- Fetches prices via `bin/fetch-prices.sh` (multi-source fallback)
- Checks human-overrides.jsonl for manual truth entries
- Appends linked records to `calibration/predictions-vs-truth.jsonl`

### Step 2: Event Truth (Verdict Falsifier Evaluation)
For each matured verdict not yet event-judged:
- Gather relevant events via `bin/events-grep.sh`
- Dispatch `verdict-judge` with `mode: calibration`
- If falsifier triggered (confidence >= 0.7), override price truth with event truth

### Step 3: Posterior Weight Calculation
Follow `pipeline/calibration-protocol.md`:
- Compute per-role Brier scores
- Apply N≥30 floor
- Calculate posteriors: clamp(prior_brier / role_brier, 0.5, 1.5)
- Run anomaly rejection checks
- If pass: write `calibration/role-weights.yaml`
- If reject: retain previous weights, log warning

### Step 4: Regime Detection
For roles with N≥30:
- Compute 30-day rolling Brier
- If deterioration > 1.5× historical: reset posterior to 1.0
- Record regime_reset event
- Inject warning into role-weights.yaml metadata

### Step 5: Status Report
Output summary to stdout:
- Records linked this run
- Per-role N counts and Brier scores
- Roles approaching N=30 threshold
- Anomaly rejections (if any)
- Regime warnings (if any)

## Flags

- `--dry-run`: compute everything but do not write role-weights.yaml
- `--force`: bypass N≥30 floor (for testing only; writes warning in metadata)
- `--verbose`: include per-record detail in status output
```

---

## `human-overrides.jsonl` Format

For users who want to manually override ground truth:

```json
{
  "run_id": "forecast-2026-05-01T08:00:00Z",
  "asset": "NDX",
  "horizon": "1w",
  "truth_bucket": "strong_up",
  "reason": "NDX rallied 8% on surprise Fed pivot, price data lagged",
  "overridden_at": "2026-05-10T12:00:00Z"
}
```

Priority: human overrides are checked first in ground-truth-linker.sh (already implemented in M4.1.2).

---

## Testing Strategy

### Unit tests (shell-level)

| Test | Method |
|---|---|
| fetch-prices.sh source fallback | Mock curl responses; verify fallback order |
| bucket_from_pct edge cases | -5.0 → down (boundary), -5.01 → strong_down |
| ground-truth-linker dedup | Run twice with same data → 0 new records second time |
| Brier score math | Known inputs → known output (hand-calculated) |
| Anomaly rejection | All-1.0 posteriors → rejected; single NaN → rejected |
| Regime detection threshold | Inject deteriorating role → reset fires |

### Integration tests

| Test | Method |
|---|---|
| Full calibrate pipeline | Seed forecast.jsonl with 35 predictions (matured), run calibrate, verify role-weights.yaml written with non-trivial posteriors |
| Cold-start behavior | Seed with 20 predictions → verify all posteriors remain 1.0 |
| Event truth override | Seed verdict with falsifier + events that trigger it → verify event truth wins over price |
| Monthly rolling | Write events across 2 months → verify grep returns both |

### Synthetic data fixtures

Create `test/fixtures/calibration/`:
- `forecast-35-samples.jsonl` — 35 matured forecast rows with known distributions
- `verdicts-with-falsifiers.jsonl` — 5 verdicts with explicit falsifiers
- `events-triggering-falsifier.jsonl` — events that should trigger one falsifier
- `human-overrides-sample.jsonl` — 2 override entries
- `expected-role-weights.yaml` — hand-calculated expected output

---

## Risk Mitigations Addressed

| Risk | Mitigation in Phase 4 |
|---|---|
| D3 (yfinance latency/errors CN) | Multi-source fallback in fetch-prices.sh; missing prices skip sample |
| D4 (events.jsonl unbounded) | Monthly rolling (M4.5) |
| M1 (5-tier tail loss) | Brier score captures calibration quality within the 5-tier system; bucket thresholds documented for future revision |
| M2 (N≥30 cold-start) | Status shows accumulator progress; posteriors degenerate to 1.0 |
| M3 (weight collapse) | Posterior clamp [0.5, 1.5] + anomaly rejection |
| P2 (regime change over-trust) | Full regime detection with 30-day rolling Brier + digest warning |
| P4 (manual weight edit) | Runtime weights in calibration/ separate from defaults/; status shows provenance |

---

## Phase 4 Exit Criteria (aggregate)

1. `/opc-ir-calibrate` runs end-to-end on synthetic data and produces valid `role-weights.yaml`.
2. Price truth fetching works for all 14 watch-assets with at least one source.
3. Event truth correctly overrides price truth when falsifiers are triggered.
4. N<30 roles maintain posterior=1.0; N≥30 roles get differentiated posteriors.
5. Anomaly rejection prevents writing degenerate weights.
6. Regime detection fires on synthetic deterioration data and resets posteriors.
7. Digest warning renders correctly for regime-detected roles.
8. events.jsonl monthly rolling works with backward-compatible cross-month queries.
9. Re-running calibrate is idempotent (no duplicate records, same weights if no new data).
10. `--dry-run` flag computes without writing weights.
