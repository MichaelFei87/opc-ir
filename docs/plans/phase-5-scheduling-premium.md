# Phase 5: Scheduling Abstraction + Premium — Implementation Plan

> **Status**: Ready for implementation
> **Prerequisite**: Phases 1–4 complete (core engine, memory layer, auto-loop, calibration all operational)
> **Estimated effort**: 5–7 calendar days (4–6 hrs/day)
> **Milestones**: M5.1 (Scheduler abstraction), M5.2 (Quota & expiry visibility), M5.3 (Premium-source framework), M5.4 (Plugin integrity check)

---

## Overview

Phase 5 productionizes OPC-IR by solving three classes of deferred risk:

1. **Scheduling brittleness** (T1) — `/loop` expires after 7 days; the system needs a unified scheduler interface so the same evolve/forecast/calibrate schedules work across `/loop`, Desktop Tasks, and Cloud Routines.
2. **Resource visibility** (T1, T2) — users must see loop expiry countdowns and token consumption before they silently hit walls.
3. **Data quality ceiling** (D2) — public RSS has an information density gap vs. Bloomberg/Refinitiv; a premium-source framework lets users with credentials plug in API sources without modifying core plugin code.
4. **Supply-chain integrity** (T6) — plugin file tampering detection via install-time SHA lock.

---

## M5.1 — Scheduler Abstraction

**Goal**: A unified `Scheduler` interface so the same schedule definitions work across three backends: `/loop` (Claude Code native), Desktop Tasks (macOS/Linux cron wrappers), and Cloud Routines (future webhook-based).

### M5.1-T1: Schedule definition file

Create `defaults/schedules.yaml` — the single source of truth for all recurring jobs:

```yaml
# defaults/schedules.yaml
# Override: ~/.opc-ir/config/local.yaml schedules section
schedules:
  evolve:
    command: /opc-ir-evolve
    interval: 1h
    description: "Fetch events, triage, update world-model"
    enabled: true

  forecast:
    # Forecast is driven by evolve (8h mtime check), not scheduled directly.
    # This entry exists for backends that cannot express "driven by another job".
    command: /opc-ir-forecast
    interval: 8h
    description: "5-strategist macro forecast"
    enabled: false  # default: driven by evolve Step 6
    standalone_ok: true

  calibrate:
    command: /opc-ir-calibrate
    interval: 24h
    description: "Ground-truth alignment + posterior weight update"
    enabled: true

  digest:
    command: /opc-ir-digest
    interval: 24h
    description: "Regenerate human-readable digest"
    enabled: true
    depends_on: calibrate  # run after calibrate completes
```

### M5.1-T2: Scheduler interface module

Create `pipeline/scheduler-protocol.md` — the abstract interface all backends implement:

```markdown
---
id: scheduler-protocol
scope: Phase 5 scheduler abstraction
---

# Scheduler Protocol

## Abstract Interface

Every scheduler backend MUST support these operations:

### 1. register(schedule_name, command, interval)
Idempotent. If the schedule already exists with the same interval, no-op.
If the interval changed, update in place.

### 2. unregister(schedule_name)
Remove a scheduled job. Idempotent (no error if not found).

### 3. list() → [{ name, command, interval, next_run, status, backend }]
Return all registered schedules with next-run time and status.

### 4. status(schedule_name) → { last_run, next_run, last_exit_code, backend }
Single-schedule health check.

## Backend Contract

Each backend writes its state to `~/.opc-ir/scheduler/{backend}.json`:

```json
{
  "backend": "loop",
  "registered_at": "2026-05-10T08:00:00Z",
  "schedules": {
    "evolve": {
      "command": "/opc-ir-evolve",
      "interval": "1h",
      "registered_at": "2026-05-10T08:00:00Z",
      "expires_at": "2026-05-17T08:00:00Z",
      "last_run": "2026-05-10T09:00:00Z",
      "last_exit_code": 0
    }
  }
}
```

## Supported Backends

### loop (Claude Code /loop)
- register → print `/loop {interval} {command}` instruction for user to execute
- 7-day expiry tracked in `expires_at`
- status reads `expires_at` and computes countdown

### desktop (cron / launchd)
- register → write crontab entry or launchd plist
- No expiry
- status reads cron log or launchd last-exit

### cloud (Cloud Routines — future)
- register → POST to webhook registration endpoint
- status polls endpoint health
- Stub implementation in Phase 5; full in future phase
```

### M5.1-T3: `/loop` backend implementation

Create `bin/scheduler-loop.sh`:

```bash
#!/usr/bin/env bash
# scheduler-loop.sh — /loop backend for OPC-IR scheduler
# Usage: scheduler-loop.sh <register|unregister|list|status> [args...]
set -euo pipefail

SCHEDULER_DIR="${OPC_IR_HOME:-$HOME/.opc-ir}/scheduler"
STATE_FILE="$SCHEDULER_DIR/loop.json"
mkdir -p "$SCHEDULER_DIR"

# Initialize state file if missing
if [ ! -f "$STATE_FILE" ]; then
  cat > "$STATE_FILE" << 'INIT'
{"backend":"loop","registered_at":null,"schedules":{}}
INIT
fi

case "${1:-help}" in
  register)
    SCHEDULE_NAME="$2"
    COMMAND="$3"
    INTERVAL="$4"
    NOW_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    EXPIRY_ISO=$(date -u -d "+7 days" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
                 date -u -v+7d +"%Y-%m-%dT%H:%M:%SZ")

    # Update state file via jq
    jq --arg name "$SCHEDULE_NAME" \
       --arg cmd "$COMMAND" \
       --arg int "$INTERVAL" \
       --arg now "$NOW_ISO" \
       --arg exp "$EXPIRY_ISO" \
       '.registered_at //= $now |
        .schedules[$name] = {
          command: $cmd,
          interval: $int,
          registered_at: $now,
          expires_at: $exp,
          last_run: null,
          last_exit_code: null
        }' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

    echo "Schedule '$SCHEDULE_NAME' registered."
    echo ""
    echo ">>> Run this in Claude Code to activate:"
    echo ">>>   /loop $INTERVAL $COMMAND"
    echo ""
    echo "WARNING: /loop expires in 7 days ($EXPIRY_ISO)."
    echo "Run '/opc-ir-status' to monitor expiry countdown."
    ;;

  unregister)
    SCHEDULE_NAME="$2"
    jq --arg name "$SCHEDULE_NAME" 'del(.schedules[$name])' \
       "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
    echo "Schedule '$SCHEDULE_NAME' unregistered."
    ;;

  list)
    jq -r '.schedules | to_entries[] |
      "\(.key)\t\(.value.command)\t\(.value.interval)\t\(.value.expires_at // "n/a")\t\(.value.last_exit_code // "pending")"' \
      "$STATE_FILE" | column -t -s$'\t' -N "NAME,COMMAND,INTERVAL,EXPIRES,LAST_EXIT"
    ;;

  status)
    SCHEDULE_NAME="$2"
    ENTRY=$(jq -r --arg name "$SCHEDULE_NAME" '.schedules[$name] // empty' "$STATE_FILE")
    if [ -z "$ENTRY" ]; then
      echo "Schedule '$SCHEDULE_NAME' not found."
      exit 1
    fi
    echo "$ENTRY" | jq .

    # Compute expiry countdown
    EXPIRES_AT=$(echo "$ENTRY" | jq -r '.expires_at // empty')
    if [ -n "$EXPIRES_AT" ]; then
      EXPIRES_EPOCH=$(date -d "$EXPIRES_AT" +%s 2>/dev/null || date -jf "%Y-%m-%dT%H:%M:%SZ" "$EXPIRES_AT" +%s)
      NOW_EPOCH=$(date +%s)
      REMAINING=$(( EXPIRES_EPOCH - NOW_EPOCH ))
      if [ "$REMAINING" -le 0 ]; then
        echo "EXPIRED — /loop needs renewal."
      else
        DAYS=$(( REMAINING / 86400 ))
        HOURS=$(( (REMAINING % 86400) / 3600 ))
        echo "Expires in: ${DAYS}d ${HOURS}h"
        if [ "$REMAINING" -le 86400 ]; then
          echo "WARNING: Less than 24 hours until /loop expiry!"
        fi
      fi
    fi
    ;;

  record-run)
    # Called by evolve/forecast/calibrate at end of run to track last_run
    SCHEDULE_NAME="$2"
    EXIT_CODE="$3"
    NOW_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq --arg name "$SCHEDULE_NAME" \
       --arg now "$NOW_ISO" \
       --argjson code "$EXIT_CODE" \
       '.schedules[$name].last_run = $now |
        .schedules[$name].last_exit_code = $code' \
       "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
    ;;

  *)
    echo "Usage: scheduler-loop.sh <register|unregister|list|status|record-run> [args...]"
    exit 1
    ;;
esac
```

### M5.1-T4: Desktop backend stub

Create `bin/scheduler-desktop.sh`:

```bash
#!/usr/bin/env bash
# scheduler-desktop.sh — cron/launchd backend for OPC-IR scheduler
# Phase 5 ships a functional cron backend; launchd support is best-effort.
set -euo pipefail

SCHEDULER_DIR="${OPC_IR_HOME:-$HOME/.opc-ir}/scheduler"
STATE_FILE="$SCHEDULER_DIR/desktop.json"
mkdir -p "$SCHEDULER_DIR"

if [ ! -f "$STATE_FILE" ]; then
  echo '{"backend":"desktop","schedules":{}}' > "$STATE_FILE"
fi

interval_to_cron() {
  case "$1" in
    1h)  echo "0 * * * *" ;;
    8h)  echo "0 */8 * * *" ;;
    24h) echo "0 6 * * *" ;;
    *)   echo "0 * * * *" ;;  # fallback hourly
  esac
}

CLAUDE_BIN=$(which claude 2>/dev/null || echo "claude")

case "${1:-help}" in
  register)
    SCHEDULE_NAME="$2"
    COMMAND="$3"
    INTERVAL="$4"
    CRON_EXPR=$(interval_to_cron "$INTERVAL")
    CRON_LINE="$CRON_EXPR $CLAUDE_BIN --command '$COMMAND' # opc-ir:$SCHEDULE_NAME"

    # Remove existing entry, add new
    (crontab -l 2>/dev/null | grep -v "opc-ir:$SCHEDULE_NAME"; echo "$CRON_LINE") | crontab -

    NOW_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq --arg name "$SCHEDULE_NAME" \
       --arg cmd "$COMMAND" \
       --arg int "$INTERVAL" \
       --arg now "$NOW_ISO" \
       --arg cron "$CRON_EXPR" \
       '.schedules[$name] = {
          command: $cmd,
          interval: $int,
          registered_at: $now,
          cron_expr: $cron,
          last_run: null,
          last_exit_code: null
        }' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

    echo "Cron job '$SCHEDULE_NAME' registered: $CRON_LINE"
    echo "No expiry — runs indefinitely until unregistered."
    ;;

  unregister)
    SCHEDULE_NAME="$2"
    crontab -l 2>/dev/null | grep -v "opc-ir:$SCHEDULE_NAME" | crontab -
    jq --arg name "$SCHEDULE_NAME" 'del(.schedules[$name])' \
       "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
    echo "Cron job '$SCHEDULE_NAME' removed."
    ;;

  list)
    echo "=== Cron entries ==="
    crontab -l 2>/dev/null | grep "opc-ir:" || echo "(none)"
    echo ""
    echo "=== State ==="
    jq -r '.schedules | to_entries[] |
      "\(.key)\t\(.value.command)\t\(.value.interval)\t\(.value.cron_expr)"' \
      "$STATE_FILE" | column -t -s$'\t' -N "NAME,COMMAND,INTERVAL,CRON"
    ;;

  status)
    SCHEDULE_NAME="$2"
    jq -r --arg name "$SCHEDULE_NAME" '.schedules[$name] // empty' "$STATE_FILE"
    echo "Backend: desktop (cron) — no expiry"
    ;;

  record-run)
    SCHEDULE_NAME="$2"
    EXIT_CODE="$3"
    NOW_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq --arg name "$SCHEDULE_NAME" \
       --arg now "$NOW_ISO" \
       --argjson code "$EXIT_CODE" \
       '.schedules[$name].last_run = $now |
        .schedules[$name].last_exit_code = $code' \
       "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
    ;;

  *)
    echo "Usage: scheduler-desktop.sh <register|unregister|list|status|record-run> [args...]"
    exit 1
    ;;
esac
```

### M5.1-T5: Scheduler dispatch helper

Create `bin/scheduler-dispatch.sh` — thin router that delegates to the active backend:

```bash
#!/usr/bin/env bash
# scheduler-dispatch.sh — routes scheduler commands to active backend
set -euo pipefail

SCHEDULER_DIR="${OPC_IR_HOME:-$HOME/.opc-ir}/scheduler"
BACKEND_FILE="$SCHEDULER_DIR/active-backend"

# Default to loop if no backend configured
BACKEND=$(cat "$BACKEND_FILE" 2>/dev/null || echo "loop")

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/scheduler-${BACKEND}.sh" "$@"
```

### M5.1-T6: Update commands to record runs

Each command (`opc-ir-evolve.md`, `opc-ir-forecast.md`, `opc-ir-calibrate.md`, `opc-ir-digest.md`) gains an epilogue step:

```markdown
## Step N+1: Record scheduler run

After all steps complete (success or handled failure):

```bash
bin/scheduler-dispatch.sh record-run <schedule-name> $EXIT_CODE
```

This updates the scheduler state so `/opc-ir-status` can report last-run times and health.
```

### M5.1 Exit Criteria

- `defaults/schedules.yaml` defines all 4 jobs
- `bin/scheduler-loop.sh register evolve /opc-ir-evolve 1h` succeeds and prints `/loop` instruction
- `bin/scheduler-desktop.sh register evolve /opc-ir-evolve 1h` writes a crontab entry
- `bin/scheduler-dispatch.sh list` delegates to the active backend
- `/opc-ir-status` displays next-run and expiry for all schedules

---

## M5.2 — Quota & Expiry Visibility

**Goal**: Surface `/loop` 7-day expiry countdown (T1) and per-run token consumption (T2) in `/opc-ir-status`.

### M5.2-T1: Loop expiry warning

Update `commands/opc-ir-status.md` to include scheduler expiry section:

```markdown
## Scheduler Health

Read `~/.opc-ir/scheduler/{active-backend}.json` and for each registered schedule, display:

| Schedule | Backend | Interval | Last Run | Next Run | Status |
|---|---|---|---|---|---|

For `/loop` backend, compute expiry countdown from `expires_at`:
- > 3 days remaining: display green "OK (Xd Yh remaining)"
- 1–3 days: display yellow "WARNING: Xd Yh until /loop expiry"
- < 24 hours: display red "CRITICAL: /loop expires in Xh — renew now"
- Expired: display red "EXPIRED: /loop has expired. Run /loop again to renew."

When expiry is < 24 hours, append to status output:

```
ACTION REQUIRED: Your /loop session expires in {hours}h.
To renew: stop current /loop, then run:
  /loop 1h /opc-ir-evolve
  /loop 24h /opc-ir-calibrate
```
```

### M5.2-T2: Token quota tracking

Create `bin/token-tracker.sh`:

```bash
#!/usr/bin/env bash
# token-tracker.sh — per-run token logging and accumulated visibility
set -euo pipefail

TOKEN_DIR="${OPC_IR_HOME:-$HOME/.opc-ir}/logs/tokens"
mkdir -p "$TOKEN_DIR"

case "${1:-help}" in
  record)
    # Called at end of each command run
    # Usage: token-tracker.sh record <command> <run_id> <input_tokens> <output_tokens>
    COMMAND="$2"
    RUN_ID="$3"
    INPUT_TOKENS="$4"
    OUTPUT_TOKENS="$5"
    TOTAL=$(( INPUT_TOKENS + OUTPUT_TOKENS ))
    NOW_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    DATE=$(date -u +"%Y-%m-%d")

    # Append to daily token log
    echo "{\"ts\":\"$NOW_ISO\",\"command\":\"$COMMAND\",\"run_id\":\"$RUN_ID\",\"input_tokens\":$INPUT_TOKENS,\"output_tokens\":$OUTPUT_TOKENS,\"total\":$TOTAL}" \
      >> "$TOKEN_DIR/$DATE.jsonl"
    ;;

  summary)
    # Usage: token-tracker.sh summary [days=7]
    DAYS="${2:-7}"
    echo "=== Token Usage (last ${DAYS} days) ==="
    echo ""

    GRAND_INPUT=0
    GRAND_OUTPUT=0
    GRAND_TOTAL=0

    for i in $(seq 0 $((DAYS - 1))); do
      DATE=$(date -u -d "-${i} days" +"%Y-%m-%d" 2>/dev/null || \
             date -u -v-${i}d +"%Y-%m-%d")
      FILE="$TOKEN_DIR/$DATE.jsonl"
      if [ -f "$FILE" ]; then
        DAY_INPUT=$(jq -s '[.[].input_tokens] | add // 0' "$FILE")
        DAY_OUTPUT=$(jq -s '[.[].output_tokens] | add // 0' "$FILE")
        DAY_TOTAL=$(jq -s '[.[].total] | add // 0' "$FILE")
        DAY_RUNS=$(wc -l < "$FILE" | tr -d ' ')
        echo "$DATE: ${DAY_RUNS} runs, ${DAY_TOTAL} tokens (in:${DAY_INPUT} out:${DAY_OUTPUT})"
        GRAND_INPUT=$((GRAND_INPUT + DAY_INPUT))
        GRAND_OUTPUT=$((GRAND_OUTPUT + DAY_OUTPUT))
        GRAND_TOTAL=$((GRAND_TOTAL + DAY_TOTAL))
      fi
    done

    echo ""
    echo "Total: ${GRAND_TOTAL} tokens (in:${GRAND_INPUT} out:${GRAND_OUTPUT})"

    # Per-command breakdown
    echo ""
    echo "=== By Command ==="
    find "$TOKEN_DIR" -name "*.jsonl" -newer "$TOKEN_DIR" -mtime -"$DAYS" -exec cat {} + 2>/dev/null | \
      jq -s 'group_by(.command) | map({
        command: .[0].command,
        runs: length,
        total_tokens: [.[].total] | add
      }) | sort_by(-.total_tokens) | .[]' 2>/dev/null || echo "(no data)"
    ;;

  *)
    echo "Usage: token-tracker.sh <record|summary> [args...]"
    exit 1
    ;;
esac
```

### M5.2-T3: Integrate token tracking into commands

Each command's epilogue (after scheduler record-run) adds:

```markdown
## Step N+2: Record token usage

After run completes, record token consumption:

```bash
bin/token-tracker.sh record <command-name> $RUN_ID $INPUT_TOKENS $OUTPUT_TOKENS
```

Note: `$INPUT_TOKENS` and `$OUTPUT_TOKENS` are extracted from the Claude API response
metadata available in the harness run context. If unavailable (e.g., no API-level
instrumentation), estimate from character count: `tokens ≈ chars / 4`.
```

### M5.2-T4: Status command integration

Extend `commands/opc-ir-status.md` with token and quota section:

```markdown
## Token Usage

Run `bin/token-tracker.sh summary 7` and display output.

Include the following computed metrics:
- **Daily average**: total_7d / 7
- **Projected monthly**: daily_average × 30
- **Last run cost**: most recent entry from today's log

If user has configured `quota_monthly_tokens` in `~/.opc-ir/config/local.yaml`:
- Show usage as percentage of quota
- Warn if projected monthly > 80% of quota
- Alert if projected monthly > 100% of quota

Example output:

```
Token Usage (7-day window):
  Total:     847,231 tokens
  Daily avg: 121,033 tokens
  Projected: 3,631,000 tokens/month

  Quota: 5,000,000 tokens/month
  Used:  16.9% (current month)
  Projected: 72.6% — OK
```
```

### M5.2 Exit Criteria

- `/opc-ir-status` shows loop expiry countdown with color-coded severity
- `/opc-ir-status` shows 7-day token summary with per-command breakdown
- When `quota_monthly_tokens` is set, status shows percentage and projection
- Expiry < 24h produces actionable renewal instructions

---

## M5.3 — Premium-Source Framework

**Goal**: Extend `defaults/sources.yaml` with a `type` field, define `secrets.env` conventions, and document the premium-source integration path.

### M5.3-T1: Extend sources.yaml schema

Update `defaults/sources.yaml` to include the type field:

```yaml
# defaults/sources.yaml
# Source types: rss (default, free), scrape (free, fragile), api (premium, requires secrets.env)
sources:
  # === Free RSS sources (ship with plugin) ===
  reuters-business:
    type: rss
    url: "https://feeds.reuters.com/reuters/businessNews"
    dimensions: [econ-finance, corp-fundamentals]
    enabled: true

  reuters-world:
    type: rss
    url: "https://feeds.reuters.com/reuters/worldNews"
    dimensions: [politics, military]
    enabled: true

  cnbc-economy:
    type: rss
    url: "https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=20910258"
    dimensions: [econ-finance]
    enabled: true

  ft-world:
    type: rss
    url: "https://www.ft.com/world?format=rss"
    dimensions: [politics, econ-finance]
    enabled: true

  arxiv-ai:
    type: rss
    url: "http://export.arxiv.org/rss/cs.AI"
    dimensions: [tech-ai]
    enabled: true

  eia-petroleum:
    type: rss
    url: "https://www.eia.gov/rss/todayinenergy.xml"
    dimensions: [energy-commodity]
    enabled: true

  fed-speeches:
    type: rss
    url: "https://www.federalreserve.gov/feeds/speeches.xml"
    dimensions: [econ-finance, politics]
    enabled: true

  pboc-news:
    type: scrape
    url: "http://www.pbc.gov.cn/english/130721/index.html"
    dimensions: [econ-finance, politics]
    enabled: true
    parser: pboc-html  # custom parser in bin/parsers/

  scmp-china:
    type: rss
    url: "https://www.scmp.com/rss/91/feed"
    dimensions: [politics, military, econ-finance]
    enabled: true

  caixin-headlines:
    type: rss
    url: "https://www.caixinglobal.com/rss.html"
    dimensions: [econ-finance, corp-fundamentals]
    enabled: true

  # === Premium API sources (disabled by default, require secrets.env) ===
  bloomberg-api:
    type: api
    endpoint: "https://api.bloomberg.com/market/v1/news"
    auth_env: BLOOMBERG_API_KEY
    auth_header: "X-Bloomberg-Token"
    dimensions: [econ-finance, corp-fundamentals, energy-commodity]
    enabled: false
    rate_limit: 100/hour

  refinitiv-api:
    type: api
    endpoint: "https://api.refinitiv.com/news/v1/headlines"
    auth_env: REFINITIV_APP_KEY
    auth_header: "Authorization: Bearer"
    dimensions: [econ-finance, corp-fundamentals]
    enabled: false
    rate_limit: 500/hour

  tradingview-webhooks:
    type: api
    endpoint: "https://scanner.tradingview.com/global/scan"
    auth_env: TRADINGVIEW_SESSION_ID
    auth_header: "Cookie: sessionid="
    dimensions: [econ-finance, corp-fundamentals]
    enabled: false

  newsapi:
    type: api
    endpoint: "https://newsapi.org/v2/top-headlines"
    auth_env: NEWSAPI_KEY
    auth_header: "X-Api-Key"
    dimensions: [politics, econ-finance, tech-ai, humanities]
    enabled: false
    rate_limit: 1000/day
    params:
      category: "business,technology,science"
      language: "en"
```

### M5.3-T2: secrets.env conventions

The file `~/.opc-ir/config/secrets.env` is the single location for API credentials:

```bash
# ~/.opc-ir/config/secrets.env
# This file is NEVER committed. Add credentials for premium sources here.
# Enable the corresponding source in ~/.opc-ir/config/local.yaml:
#   sources:
#     bloomberg-api:
#       enabled: true

# BLOOMBERG_API_KEY=your-key-here
# REFINITIV_APP_KEY=your-key-here
# TRADINGVIEW_SESSION_ID=your-session-id
# NEWSAPI_KEY=your-key-here
```

### M5.3-T3: Update fetch-rss.sh to handle API sources

Extend `bin/fetch-rss.sh` to dispatch by source type:

```bash
# Add to bin/fetch-rss.sh after existing RSS fetch logic:

fetch_api_source() {
  local SOURCE_NAME="$1"
  local ENDPOINT="$2"
  local AUTH_ENV="$3"
  local AUTH_HEADER="$4"
  local PARAMS="$5"

  # Load secrets
  SECRETS_FILE="${OPC_IR_HOME:-$HOME/.opc-ir}/config/secrets.env"
  if [ ! -f "$SECRETS_FILE" ]; then
    log_warn "$SOURCE_NAME: secrets.env not found, skipping"
    return 1
  fi
  source "$SECRETS_FILE"

  # Check if credential is set
  local API_KEY="${!AUTH_ENV:-}"
  if [ -z "$API_KEY" ]; then
    log_warn "$SOURCE_NAME: $AUTH_ENV not set in secrets.env, skipping"
    return 1
  fi

  # Build curl command based on auth_header format
  local CURL_ARGS=()
  if [[ "$AUTH_HEADER" == *"Bearer"* ]]; then
    CURL_ARGS+=(-H "Authorization: Bearer $API_KEY")
  elif [[ "$AUTH_HEADER" == *"Cookie:"* ]]; then
    CURL_ARGS+=(-H "Cookie: ${AUTH_HEADER#Cookie: }$API_KEY")
  else
    CURL_ARGS+=(-H "$AUTH_HEADER: $API_KEY")
  fi

  local FULL_URL="$ENDPOINT"
  if [ -n "$PARAMS" ]; then
    FULL_URL="${ENDPOINT}?${PARAMS}"
  fi

  local RESPONSE
  RESPONSE=$(curl -sf --max-time 30 "${CURL_ARGS[@]}" "$FULL_URL") || {
    log_warn "$SOURCE_NAME: API request failed (exit $?)"
    return 1
  }

  # Parse JSON response into events.jsonl format
  # Each API source may need a custom parser; fallback to generic JSON extraction
  echo "$RESPONSE" | jq -c --arg src "$SOURCE_NAME" '.[] // . |
    {
      id: ($src + "-" + (.id // .uuid // .storyId // (.title | gsub("[^a-zA-Z0-9]"; "-")[0:40]) | tostring) + "-" + (now | tostring)),
      source: $src,
      fetched_at: (now | todate),
      published_at: (.published_at // .dateTime // .publishedAt // (now | todate)),
      title: (.title // .headline // ""),
      summary: (.summary // .description // .body[0:500] // ""),
      url: (.url // .link // ""),
      raw_text: (.body // .content // .summary // "")
    }' 2>/dev/null
}

# In the main source iteration loop, add:
process_source() {
  local SOURCE_NAME="$1"
  local SOURCE_TYPE
  SOURCE_TYPE=$(yq -r ".sources.\"$SOURCE_NAME\".type // \"rss\"" "$SOURCES_FILE")

  case "$SOURCE_TYPE" in
    rss)
      fetch_rss_source "$SOURCE_NAME"
      ;;
    scrape)
      fetch_scrape_source "$SOURCE_NAME"
      ;;
    api)
      local ENDPOINT AUTH_ENV AUTH_HEADER PARAMS
      ENDPOINT=$(yq -r ".sources.\"$SOURCE_NAME\".endpoint" "$SOURCES_FILE")
      AUTH_ENV=$(yq -r ".sources.\"$SOURCE_NAME\".auth_env" "$SOURCES_FILE")
      AUTH_HEADER=$(yq -r ".sources.\"$SOURCE_NAME\".auth_header" "$SOURCES_FILE")
      PARAMS=$(yq -r ".sources.\"$SOURCE_NAME\".params // {} | to_entries | map(\"\(.key)=\(.value)\") | join(\"&\")" "$SOURCES_FILE")
      fetch_api_source "$SOURCE_NAME" "$ENDPOINT" "$AUTH_ENV" "$AUTH_HEADER" "$PARAMS"
      ;;
    *)
      log_warn "$SOURCE_NAME: unknown type '$SOURCE_TYPE', skipping"
      ;;
  esac
}
```

### M5.3-T4: PREMIUM-SOURCES.md guide

Create `docs/PREMIUM-SOURCES.md`:

```markdown
# Premium Sources Guide

OPC-IR ships with 10+ free RSS sources that provide reasonable coverage for macro
analysis. For users with access to premium data providers, the plugin supports
API-based sources that significantly increase information density and timeliness.

## Quick Start

1. **Get credentials** from your data provider (Bloomberg, Refinitiv, NewsAPI, etc.)

2. **Add credentials** to `~/.opc-ir/config/secrets.env`:
   ```bash
   # Create the file if it doesn't exist
   touch ~/.opc-ir/config/secrets.env
   chmod 600 ~/.opc-ir/config/secrets.env

   # Add your key
   echo 'NEWSAPI_KEY=abc123def456' >> ~/.opc-ir/config/secrets.env
   ```

3. **Enable the source** in `~/.opc-ir/config/local.yaml`:
   ```yaml
   sources:
     newsapi:
       enabled: true
   ```

4. **Verify** with a dry run:
   ```
   /opc-ir-evolve --dry-run
   ```
   The status output will show the new source fetching events.

## Supported Premium Sources

| Source | Env Variable | Dimensions | Rate Limit | Notes |
|---|---|---|---|---|
| Bloomberg API | `BLOOMBERG_API_KEY` | econ, corp, energy | 100/hr | Enterprise terminal license required |
| Refinitiv/LSEG | `REFINITIV_APP_KEY` | econ, corp | 500/hr | Eikon or Workspace subscription |
| NewsAPI | `NEWSAPI_KEY` | politics, econ, tech, humanities | 1000/day | Free tier: 100 req/day |
| TradingView | `TRADINGVIEW_SESSION_ID` | econ, corp | Best effort | Session cookie from browser |

## Security

- `secrets.env` is stored in `~/.opc-ir/config/` — outside the plugin repo
- Never committed to git (the plugin repo has no access to `~/.opc-ir/`)
- File permissions should be `600` (owner read/write only)
- Keys are loaded at fetch time only, never logged or persisted in events.jsonl
- The `source` field in events.jsonl records the source name, not the credential

## Adding Custom API Sources

Add to `~/.opc-ir/config/local.yaml`:

```yaml
sources:
  my-custom-api:
    type: api
    endpoint: "https://api.example.com/v1/news"
    auth_env: MY_CUSTOM_API_KEY
    auth_header: "Authorization: Bearer"
    dimensions: [econ-finance, tech-ai]
    enabled: true
    rate_limit: 100/hour
```

Then add `MY_CUSTOM_API_KEY=...` to `secrets.env`.

The generic API fetcher expects a JSON response. If the API returns a non-standard
format, create a custom parser in `bin/parsers/` and reference it:

```yaml
sources:
  my-custom-api:
    type: api
    parser: my-custom  # → bin/parsers/my-custom.sh
    ...
```

## Impact on Analysis Quality

Premium sources primarily improve:
- **Timeliness**: API sources deliver news seconds after publication vs. 15–60 min RSS delay
- **Coverage**: Bloomberg/Refinitiv cover earnings, M&A, credit events that RSS often misses
- **Depth**: Full article text vs. RSS summaries enable richer triage and watcher analysis

The calibration system (Phase 4) will naturally learn to weight predictions made
with premium data more heavily if they prove more accurate.
```

### M5.3 Exit Criteria

- `defaults/sources.yaml` has `type` field on all sources; 4+ `type: api` sources defined (disabled)
- `bin/fetch-rss.sh` handles `rss`, `scrape`, and `api` types via `process_source` dispatch
- `secrets.env` template exists at init time with all supported env vars commented out
- `docs/PREMIUM-SOURCES.md` covers setup, security, custom sources
- Enabling a source in `local.yaml` + adding key to `secrets.env` → events appear in events.jsonl

---

## M5.4 — Plugin Integrity Check

**Goal**: Detect plugin file tampering via SHA256 hash verification (T6).

### M5.4-T1: Install lock generation

Create `bin/integrity.sh`:

```bash
#!/usr/bin/env bash
# integrity.sh — plugin file integrity management
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCK_DIR="${OPC_IR_HOME:-$HOME/.opc-ir}"
LOCK_FILE="$LOCK_DIR/install.lock"

generate_manifest() {
  # Hash all plugin files (excluding docs, .git, runtime data)
  find "$PLUGIN_ROOT" \
    -type f \
    ! -path "*/.git/*" \
    ! -path "*/docs/*" \
    ! -path "*/.claude/*" \
    ! -name "*.log" \
    ! -name ".DS_Store" \
    | sort \
    | while read -r file; do
        RELPATH="${file#$PLUGIN_ROOT/}"
        HASH=$(sha256sum "$file" | cut -d' ' -f1)
        echo "$HASH  $RELPATH"
      done
}

case "${1:-help}" in
  lock)
    # Generate install lock at install time
    mkdir -p "$LOCK_DIR"
    MANIFEST=$(generate_manifest)
    MASTER_HASH=$(echo "$MANIFEST" | sha256sum | cut -d' ' -f1)
    NOW_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    cat > "$LOCK_FILE" << EOF
{
  "locked_at": "$NOW_ISO",
  "plugin_root": "$PLUGIN_ROOT",
  "master_hash": "$MASTER_HASH",
  "file_count": $(echo "$MANIFEST" | wc -l | tr -d ' '),
  "manifest_hash_algorithm": "sha256"
}
EOF

    # Store full manifest alongside lock
    echo "$MANIFEST" > "$LOCK_DIR/install.manifest"

    echo "Install lock created: $LOCK_FILE"
    echo "Master hash: $MASTER_HASH"
    echo "Files locked: $(echo "$MANIFEST" | wc -l | tr -d ' ')"
    ;;

  verify)
    # Verify plugin integrity against install lock
    if [ ! -f "$LOCK_FILE" ]; then
      echo "NO LOCK: install.lock not found. Run 'bin/integrity.sh lock' after install."
      exit 1
    fi

    if [ ! -f "$LOCK_DIR/install.manifest" ]; then
      echo "NO MANIFEST: install.manifest not found. Re-run 'bin/integrity.sh lock'."
      exit 1
    fi

    EXPECTED_MASTER=$(jq -r '.master_hash' "$LOCK_FILE")
    CURRENT_MANIFEST=$(generate_manifest)
    CURRENT_MASTER=$(echo "$CURRENT_MANIFEST" | sha256sum | cut -d' ' -f1)

    if [ "$EXPECTED_MASTER" = "$CURRENT_MASTER" ]; then
      echo "INTEGRITY OK: all plugin files match install lock."
      echo "Master hash: $CURRENT_MASTER"
      exit 0
    fi

    echo "INTEGRITY MISMATCH: plugin files have changed since install."
    echo "Expected: $EXPECTED_MASTER"
    echo "Current:  $CURRENT_MASTER"
    echo ""

    # Show specific differences
    STORED_MANIFEST="$LOCK_DIR/install.manifest"
    echo "=== Changed files ==="
    diff <(sort "$STORED_MANIFEST") <(echo "$CURRENT_MANIFEST" | sort) | \
      grep "^[<>]" | sed 's/^< /REMOVED: /; s/^> /ADDED\/MODIFIED: /' || true

    echo ""
    echo "If these changes are expected (e.g., plugin update), run:"
    echo "  bin/integrity.sh lock"
    echo "to update the install lock."
    exit 2
    ;;

  *)
    echo "Usage: integrity.sh <lock|verify>"
    echo ""
    echo "  lock    — Generate install lock (run after install/update)"
    echo "  verify  — Check plugin files against lock"
    exit 1
    ;;
esac
```

### M5.4-T2: Hook into /opc-ir-init

Update `commands/opc-ir-init.md` to run `bin/integrity.sh lock` as the final step:

```markdown
## Step N+1: Generate install lock

After directory creation and config scaffolding:

```bash
bin/integrity.sh lock
```

This captures the SHA256 hash of all plugin files at install time.
The lock is stored at `~/.opc-ir/install.lock` and verified by `/opc-ir-status`.
```

### M5.4-T3: Hook into /opc-ir-status

Update `commands/opc-ir-status.md` with integrity section:

```markdown
## Plugin Integrity

Run `bin/integrity.sh verify` and display the result:

- **INTEGRITY OK**: "Plugin files verified (SHA: {first 12 chars of master_hash})"
- **INTEGRITY MISMATCH**: List changed files and display warning
- **NO LOCK**: "Install lock not found — run /opc-ir-init to generate"

This detects unauthorized modifications to plugin commands, agents, roles,
pipeline protocols, or bin scripts since installation.
```

### M5.4 Exit Criteria

- `bin/integrity.sh lock` produces `~/.opc-ir/install.lock` + `install.manifest`
- `bin/integrity.sh verify` returns exit 0 on clean install, exit 2 on mismatch
- Modifying any plugin file → `verify` detects and lists the changed file
- `/opc-ir-status` includes integrity check result
- `/opc-ir-init` automatically generates the lock

---

## Full Phase 5 Status Command Output

After all milestones, `/opc-ir-status` produces output like:

```
=== OPC-IR Status ===

Plugin: v0.5.0 (Phase 5)
Integrity: OK (SHA: a3f8b2c91d4e)

=== Scheduler ===
Backend: loop
| Schedule  | Interval | Last Run             | Status                        |
|-----------|----------|----------------------|-------------------------------|
| evolve    | 1h       | 2026-05-15T14:00:00Z | OK (expires in 2d 14h)        |
| calibrate | 24h      | 2026-05-15T06:00:00Z | OK (expires in 2d 14h)        |
| digest    | 24h      | 2026-05-15T06:05:00Z | OK (expires in 2d 14h)        |

=== Token Usage (7-day) ===
Total:     847,231 tokens
Daily avg: 121,033 tokens
Projected: 3,631,000 tokens/month
Quota:     5,000,000 tokens/month (72.6%)

=== Data Sources ===
RSS:     10 active (0 stale)
API:     1 active (newsapi)
Scrape:  1 active (pboc-news)

=== Streams ===
World-Model: updated 2026-05-15T14:03:12Z (12 min ago)
Forecast:    updated 2026-05-15T12:00:05Z (2h ago), next ~18:00
Verdict:     last NDX 2026-05-15T09:15:00Z
Calibration: N=47 (posterior active), regime=stable
```

---

## Dependency & Sequencing

```
M5.1-T1 (schedules.yaml)
M5.1-T2 (scheduler-protocol.md)         ─┐
M5.1-T3 (scheduler-loop.sh)              ├─ M5.1-T5 (dispatch) ─── M5.1-T6 (command epilogues)
M5.1-T4 (scheduler-desktop.sh)          ─┘

M5.2-T1 (expiry warning)                 ─┐
M5.2-T2 (token-tracker.sh)               ├─ M5.2-T4 (status integration)
M5.2-T3 (command token recording)        ─┘

M5.3-T1 (sources.yaml schema)            ─┐
M5.3-T2 (secrets.env conventions)         ├─ M5.3-T3 (fetch-rss.sh update)
                                          └─ M5.3-T4 (PREMIUM-SOURCES.md)

M5.4-T1 (integrity.sh)                   ─── M5.4-T2 (init hook) + M5.4-T3 (status hook)
```

Parallelizable pairs: M5.1 + M5.4 (no dependencies); M5.2 + M5.3 (no dependencies). Within each milestone, tasks are largely sequential.

Recommended order: M5.4 (smallest, quick win) → M5.3 (sources framework) → M5.1 (scheduler) → M5.2 (visibility, depends on M5.1 state files).

---

## Phase 5 Exit Criteria

1. All 4 milestones pass their individual exit criteria
2. `/opc-ir-status` produces the full output shown above (all sections populated)
3. `bin/scheduler-loop.sh` and `bin/scheduler-desktop.sh` both pass register/list/status cycle
4. Premium source (e.g., NewsAPI with real key) fetches events into events.jsonl
5. `bin/integrity.sh verify` detects a manually-modified plugin file
6. No regression: evolve → forecast → verdict → calibrate cycle runs clean with Phase 5 epilogues
