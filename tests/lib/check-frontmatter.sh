#!/usr/bin/env bash
set -euo pipefail

# check-frontmatter.sh — Validate YAML frontmatter in a markdown file
# Usage: check-frontmatter.sh <file.md> [required-key ...]
# Exit 0 = valid, Exit 1 = invalid

FILE="${1:?Usage: check-frontmatter.sh <file.md> [required-key ...]}"
shift

if [[ ! -f "$FILE" ]]; then
  echo "Error: file not found: $FILE" >&2
  exit 1
fi

# Extract frontmatter between first pair of ---
# macOS sed compatible: read between first two --- lines
FRONTMATTER=$(awk 'BEGIN{c=0} /^---$/{c++;next} c==1{print} c>=2{exit}' "$FILE")

if [[ -z "$FRONTMATTER" ]]; then
  echo "Error: no YAML frontmatter found in $FILE" >&2
  exit 1
fi

# Validate YAML
echo "$FRONTMATTER" | yq '.' > /dev/null 2>&1 || {
  echo "Error: invalid YAML frontmatter in $FILE" >&2
  exit 1
}

# Check required keys
for key in "$@"; do
  VALUE=$(echo "$FRONTMATTER" | yq ".$key" 2>/dev/null)
  if [[ -z "$VALUE" || "$VALUE" == "null" ]]; then
    echo "Error: required key '$key' missing in frontmatter of $FILE" >&2
    exit 1
  fi
done

echo "OK: $FILE"
