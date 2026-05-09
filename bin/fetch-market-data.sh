#!/usr/bin/env bash
set -euo pipefail

# fetch-market-data.sh — Fetch macro + watcher asset prices via yfinance
# Usage: fetch-market-data.sh [--home <path>] [--assets <path>]
# Output: writes macro-snapshot.json + watcher-snapshot.json to ~/.opc-ir/market-data/
# Exit 0 = success (partial failures logged), Exit 1 = total failure.

OPC_IR_HOME="${OPC_IR_HOME:-$HOME/.opc-ir}"
ASSETS_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --home)   OPC_IR_HOME="$2"; shift 2 ;;
    --assets) ASSETS_FILE="$2"; shift 2 ;;
    *)        echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

MARKET_DIR="$OPC_IR_HOME/market-data"
HISTORY_DIR="$MARKET_DIR/history"
LOG_DIR="$OPC_IR_HOME/logs"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).log"
mkdir -p "$MARKET_DIR" "$HISTORY_DIR" "$LOG_DIR"

log_msg() {
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "[$ts] fetch-market-data: $1" >> "$LOG_FILE"
}

# Resolve assets file
if [[ -z "$ASSETS_FILE" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  ASSETS_FILE="$SCRIPT_DIR/defaults/watch-assets.yaml"
fi

if [[ ! -f "$ASSETS_FILE" ]]; then
  log_msg "ERROR: assets file not found: $ASSETS_FILE"
  exit 1
fi

# Check yfinance availability
if ! python3 -c "import yfinance" 2>/dev/null; then
  log_msg "ERROR: yfinance not installed. Run: pip3 install yfinance"
  echo "ERROR: yfinance not installed. Run: pip3 install yfinance" >&2
  exit 1
fi

log_msg "Starting market data fetch"

# Run the Python fetcher — stderr goes to log
RESULT=$(ASSETS_FILE="$ASSETS_FILE" MARKET_DIR="$MARKET_DIR" HISTORY_DIR="$HISTORY_DIR" python3 << 'PYEOF' 2>>"$LOG_FILE"
import json, os, sys, re, tempfile, warnings
from datetime import datetime, timezone, timedelta

warnings.filterwarnings("ignore", category=FutureWarning)

import yfinance as yf

assets_file = os.environ["ASSETS_FILE"]
market_dir = os.environ["MARKET_DIR"]
history_dir = os.environ["HISTORY_DIR"]

# ── YAML parser (anchored regex, not substring) ──

def parse_assets_yaml(path):
    """Parse watch-assets.yaml using anchored regex matching."""
    assets = []
    current = {}
    with open(path) as f:
        for raw_line in f:
            line = raw_line.rstrip()
            stripped = line.strip()
            if not stripped or stripped.startswith('#'):
                continue
            # New asset item
            m = re.match(r'^\s*-\s+symbol:\s*(.+)', line)
            if m:
                if current:
                    assets.append(current)
                val = m.group(1).strip().strip('"').strip("'")
                current = {'symbol': val}
                continue
            if not current:
                continue
            # Field within current asset
            for field in ('name', 'class', 'region', 'ticker', 'proxy_for'):
                fm = re.match(rf'^\s+{field}:\s*(.+)', line)
                if fm:
                    current[field] = fm.group(1).strip().strip('"').strip("'")
                    break
    if current:
        assets.append(current)
    return assets

assets = parse_assets_yaml(assets_file)

# ── Ticker mapping (from YAML `ticker` field, fallback to symbol) ──

YFINANCE_MAP = {a['symbol']: a.get('ticker', a['symbol']) for a in assets}

YIELD_ASSETS = {"US3M", "US2Y", "US5Y", "US10Y", "US30Y"}
TREND_THRESHOLD = 0.02  # 2% for most assets

def classify_trend(current, past):
    if past is None or past == 0 or current is None:
        return "unknown"
    pct = (current - past) / abs(past)
    if pct > TREND_THRESHOLD:
        return "up"
    elif pct < -TREND_THRESHOLD:
        return "down"
    return "sideways"

def atomic_write_json(path, data):
    """Write JSON atomically via temp file + rename."""
    dir_name = os.path.dirname(path)
    fd, tmp_path = tempfile.mkstemp(dir=dir_name, suffix='.tmp')
    try:
        with os.fdopen(fd, 'w') as f:
            json.dump(data, f, indent=2)
        os.rename(tmp_path, path)
    except Exception:
        try:
            os.remove(tmp_path)
        except OSError:
            pass
        raise

def extract_closes(hist):
    """Extract close prices from a yfinance history DataFrame."""
    if hist is None or hist.empty:
        return None
    closes = hist['Close'].dropna()
    return closes if len(closes) > 0 else None

def compute_trends_and_change(closes):
    """Compute trend_1w, trend_1m, trend_3m, change_1d from close series."""
    current = round(float(closes.iloc[-1]), 4)
    result = {"current": current}

    # 1-day change
    if len(closes) >= 2:
        prev = float(closes.iloc[-2])
        if prev != 0:
            pct = (current - prev) / abs(prev) * 100
            result["change_1d_pct"] = f"{pct:+.1f}%"
            result["change_1d_bp"] = f"{(current - prev) * 100:+.0f}bp"
    else:
        result["change_1d_pct"] = "N/A"
        result["change_1d_bp"] = "N/A"

    # Trends
    result["trend_1w"] = classify_trend(current, float(closes.iloc[-5])) if len(closes) >= 5 else "unknown"
    result["trend_1m"] = classify_trend(current, float(closes.iloc[-22])) if len(closes) >= 22 else "unknown"
    result["trend_3m"] = classify_trend(current, float(closes.iloc[-63])) if len(closes) >= 63 else "unknown"

    # Range
    result["high"] = round(float(closes.max()), 4)
    result["low"] = round(float(closes.min()), 4)

    # Sparkline
    result["sparkline"] = [round(float(v), 2) for v in closes.iloc[::5].tolist()][-12:]

    return result

# ── Classify symbols ──

now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
macro_symbols = []
watcher_symbols = []
options_proxies = []

for a in assets:
    sym = a['symbol']
    cls = a.get('class', '')
    if cls == 'equity-single':
        watcher_symbols.append(sym)
    elif cls == 'options-proxy':
        options_proxies.append(a)
    else:
        macro_symbols.append(sym)

# ── Batch fetch macro data (yf.download) with timeout + retry ──

macro_instruments = {}
success_count = 0
fail_count = 0

macro_tickers = [YFINANCE_MAP.get(s, s) for s in macro_symbols]
macro_ticker_to_sym = {}
for s in macro_symbols:
    macro_ticker_to_sym[YFINANCE_MAP.get(s, s)] = s

MAX_RETRIES = 2
for attempt in range(MAX_RETRIES + 1):
    try:
        batch_data = yf.download(
            macro_tickers,
            period="3mo",
            group_by="ticker",
            timeout=15,
            progress=False,
        )
        break
    except Exception as e:
        if attempt < MAX_RETRIES:
            import time
            wait = 2 ** attempt
            print(f"WARN: batch fetch attempt {attempt+1} failed: {e}, retrying in {wait}s", file=sys.stderr)
            time.sleep(wait)
        else:
            print(f"ERROR: batch fetch failed after {MAX_RETRIES+1} attempts: {e}", file=sys.stderr)
            batch_data = None

if batch_data is not None and not batch_data.empty:
    for yf_ticker, sym in macro_ticker_to_sym.items():
        try:
            # For single ticker download, structure differs
            if len(macro_tickers) == 1:
                ticker_data = batch_data
            else:
                ticker_data = batch_data[yf_ticker] if yf_ticker in batch_data.columns.get_level_values(0) else None

            if ticker_data is None or ticker_data.empty:
                print(f"WARN: {sym} ({yf_ticker}): no data in batch", file=sys.stderr)
                fail_count += 1
                continue

            closes = extract_closes(ticker_data.to_frame('Close') if 'Close' not in ticker_data.columns else ticker_data)
            if closes is None:
                fail_count += 1
                continue

            info = compute_trends_and_change(closes)

            if sym in YIELD_ASSETS:
                macro_instruments[sym] = {
                    "yield": info["current"],
                    "change_1d": info["change_1d_bp"],
                    "trend_1m": info["trend_1m"],
                    "high_60d": info["high"],
                    "low_60d": info["low"],
                }
            else:
                macro_instruments[sym] = {
                    "price": info["current"],
                    "change_1d_pct": info["change_1d_pct"],
                    "trend_1w": info["trend_1w"],
                    "trend_1m": info["trend_1m"],
                    "high_60d": info["high"],
                    "low_60d": info["low"],
                    "sparkline_60d": info["sparkline"],
                }
            success_count += 1
            print(f"OK: {sym} ({yf_ticker})", file=sys.stderr)
        except Exception as e:
            print(f"WARN: {sym} ({yf_ticker}) parse failed: {e}", file=sys.stderr)
            fail_count += 1
else:
    print("WARN: batch fetch returned no data, all macro tickers failed", file=sys.stderr)
    fail_count += len(macro_symbols)

# ── 2s10s spread (conventional: 10Y - 2Y) ──

us2y = macro_instruments.get("US2Y", {}).get("yield")
us10y = macro_instruments.get("US10Y", {}).get("yield")
if us2y is not None and us10y is not None:
    spread = round(us10y - us2y, 4)  # conventional: positive = normal curve
    t2y = macro_instruments.get("US2Y", {}).get("trend_1m", "unknown")
    t10y = macro_instruments.get("US10Y", {}).get("trend_1m", "unknown")
    # If 10Y falling faster than 2Y, spread narrows; if 10Y rising faster, widens
    if t10y == "down" and t2y != "down":
        spread_trend = "narrowing"
    elif t10y == "up" and t2y != "up":
        spread_trend = "widening"
    elif t10y == "down" and t2y == "down":
        spread_trend = "stable"
    elif t10y == "up" and t2y == "up":
        spread_trend = "stable"
    else:
        spread_trend = "stable"
    macro_instruments["2s10s_spread"] = {
        "value": spread,
        "trend_1m": spread_trend,
    }

# ── Fetch watcher assets (batch 1y) ──

watcher_assets = {}

if watcher_symbols:
    watcher_tickers = [YFINANCE_MAP.get(s, s) for s in watcher_symbols]
    watcher_ticker_to_sym = {YFINANCE_MAP.get(s, s): s for s in watcher_symbols}

    for attempt in range(MAX_RETRIES + 1):
        try:
            watcher_batch = yf.download(
                watcher_tickers,
                period="1y",
                group_by="ticker",
                timeout=15,
                progress=False,
            )
            break
        except Exception as e:
            if attempt < MAX_RETRIES:
                import time
                time.sleep(2 ** attempt)
            else:
                watcher_batch = None

    if watcher_batch is not None and not watcher_batch.empty:
        for yf_ticker, sym in watcher_ticker_to_sym.items():
            try:
                if len(watcher_tickers) == 1:
                    ticker_data = watcher_batch
                else:
                    ticker_data = watcher_batch[yf_ticker] if yf_ticker in watcher_batch.columns.get_level_values(0) else None

                if ticker_data is None or ticker_data.empty:
                    fail_count += 1
                    continue

                closes = extract_closes(ticker_data.to_frame('Close') if 'Close' not in ticker_data.columns else ticker_data)
                if closes is None:
                    fail_count += 1
                    continue

                info = compute_trends_and_change(closes)

                watcher_assets[sym] = {
                    "price": info["current"],
                    "change_1d_pct": info["change_1d_pct"],
                    "high_52w": info["high"],
                    "low_52w": info["low"],
                    "trend_3m": info["trend_3m"],
                    "trend_1m": info["trend_1m"],
                }
                success_count += 1
                print(f"OK: watcher {sym}", file=sys.stderr)
            except Exception as e:
                print(f"WARN: watcher {sym} failed: {e}", file=sys.stderr)
                fail_count += 1

# ── Fetch options sentiment for options-proxy assets ──

options_sentiment = {}

for proxy in options_proxies:
    sym = proxy['symbol']           # SPY, QQQ
    proxy_for = proxy.get('proxy_for', sym)  # SPX, NDX
    try:
        ticker = yf.Ticker(sym)
        expirations = ticker.options
        if not expirations:
            print(f"WARN: {sym} options: no expirations", file=sys.stderr)
            fail_count += 1
            continue

        total_call_vol = total_put_vol = 0
        total_call_oi = total_put_oi = 0
        total_call_notional = total_put_notional = 0.0
        exps_used = 0

        for exp in expirations[:8]:
            try:
                chain = ticker.option_chain(exp)
                cv = chain.calls['volume'].sum()
                pv = chain.puts['volume'].sum()
                total_call_vol += int(cv)
                total_put_vol += int(pv)
                total_call_oi += int(chain.calls['openInterest'].sum())
                total_put_oi += int(chain.puts['openInterest'].sum())
                total_call_notional += float((chain.calls['volume'] * chain.calls['lastPrice'] * 100).sum())
                total_put_notional += float((chain.puts['volume'] * chain.puts['lastPrice'] * 100).sum())
                exps_used += 1
            except Exception as e:
                print(f"WARN: {sym} options exp {exp}: {e}", file=sys.stderr)

        if exps_used > 0:
            pc_ratio = round(total_put_notional / total_call_notional, 2) if total_call_notional > 0 else None
            options_sentiment[proxy_for] = {
                "proxy": sym,
                "expirations_sampled": exps_used,
                "call_volume": total_call_vol,
                "put_volume": total_put_vol,
                "call_open_interest": total_call_oi,
                "put_open_interest": total_put_oi,
                "call_notional_usd": round(total_call_notional),
                "put_notional_usd": round(total_put_notional),
                "put_call_ratio": pc_ratio,
            }
            success_count += 1
            print(f"OK: options {sym} (proxy for {proxy_for}), {exps_used} exps", file=sys.stderr)
        else:
            fail_count += 1
    except Exception as e:
        print(f"WARN: {sym} options failed: {e}", file=sys.stderr)
        fail_count += 1

# ── Write outputs atomically ──

macro_snapshot = {
    "fetched_at": now,
    "instruments": macro_instruments,
    "_stats": {"success": success_count, "failed": fail_count},
}

watcher_snapshot = {
    "fetched_at": now,
    "assets": watcher_assets,
}

atomic_write_json(os.path.join(market_dir, "macro-snapshot.json"), macro_snapshot)
atomic_write_json(os.path.join(market_dir, "watcher-snapshot.json"), watcher_snapshot)

if options_sentiment:
    options_snapshot = {
        "fetched_at": now,
        "sentiment": options_sentiment,
    }
    atomic_write_json(os.path.join(market_dir, "options-snapshot.json"), options_snapshot)

# Daily archive
today = datetime.now(timezone.utc).strftime('%Y-%m-%d')
atomic_write_json(os.path.join(history_dir, f"{today}-macro.json"), macro_snapshot)

# Clean old archives (>90 days)
cutoff = datetime.now(timezone.utc) - timedelta(days=90)
for fname in os.listdir(history_dir):
    if fname.endswith('-macro.json'):
        try:
            date_str = fname[:10]
            fdate = datetime.strptime(date_str, '%Y-%m-%d').replace(tzinfo=timezone.utc)
            if fdate < cutoff:
                os.remove(os.path.join(history_dir, fname))
                print(f"CLEANUP: removed old archive {fname}", file=sys.stderr)
        except Exception as e:
            print(f"WARN: cleanup failed for {fname}: {e}", file=sys.stderr)

print(json.dumps({"success": success_count, "failed": fail_count}))
PYEOF
) || {
  log_msg "FATAL: Python fetcher crashed"
  exit 1
}

log_msg "Fetch complete: $RESULT"
echo "$RESULT"
exit 0
