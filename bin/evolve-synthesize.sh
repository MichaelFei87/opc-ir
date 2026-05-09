#!/usr/bin/env bash
set -euo pipefail

# evolve-synthesize.sh — Render market data + append delta to jsonl audit log
#
# This script handles ONLY structured data processing:
#   1. Renders market data JSON → Markdown table (market-data-section.md)
#   2. Appends delta metadata to world-model.jsonl (audit log)
#
# It does NOT modify world-model.md — narrative synthesis is done by the
# LLM orchestrator in Step 7b (see pipeline/evolve-protocol.md).
#
# Usage: evolve-synthesize.sh <watcher-outputs-dir> <world-model.jsonl> [--market-dir <path>]

USAGE="Usage: evolve-synthesize.sh <watcher-outputs-dir> <world-model.jsonl> [--market-dir <path>]"
WATCHER_DIR="${1:?$USAGE}"
WM_JSONL="${2:?$USAGE}"
shift 2

MARKET_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --market-dir) MARKET_DIR="$2"; shift 2 ;;
    *)            echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

RUN_ID="evolve-$(date -u +%Y%m%dT%H%M%SZ)"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Discover watcher output files (any .md in watcher dir)
WATCHER_FILES=()
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  WATCHER_FILES+=("$f")
done < <(find "$WATCHER_DIR" -name '*.md' 2>/dev/null | sort)

if [[ ${#WATCHER_FILES[@]} -eq 0 ]]; then
  echo "Warning: no watcher outputs found in $WATCHER_DIR" >&2
  # Still proceed — market data update is valuable even without watcher deltas
fi

WATCHER_DIR="$WATCHER_DIR" WM_JSONL="$WM_JSONL" MARKET_DIR="$MARKET_DIR" \
  RUN_ID="$RUN_ID" TIMESTAMP="$TIMESTAMP" \
  python3 << 'PYEOF'
import json
import os

watcher_dir = os.environ["WATCHER_DIR"]
wm_jsonl = os.environ["WM_JSONL"]
run_id = os.environ["RUN_ID"]
timestamp = os.environ["TIMESTAMP"]
market_dir = os.environ.get("MARKET_DIR", "")

# ── 1. Discover dimensions from watcher files ──

dimensions_updated = set()
for f in sorted(os.listdir(watcher_dir)):
    if f.endswith('.md'):
        dim = f.replace('.md', '')
        dimensions_updated.add(dim)

# ── 2. Append delta metadata to jsonl (audit log) ──

delta_entry = {
    "run_id": run_id,
    "timestamp": timestamp,
    "dimensions_updated": sorted(dimensions_updated),
    "watcher_count": len(dimensions_updated)
}

with open(wm_jsonl, "a") as f:
    f.write(json.dumps(delta_entry) + "\n")

# ── 3. Render market data section ──

def val(inst, key, default="—"):
    v = inst.get(key, default)
    return str(v) if v is not None else default

def render_market_data(market_dir):
    if not market_dir:
        return ""
    macro_path = os.path.join(market_dir, "macro-snapshot.json")
    watcher_path = os.path.join(market_dir, "watcher-snapshot.json")
    options_path = os.path.join(market_dir, "options-snapshot.json")
    if not os.path.exists(macro_path) and not os.path.exists(watcher_path):
        return ""

    lines = ["## Market Data\n"]

    macro = {}
    if os.path.exists(macro_path):
        with open(macro_path) as f:
            macro = json.load(f)
    watcher = {}
    if os.path.exists(watcher_path):
        with open(watcher_path) as f:
            watcher = json.load(f)
    options = {}
    if os.path.exists(options_path):
        with open(options_path) as f:
            options = json.load(f)

    instruments = macro.get("instruments", {})
    fetched_at = macro.get("fetched_at", watcher.get("fetched_at", "unknown"))
    lines.append(f"> As of {fetched_at}\n")

    # Yield Curve
    yield_syms = ["US3M", "US2Y", "US5Y", "US10Y", "US30Y"]
    yield_data = {s: instruments[s] for s in yield_syms if s in instruments}
    if yield_data:
        lines.append("### Yield Curve\n")
        lines.append("| Tenor | Yield | 1d Chg | 1m Trend |")
        lines.append("|-------|-------|--------|----------|")
        for s in yield_syms:
            if s in yield_data:
                d = yield_data[s]
                lines.append(f"| {s} | {val(d,'yield')} | {val(d,'change_1d')} | {val(d,'trend_1m')} |")
        spread = instruments.get("2s10s_spread")
        if spread:
            lines.append(f"\n**2s10s Spread**: {val(spread,'value')}% ({val(spread,'trend_1m')})\n")

    # Equity Indices
    idx_syms = ["NDX", "SPX", "RUT", "HSI", "HSCEI", "CSI300"]
    idx_data = {s: instruments[s] for s in idx_syms if s in instruments}
    if idx_data:
        lines.append("### Equity Indices\n")
        lines.append("| Index | Price | 1d Chg | 1w Trend | 1m Trend |")
        lines.append("|-------|-------|--------|----------|----------|")
        for s in idx_syms:
            if s in idx_data:
                d = idx_data[s]
                lines.append(f"| {s} | {val(d,'price')} | {val(d,'change_1d_pct')} | {val(d,'trend_1w')} | {val(d,'trend_1m')} |")
        lines.append("")

    # Currencies
    cur_syms = ["DXY", "CNH", "USDCNY"]
    cur_data = {s: instruments[s] for s in cur_syms if s in instruments}
    if cur_data:
        lines.append("### Currencies\n")
        lines.append("| Pair | Price | 1d Chg | 1m Trend |")
        lines.append("|------|-------|--------|----------|")
        for s in cur_syms:
            if s in cur_data:
                d = cur_data[s]
                lines.append(f"| {s} | {val(d,'price')} | {val(d,'change_1d_pct')} | {val(d,'trend_1m')} |")
        lines.append("")

    # Commodities
    com_syms = ["GLD", "WTI"]
    com_data = {s: instruments[s] for s in com_syms if s in instruments}
    if com_data:
        lines.append("### Commodities\n")
        lines.append("| Asset | Price | 1d Chg | 1w Trend | 1m Trend |")
        lines.append("|-------|-------|--------|----------|----------|")
        for s in com_syms:
            if s in com_data:
                d = com_data[s]
                lines.append(f"| {s} | {val(d,'price')} | {val(d,'change_1d_pct')} | {val(d,'trend_1w')} | {val(d,'trend_1m')} |")
        lines.append("")

    # Volatility + Crypto
    for label, syms in [("Volatility", ["VIX"]), ("Crypto", ["BTC"])]:
        sec_data = {s: instruments[s] for s in syms if s in instruments}
        if sec_data:
            lines.append(f"### {label}\n")
            for s in syms:
                if s in sec_data:
                    d = sec_data[s]
                    lines.append(f"- **{s}**: {val(d,'price')} ({val(d,'change_1d_pct')} 1d, {val(d,'trend_1m')} 1m)")
            lines.append("")

    # Tracked Equities (from watcher-snapshot)
    eq_assets = watcher.get("assets", {})
    if eq_assets:
        lines.append("### Tracked Equities\n")
        lines.append("| Ticker | Price | 1d Chg | 1m Trend | 3m Trend | 52w Range |")
        lines.append("|--------|-------|--------|----------|----------|-----------|")
        for sym, d in sorted(eq_assets.items()):
            hi = val(d, 'high_52w')
            lo = val(d, 'low_52w')
            lines.append(f"| {sym} | {val(d,'price')} | {val(d,'change_1d_pct')} | {val(d,'trend_1m')} | {val(d,'trend_3m')} | {lo}–{hi} |")
        lines.append("")

    # Options Sentiment
    opt_data = options.get("sentiment", {})
    if opt_data:
        lines.append("### Options Sentiment\n")
        lines.append("| Index | Proxy | Call Vol | Put Vol | P/C Ratio | Call Notional | Put Notional | Call OI | Put OI |")
        lines.append("|-------|-------|----------|---------|-----------|---------------|--------------|---------|--------|")
        for idx in sorted(opt_data.keys()):
            d = opt_data[idx]
            def fmt_usd(v):
                if v >= 1_000_000_000: return f"${v/1e9:.1f}B"
                if v >= 1_000_000: return f"${v/1e6:.0f}M"
                if v >= 1_000: return f"${v/1e3:.0f}K"
                return f"${v:,.0f}"
            def fmt_int(v):
                if v >= 1_000_000: return f"{v/1e6:.1f}M"
                if v >= 1_000: return f"{v/1e3:.0f}K"
                return f"{v:,}"
            lines.append(f"| {idx} | {val(d,'proxy')} | {fmt_int(d.get('call_volume',0))} | {fmt_int(d.get('put_volume',0))} | {val(d,'put_call_ratio')} | {fmt_usd(d.get('call_notional_usd',0))} | {fmt_usd(d.get('put_notional_usd',0))} | {fmt_int(d.get('call_open_interest',0))} | {fmt_int(d.get('put_open_interest',0))} |")
        lines.append(f"\n> Sampled from nearest {val(list(opt_data.values())[0], 'expirations_sampled', '?')} expirations per proxy\n")

    return "\n".join(lines) + "\n"

market_md = render_market_data(market_dir)

# Write market-data-section.md to watcher_dir's parent (the run dir)
run_dir = os.path.dirname(watcher_dir.rstrip('/'))
market_out = os.path.join(run_dir, "market-data-section.md")
with open(market_out, "w") as f:
    f.write(market_md)

print(f"run_id: {run_id}")
print(f"dimensions: {','.join(sorted(dimensions_updated)) if dimensions_updated else '(none)'}")
print(f"market_data: {market_out}")
print(f"jsonl_appended: {wm_jsonl}")
PYEOF
