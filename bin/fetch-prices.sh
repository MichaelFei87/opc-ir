#!/usr/bin/env bash
set -euo pipefail

# fetch-prices.sh — Fetch historical close prices for OPC-IR calibration.
# Usage: fetch-prices.sh <asset> <date-YYYY-MM-DD>
# Output: JSON to stdout: {"asset":"NDX","date":"2026-05-08","close":18542.30,"source":"yahoo"}
# Exit 0 = success, Exit 1 = all sources failed.

ASSET="${1:?Usage: fetch-prices.sh <asset> <date>}"
DATE="${2:?Usage: fetch-prices.sh <asset> <date>}"
LOG_DIR="${OPC_IR_HOME:-$HOME/.opc-ir}/logs"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).log"
mkdir -p "$LOG_DIR"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] fetch-prices: $*" >> "$LOG_FILE"; }

# Use python for ticker mapping (macOS bash 3.x compatible — no associative arrays)
RESULT=$(ASSET="$ASSET" DATE="$DATE" python3 << 'PYEOF'
import json, os, sys, urllib.request

asset = os.environ["ASSET"]
date = os.environ["DATE"]

# Ticker maps per source
YAHOO_MAP = {
    "NDX": "^NDX", "SPX": "^GSPC", "RUT": "^RUT", "VIX": "^VIX",
    "HSI": "^HSI", "HSCEI": "^HSCE", "CSI300": "000300.SS",
    "DXY": "DX-Y.NYB", "CNH": "CNH=X", "USDCNY": "USDCNY=X",
    "GLD": "GC=F", "ZB": "ZB=F", "WTI": "CL=F", "BTC": "BTC-USD"
}

def fetch_yahoo():
    ticker = YAHOO_MAP.get(asset)
    if not ticker: return None
    from datetime import datetime, timezone
    try:
        dt = datetime.strptime(date, "%Y-%m-%d").replace(tzinfo=timezone.utc)
        p1 = int(dt.timestamp())
        p2 = p1 + 86400
    except Exception: return None

    url = f"https://query1.finance.yahoo.com/v8/finance/chart/{ticker}?period1={p1}&period2={p2}&interval=1d"
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read())
        close = data["chart"]["result"][0]["indicators"]["quote"][0]["close"][0]
        if close is None: return None
        return {"asset": asset, "date": date, "close": round(close, 2), "source": "yahoo"}
    except Exception:
        return None

# Try sources in priority order
for fetcher in [fetch_yahoo]:
    result = fetcher()
    if result:
        print(json.dumps(result))
        sys.exit(0)

sys.exit(1)
PYEOF
) || {
  log "ALL_FAILED: $ASSET $DATE"
  exit 1
}

log "OK: $ASSET $DATE"
echo "$RESULT"
