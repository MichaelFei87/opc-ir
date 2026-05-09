#!/usr/bin/env bash
set -euo pipefail

# invalidator-lint.sh — Check invalidator/falsifier specificity
# Usage: invalidator-lint.sh <text>
# Exit 0 = passes specificity check
# Exit 1 = too vague (missing numeric, temporal, or asset/event reference)
#
# Specificity requirements (M4 mitigation):
#   1. Contains at least one number (price level, percentage, count)
#   2. Contains at least one temporal reference (date, "by Q3", "within 30 days", etc.)
#   3. Contains at least one asset or event reference (ticker, "Fed", "CPI", etc.)

TEXT="${1:?Usage: invalidator-lint.sh <text-or-file>}"

# If argument is a file path, read contents
if [[ -f "$TEXT" ]]; then
  TEXT=$(cat "$TEXT")
fi

ERRORS=()

# Check 1: numeric reference
if ! echo "$TEXT" | grep -qE '[0-9]+(\.[0-9]+)?%?'; then
  ERRORS+=("Missing numeric reference (price level, percentage, or count)")
fi

# Check 2: temporal reference
TEMPORAL_PATTERN='(20[0-9]{2}|Q[1-4]|[Jj]an|[Ff]eb|[Mm]ar|[Aa]pr|[Mm]ay|[Jj]un|[Jj]ul|[Aa]ug|[Ss]ep|[Oo]ct|[Nn]ov|[Dd]ec|within [0-9]+ (day|week|month)|by (end of|mid-)|before |after |next [0-9]+ (day|week|month)|[0-9]+ (day|week|month)s?)'
if ! echo "$TEXT" | grep -qE "$TEMPORAL_PATTERN"; then
  ERRORS+=("Missing temporal reference (date, quarter, or timeframe)")
fi

# Check 3: asset or event reference
ASSET_PATTERN='(NDX|SPX|RUT|VIX|HSI|HSCEI|CSI300|DXY|CNH|USDCNY|GLD|ZB|WTI|BTC|NASDAQ|S&P|MSFT|NVDA|GOOGL|META|TSM|AAPL|AMZN|GOOG|AVGO|TSLA|COST|NFLX|Fed|ECB|PBOC|BOJ|CPI|GDP|NFP|PMI|ISM|FOMC|earnings|rate (cut|hike)|tariff|sanctions|oil|gold|dollar|yuan|bitcoin|treasury)'
if ! echo "$TEXT" | grep -qiE "$ASSET_PATTERN"; then
  ERRORS+=("Missing asset or event reference (ticker, institution, or macro indicator)")
fi

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "FAIL: Invalidator lacks specificity"
  for err in "${ERRORS[@]}"; do
    echo "  - $err"
  done
  echo ""
  echo "Invalidator text: $TEXT"
  echo ""
  echo "A valid invalidator must contain:"
  echo "  1. A numeric reference (e.g., 'drops below 4500', 'exceeds 5%')"
  echo "  2. A temporal reference (e.g., 'by Q3 2026', 'within 30 days')"
  echo "  3. An asset/event reference (e.g., 'SPX', 'Fed rate cut', 'CPI')"
  exit 1
fi

echo "PASS: Invalidator meets specificity requirements"
exit 0
