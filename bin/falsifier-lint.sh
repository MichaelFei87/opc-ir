#!/usr/bin/env bash
set -euo pipefail

# falsifier-lint.sh — Same specificity check as invalidator-lint, for verdict falsifiers
# Usage: falsifier-lint.sh <text-or-file> [--retry-counter <file>]
# Exit 0 = passes; Exit 1 = fails
# With --retry-counter: increments counter in file, exits 2 if counter >= 2

TEXT="${1:?Usage: falsifier-lint.sh <text-or-file> [--retry-counter <file>]}"
RETRY_COUNTER=""

shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --retry-counter)
      RETRY_COUNTER="${2:?--retry-counter requires a file path}"
      shift 2
      ;;
    *)
      echo "Unknown flag: $1" >&2
      exit 1
      ;;
  esac
done

# If file, read contents
if [[ -f "$TEXT" ]]; then
  TEXT=$(cat "$TEXT")
fi

# Reuse invalidator-lint logic
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! "$SCRIPT_DIR/invalidator-lint.sh" "$TEXT" 2>&1; then
  # Lint failed
  if [[ -n "$RETRY_COUNTER" ]]; then
    # Increment retry counter
    if [[ -f "$RETRY_COUNTER" ]]; then
      COUNT=$(cat "$RETRY_COUNTER")
    else
      COUNT=0
    fi
    COUNT=$((COUNT + 1))
    echo "$COUNT" > "$RETRY_COUNTER"

    if [[ "$COUNT" -ge 2 ]]; then
      echo "FATAL: Falsifier lint failed after $COUNT retries (max 2)" >&2
      exit 2
    fi
    echo "Retry $COUNT/2 — falsifier must meet specificity requirements" >&2
  fi
  exit 1
fi
exit 0
