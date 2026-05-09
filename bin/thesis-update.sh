#!/usr/bin/env bash
set -euo pipefail

# thesis-update.sh — Update thesis file for a ticker, preserving history
# Usage: thesis-update.sh <opc-ir-home> <ticker> <verdict.json>
#
# Reads the current thesis file (if any), archives the prior stance to History,
# then writes the new thesis from the verdict JSON.

OPC_IR_HOME="${1:?Usage: thesis-update.sh <opc-ir-home> <ticker> <verdict.json>}"
TICKER="${2:?Usage: thesis-update.sh <opc-ir-home> <ticker> <verdict.json>}"
VERDICT_JSON="${3:?Usage: thesis-update.sh <opc-ir-home> <ticker> <verdict.json>}"

THESES_DIR="$OPC_IR_HOME/verdict/theses"
mkdir -p "$THESES_DIR"

THESIS_FILE="$THESES_DIR/${TICKER}.md"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Extract verdict fields (guard nulls)
DIRECTION=$(jq -r '.consensus.direction // "unknown"' "$VERDICT_JSON")
CONVICTION=$(jq -r '.consensus.conviction // 0' "$VERDICT_JSON")
HORIZON=$(jq -r '.consensus.horizon // "unknown"' "$VERDICT_JSON")

# Collect falsifiers
FALSIFIERS=$(jq -r '.falsifiers[] | "- [\(.role)] \(.condition)"' "$VERDICT_JSON" 2>/dev/null || echo "- (none)")

# Collect dissent
DISSENT=$(jq -r '.preserved_dissent[] | "- **\(.role)** (\(.direction)): \(.reasoning_summary)"' "$VERDICT_JSON" 2>/dev/null || echo "")

# Build prior history entry if thesis file exists
PRIOR_HISTORY=""
EXISTING_HISTORY=""
if [[ -f "$THESIS_FILE" ]]; then
  # Extract current stance for archival (use env vars for path safety)
  PRIOR_DIRECTION=$(THESIS_FILE="$THESIS_FILE" python3 -c "
import re, os
content = open(os.environ['THESIS_FILE']).read()
m = re.search(r'Direction:\s*(.+)', content)
print(m.group(1).strip() if m else 'unknown')
")
  PRIOR_DATE=$(THESIS_FILE="$THESIS_FILE" python3 -c "
import re, os
content = open(os.environ['THESIS_FILE']).read()
m = re.search(r'updated_at:\s*(.+)', content)
print(m.group(1).strip() if m else 'unknown')
")

  PRIOR_HISTORY="- **${PRIOR_DATE}** — ${PRIOR_DIRECTION}"

  # Preserve existing History section entries
  EXISTING_HISTORY=$(THESIS_FILE="$THESIS_FILE" python3 -c "
import re, os
content = open(os.environ['THESIS_FILE']).read()
m = re.search(r'## History\n\n(.*?)(?:\n##|\Z)', content, re.DOTALL)
if m:
    print(m.group(1).strip())
else:
    print('')
")
fi

# Build full history
HISTORY_SECTION=""
if [[ -n "$PRIOR_HISTORY" ]] || [[ -n "$EXISTING_HISTORY" ]]; then
  HISTORY_SECTION="## History

"
  if [[ -n "$PRIOR_HISTORY" ]]; then
    HISTORY_SECTION="${HISTORY_SECTION}${PRIOR_HISTORY}
"
  fi
  if [[ -n "$EXISTING_HISTORY" ]]; then
    HISTORY_SECTION="${HISTORY_SECTION}${EXISTING_HISTORY}
"
  fi
fi

# Direction emoji
case "$DIRECTION" in
  long) DIR_EMOJI="🟢 LONG" ;;
  short) DIR_EMOJI="🔴 SHORT" ;;
  neutral) DIR_EMOJI="⚪ NEUTRAL" ;;
  split) DIR_EMOJI="⚠️ SPLIT" ;;
  *) DIR_EMOJI="❓ $DIRECTION" ;;
esac

# Write thesis file
cat > "$THESIS_FILE" << EOF
---
ticker: ${TICKER}
updated_at: ${TIMESTAMP}
direction: ${DIRECTION}
conviction: ${CONVICTION}
horizon: ${HORIZON}
---

# ${TICKER} — ${DIR_EMOJI}

- **Direction:** ${DIR_EMOJI}
- **Conviction:** $(python3 -c "v=${CONVICTION}; print(f'{v:.0%}') if v else print('N/A')")
- **Horizon:** ${HORIZON}
- **Updated:** ${TIMESTAMP}

## Active Falsifiers

${FALSIFIERS}

EOF

if [[ -n "$DISSENT" ]]; then
  cat >> "$THESIS_FILE" << EOF
## Minority Positions

${DISSENT}

EOF
fi

if [[ -n "$HISTORY_SECTION" ]]; then
  echo "$HISTORY_SECTION" >> "$THESIS_FILE"
fi

echo "Thesis updated: $THESIS_FILE"
