#!/usr/bin/env bash
set -euo pipefail

# integrity.sh — plugin file integrity management
# Usage: integrity.sh <lock|verify>

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPC_IR_HOME="${OPC_IR_HOME:-$HOME/.opc-ir}"
LOCK_DIR="$OPC_IR_HOME"
LOCK_FILE="$LOCK_DIR/install.lock"

generate_manifest() {
  find "$PLUGIN_ROOT" \
    -type f \
    ! -path "*/.git/*" \
    ! -path "*/docs/*" \
    ! -path "*/.harness/*" \
    ! -path "*/.claude/*" \
    ! -name "*.log" \
    ! -name ".DS_Store" \
    | LC_ALL=C sort \
    | while read -r file; do
        RELPATH="${file#$PLUGIN_ROOT/}"
        # Use python for portable SHA256 (macOS has shasum, Linux has sha256sum)
        HASH=$(python3 -c "
import hashlib, sys
with open(sys.argv[1], 'rb') as f:
    print(hashlib.sha256(f.read()).hexdigest())
" "$file")
        echo "$HASH  $RELPATH"
      done
}

case "${1:-help}" in
  lock)
    mkdir -p "$LOCK_DIR"
    MANIFEST=$(generate_manifest)
    MASTER_HASH=$(echo "$MANIFEST" | python3 -c "
import hashlib, sys
print(hashlib.sha256(sys.stdin.read().encode()).hexdigest())
")
    NOW_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    FILE_COUNT=$(echo "$MANIFEST" | wc -l | tr -d ' ')

    cat > "$LOCK_FILE" << EOF
{"locked_at":"$NOW_ISO","plugin_root":"$PLUGIN_ROOT","master_hash":"$MASTER_HASH","file_count":$FILE_COUNT}
EOF

    echo "$MANIFEST" > "$LOCK_DIR/install.manifest"

    echo "Install lock created: $LOCK_FILE"
    echo "Master hash: ${MASTER_HASH:0:12}..."
    echo "Files locked: $FILE_COUNT"
    ;;

  verify)
    if [[ ! -f "$LOCK_FILE" ]]; then
      echo "NO LOCK: install.lock not found. Run 'bin/integrity.sh lock' after install."
      exit 1
    fi

    if [[ ! -f "$LOCK_DIR/install.manifest" ]]; then
      echo "NO MANIFEST: install.manifest not found. Re-run 'bin/integrity.sh lock'."
      exit 1
    fi

    EXPECTED_MASTER=$(jq -r '.master_hash' "$LOCK_FILE")
    CURRENT_MANIFEST=$(generate_manifest)
    CURRENT_MASTER=$(echo "$CURRENT_MANIFEST" | python3 -c "
import hashlib, sys
print(hashlib.sha256(sys.stdin.read().encode()).hexdigest())
")

    if [[ "$EXPECTED_MASTER" = "$CURRENT_MASTER" ]]; then
      echo "INTEGRITY OK: all plugin files match install lock."
      echo "Master hash: ${CURRENT_MASTER:0:12}..."
      exit 0
    fi

    echo "INTEGRITY MISMATCH: plugin files have changed since install."
    echo "Expected: ${EXPECTED_MASTER:0:12}..."
    echo "Current:  ${CURRENT_MASTER:0:12}..."
    echo ""
    echo "=== Changed files ==="
    diff <(sort "$LOCK_DIR/install.manifest") <(echo "$CURRENT_MANIFEST" | sort) | \
      grep "^[<>]" | sed 's/^< /REMOVED: /; s/^> /ADDED\/MODIFIED: /' | head -20 || true

    echo ""
    echo "Run 'bin/integrity.sh lock' to update the install lock."
    exit 2
    ;;

  *)
    echo "Usage: integrity.sh <lock|verify>"
    exit 1
    ;;
esac
