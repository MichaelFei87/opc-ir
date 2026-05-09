#!/usr/bin/env bash
set -euo pipefail

# scheduler-dispatch.sh — routes scheduler commands to active backend
# Usage: scheduler-dispatch.sh <register|unregister|list|status|record-run> [args...]

OPC_IR_HOME="${OPC_IR_HOME:-$HOME/.opc-ir}"
SCHEDULER_DIR="$OPC_IR_HOME/scheduler"
BACKEND_FILE="$SCHEDULER_DIR/active-backend"

BACKEND=$(cat "$BACKEND_FILE" 2>/dev/null || echo "loop")

# Whitelist valid backends to prevent path injection
case "$BACKEND" in
  loop) ;;
  cron|launchd) echo "ERROR: backend '$BACKEND' is not yet implemented. Only 'loop' is currently supported." >&2; exit 1 ;;
  *) echo "ERROR: invalid backend '$BACKEND'. Must be one of: loop" >&2; exit 1 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/scheduler-${BACKEND}.sh" "$@"
