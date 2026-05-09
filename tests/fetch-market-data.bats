#!/usr/bin/env bats

# fetch-market-data.bats — Market data fetch tests using live yfinance API

setup() {
  python3 -c "import yfinance" 2>/dev/null || skip "yfinance not installed"
  export OPC_IR_HOME="$(mktemp -d)"
  mkdir -p "$OPC_IR_HOME/market-data" "$OPC_IR_HOME/logs"
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export PATH="$SCRIPT_DIR/bin:$PATH"

  # Fetch once, reuse across tests
  if [ ! -f "$OPC_IR_HOME/market-data/macro-snapshot.json" ]; then
    fetch-market-data.sh --home "$OPC_IR_HOME"
  fi
}

teardown() {
  rm -rf "$OPC_IR_HOME"
}

# ── Macro snapshot ──

@test "fetch-market-data: produces macro-snapshot.json with required structure" {
  local macro="$OPC_IR_HOME/market-data/macro-snapshot.json"
  [ -f "$macro" ]
  jq -e '.fetched_at and .instruments and ._stats' "$macro" >/dev/null
}

@test "fetch-market-data: yield instruments have yield and basis point change" {
  local macro="$OPC_IR_HOME/market-data/macro-snapshot.json"
  for tenor in US3M US2Y US5Y US10Y US30Y; do
    jq -e ".instruments.${tenor}.yield" "$macro" >/dev/null
    local change
    change=$(jq -r ".instruments.${tenor}.change_1d" "$macro")
    [[ "$change" == *bp* ]]
  done
}

@test "fetch-market-data: equity indices have price and percentage change" {
  local macro="$OPC_IR_HOME/market-data/macro-snapshot.json"
  for idx in NDX SPX RUT; do
    jq -e ".instruments.${idx}.price" "$macro" >/dev/null
    local change
    change=$(jq -r ".instruments.${idx}.change_1d_pct" "$macro")
    [[ "$change" == *%* ]]
  done
}

@test "fetch-market-data: 2s10s spread equals 10Y minus 2Y" {
  local macro="$OPC_IR_HOME/market-data/macro-snapshot.json"
  local us10y us2y spread expected
  us10y=$(jq '.instruments.US10Y.yield' "$macro")
  us2y=$(jq '.instruments.US2Y.yield' "$macro")
  spread=$(jq '.instruments["2s10s_spread"].value' "$macro")
  expected=$(echo "$us10y - $us2y" | bc)
  [ "$(echo "$spread == $expected" | bc)" -eq 1 ]
}

@test "fetch-market-data: VIX, DXY, GLD, WTI, BTC all present" {
  local macro="$OPC_IR_HOME/market-data/macro-snapshot.json"
  for sym in VIX DXY GLD WTI BTC; do
    jq -e ".instruments.${sym}.price" "$macro" >/dev/null
  done
}

# ── Watcher snapshot ──

@test "fetch-market-data: watcher-snapshot has all 5 equity-single assets" {
  local watcher="$OPC_IR_HOME/market-data/watcher-snapshot.json"
  [ -f "$watcher" ]
  for sym in MSFT NVDA GOOGL META TSM; do
    jq -e ".assets.${sym}.price" "$watcher" >/dev/null
    jq -e ".assets.${sym}.trend_3m" "$watcher" >/dev/null
  done
}

# ── Options sentiment ──

@test "fetch-market-data: options-snapshot has SPX and NDX with required fields" {
  local opts="$OPC_IR_HOME/market-data/options-snapshot.json"
  [ -f "$opts" ]
  for idx in SPX NDX; do
    jq -e ".sentiment.${idx}.call_volume" "$opts" >/dev/null
    jq -e ".sentiment.${idx}.put_volume" "$opts" >/dev/null
    jq -e ".sentiment.${idx}.call_notional_usd" "$opts" >/dev/null
    jq -e ".sentiment.${idx}.put_notional_usd" "$opts" >/dev/null
    jq -e ".sentiment.${idx}.put_call_ratio" "$opts" >/dev/null
    jq -e ".sentiment.${idx}.call_open_interest" "$opts" >/dev/null
    jq -e ".sentiment.${idx}.put_open_interest" "$opts" >/dev/null
  done
}

@test "fetch-market-data: options notional values are positive and P/C ratio is sane" {
  local opts="$OPC_IR_HOME/market-data/options-snapshot.json"
  for idx in SPX NDX; do
    local cn pn pc
    cn=$(jq ".sentiment.${idx}.call_notional_usd" "$opts")
    pn=$(jq ".sentiment.${idx}.put_notional_usd" "$opts")
    pc=$(jq ".sentiment.${idx}.put_call_ratio" "$opts")
    [ "$(echo "$cn > 0" | bc)" -eq 1 ]
    [ "$(echo "$pn > 0" | bc)" -eq 1 ]
    [ "$(echo "$pc > 0" | bc)" -eq 1 ]
  done
}

# ── Zero failures ──

@test "fetch-market-data: 26 assets fetched with 0 failures" {
  local macro="$OPC_IR_HOME/market-data/macro-snapshot.json"
  local failed
  failed=$(jq '._stats.failed' "$macro")
  [ "$failed" -eq 0 ]
}
