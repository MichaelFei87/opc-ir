#!/usr/bin/env bash
set -euo pipefail

# fetch-earnings.sh — Fetch latest quarterly earnings for watcher assets via yfinance
# Usage: fetch-earnings.sh [SYMBOL] [--home <path>] [--assets <path>]
#   If SYMBOL given, fetch only that symbol. Otherwise fetch all equity-single assets.
# Output: writes per-quarter JSON to ~/.opc-ir/market-data/earnings/{SYMBOL}-{YYYY}Q{N}.json
# Exit 0 = success, Exit 1 = total failure.

OPC_IR_HOME="${OPC_IR_HOME:-$HOME/.opc-ir}"
ASSETS_FILE=""
TARGET_SYMBOL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --home)   OPC_IR_HOME="$2"; shift 2 ;;
    --assets) ASSETS_FILE="$2"; shift 2 ;;
    -*)       echo "Unknown option: $1" >&2; exit 1 ;;
    *)        TARGET_SYMBOL="$1"; shift ;;
  esac
done

EARNINGS_DIR="$OPC_IR_HOME/market-data/earnings"
LOG_DIR="$OPC_IR_HOME/logs"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).log"
mkdir -p "$EARNINGS_DIR" "$LOG_DIR"

log_msg() {
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "[$ts] fetch-earnings: $1" >> "$LOG_FILE"
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

# Check yfinance
if ! python3 -c "import yfinance" 2>/dev/null; then
  log_msg "ERROR: yfinance not installed. Run: pip3 install yfinance"
  echo "ERROR: yfinance not installed. Run: pip3 install yfinance" >&2
  exit 1
fi

log_msg "Starting earnings fetch${TARGET_SYMBOL:+ for $TARGET_SYMBOL}"

RESULT=$(ASSETS_FILE="$ASSETS_FILE" EARNINGS_DIR="$EARNINGS_DIR" \
  TARGET_SYMBOL="${TARGET_SYMBOL:-}" python3 << 'PYEOF' 2>>"$LOG_FILE"
import json, math, os, sys, re, tempfile, warnings
from datetime import datetime, timezone

warnings.filterwarnings("ignore", category=FutureWarning)
import pandas as pd
import yfinance as yf

assets_file = os.environ["ASSETS_FILE"]
earnings_dir = os.environ["EARNINGS_DIR"]
target_symbol = os.environ.get("TARGET_SYMBOL", "")

def parse_equity_singles(path):
    """Parse watch-assets.yaml, return only equity-single symbols."""
    symbols = []
    current_sym = None
    current_cls = None
    with open(path) as f:
        for raw_line in f:
            line = raw_line.rstrip()
            stripped = line.strip()
            if not stripped or stripped.startswith('#'):
                continue
            m = re.match(r'^\s*-\s+symbol:\s*(.+)', line)
            if m:
                if current_sym and current_cls == 'equity-single':
                    symbols.append(current_sym)
                current_sym = m.group(1).strip().strip('"').strip("'")
                current_cls = None
                continue
            fm = re.match(r'^\s+class:\s*(.+)', line)
            if fm and current_sym:
                current_cls = fm.group(1).strip().strip('"').strip("'")
    if current_sym and current_cls == 'equity-single':
        symbols.append(current_sym)
    return symbols

def atomic_write_json(path, data):
    dir_name = os.path.dirname(path)
    fd, tmp_path = tempfile.mkstemp(dir=dir_name, suffix='.tmp')
    try:
        with os.fdopen(fd, 'w') as f:
            json.dump(data, f, indent=2)
        os.rename(tmp_path, path)
    except Exception:
        try: os.remove(tmp_path)
        except OSError: pass
        raise

# Determine symbols to fetch
if target_symbol:
    symbols = [target_symbol]
else:
    symbols = parse_equity_singles(assets_file)

if not symbols:
    print(json.dumps({"fetched": 0, "skipped": 0, "failed": 0}))
    sys.exit(0)

fetched = 0
skipped = 0
failed = 0

MAX_RETRIES = 2

def _safe_float(val):
    """Return float if val is a real number, else None."""
    if val is None or (isinstance(val, float) and math.isnan(val)):
        return None
    try:
        f = float(val)
        return None if math.isnan(f) else f
    except (ValueError, TypeError):
        return None

def _fiscal_quarter_label(qfin, latest_date):
    """Derive quarter label from quarterly_financials column dates (fiscal period end).
    Falls back to earnings announcement date if financials unavailable."""
    if qfin is not None and not qfin.empty:
        # Columns are fiscal period-end dates, sorted descending
        fiscal_date = qfin.columns[0]
        if hasattr(fiscal_date, 'month'):
            q = (fiscal_date.month - 1) // 3 + 1
            return f"{fiscal_date.year}Q{q}", fiscal_date
    # Fallback: use announcement date (less accurate)
    q = (latest_date.month - 1) // 3 + 1
    return f"{latest_date.year}Q{q}", latest_date

def _find_yoy_revenue(rev_series, latest_fiscal_date):
    """Find revenue from the same quarter one year ago by matching dates,
    not positional index. Falls back to closest match within 30 days."""
    if latest_fiscal_date is None or not hasattr(latest_fiscal_date, 'year'):
        return None
    target_year = latest_fiscal_date.year - 1
    target_month = latest_fiscal_date.month
    target_day = latest_fiscal_date.day
    # Try exact year-ago match
    for col_date, val in rev_series.items():
        v = _safe_float(val)
        if v is None:
            continue
        if hasattr(col_date, 'year') and col_date.year == target_year and col_date.month == target_month:
            return v
    return None

for sym in symbols:
    retries_left = MAX_RETRIES
    while True:
        try:
            ticker = yf.Ticker(sym)

            # Get earnings dates to find latest quarter
            try:
                edates = ticker.earnings_dates
                if edates is None or edates.empty:
                    print(f"SKIP: {sym}: no earnings history (IPO/ETF?)", file=sys.stderr)
                    skipped += 1
                    break
                # Find most recent past earnings date
                now = datetime.now(timezone.utc)
                past_dates = [d for d in edates.index if d.to_pydatetime().replace(tzinfo=timezone.utc) <= now]
                if not past_dates:
                    print(f"SKIP: {sym}: no past earnings dates (recent IPO?)", file=sys.stderr)
                    skipped += 1
                    break
                latest_date = max(past_dates)
            except Exception as e:
                print(f"WARN: {sym}: earnings_dates failed: {e}", file=sys.stderr)
                if retries_left > 0:
                    retries_left -= 1
                    import time; time.sleep(2 ** (MAX_RETRIES - retries_left))
                    continue
                failed += 1
                break

            # Fetch quarterly financials (needed for fiscal quarter label + revenue)
            qfin = None
            try:
                qfin = ticker.quarterly_financials
            except Exception as e:
                print(f"WARN: {sym}: quarterly_financials failed: {e}", file=sys.stderr)

            quarter_label, fiscal_date = _fiscal_quarter_label(qfin, latest_date)

            # Skip if already exists
            out_path = os.path.join(earnings_dir, f"{sym}-{quarter_label}.json")
            if os.path.exists(out_path):
                print(f"SKIP: {sym} {quarter_label} already exists", file=sys.stderr)
                skipped += 1
                break

            earnings_data = {
                "symbol": sym,
                "quarter": quarter_label,
                "earnings_date": latest_date.strftime('%Y-%m-%d'),
                "fetched_at": datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
            }

            # EPS from earnings_dates table — handle duplicate rows
            try:
                row = edates.loc[latest_date]
                # If duplicate rows, take the first one
                if isinstance(row, pd.DataFrame):
                    row = row.iloc[0]
                row_dict = row.to_dict() if hasattr(row, 'to_dict') else {}
                eps_est = _safe_float(row_dict.get('EPS Estimate'))
                eps_actual = _safe_float(row_dict.get('Reported EPS'))
                if eps_actual is not None:
                    earnings_data['eps'] = round(eps_actual, 2)
                if eps_est is not None:
                    earnings_data['eps_estimate'] = round(eps_est, 2)
                if earnings_data.get('eps') is not None and earnings_data.get('eps_estimate') is not None:
                    if earnings_data['eps'] > earnings_data['eps_estimate']:
                        earnings_data['eps_surprise'] = 'beat'
                    elif earnings_data['eps'] < earnings_data['eps_estimate']:
                        earnings_data['eps_surprise'] = 'miss'
                    else:
                        earnings_data['eps_surprise'] = 'inline'
            except Exception as e:
                print(f"WARN: {sym}: EPS parsing failed: {e}", file=sys.stderr)

            # Revenue from quarterly financials — match by date for YoY
            try:
                if qfin is not None and not qfin.empty and 'Total Revenue' in qfin.index:
                    rev_series = qfin.loc['Total Revenue'].dropna()
                    if len(rev_series) >= 1:
                        latest_rev = _safe_float(rev_series.iloc[0])
                        if latest_rev is not None:
                            earnings_data['revenue'] = latest_rev
                            if latest_rev >= 1e9:
                                earnings_data['revenue_formatted'] = f"{latest_rev/1e9:.1f}B"
                            elif latest_rev >= 1e6:
                                earnings_data['revenue_formatted'] = f"{latest_rev/1e6:.1f}M"
                            # YoY: match by date, not positional index
                            yoy_rev = _find_yoy_revenue(rev_series, fiscal_date)
                            if yoy_rev is not None and yoy_rev > 0:
                                yoy_pct = (latest_rev - yoy_rev) / yoy_rev * 100
                                earnings_data['revenue_yoy'] = f"{yoy_pct:+.1f}%"
            except Exception as e:
                print(f"WARN: {sym}: revenue parsing failed: {e}", file=sys.stderr)

            # Note: LLM summary + guidance added by corp-fundamentals-watcher during evolve
            earnings_data['summary'] = None

            atomic_write_json(out_path, earnings_data)
            fetched += 1
            print(f"OK: {sym} {quarter_label}", file=sys.stderr)
            break

        except Exception as e:
            if retries_left > 0:
                retries_left -= 1
                import time; time.sleep(2 ** (MAX_RETRIES - retries_left))
                continue
            print(f"WARN: {sym} failed after retries: {e}", file=sys.stderr)
            failed += 1
            break

print(json.dumps({"fetched": fetched, "skipped": skipped, "failed": failed}))
PYEOF
) || {
  log_msg "FATAL: Python earnings fetcher crashed"
  exit 1
}

log_msg "Earnings fetch complete: $RESULT"
echo "$RESULT"
exit 0
