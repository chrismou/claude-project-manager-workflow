#!/usr/bin/env bash
# generate-readme-section.sh — regenerate the deny-list table in README.md
#
# Reads hooks/deny-list.json and replaces the content between
# <!-- deny-list-generated-start --> and <!-- deny-list-generated-end -->
# in README.md.
#
# Usage:
#   ./hooks/generate-readme-section.sh              # updates README.md in repo root
#   ./hooks/generate-readme-section.sh [readme]     # updates the specified file
#
# Returns exit code 1 if the markers are missing or jq / python3 is absent.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
DENY_LIST_FILE="${SCRIPT_DIR}/deny-list.json"
README_FILE="${1:-${SCRIPT_DIR}/../README.md}"
README_FILE="$(realpath "$README_FILE")"

# ── Pre-flight ─────────────────────────────────────────────────────────────────
if [ ! -f "$DENY_LIST_FILE" ]; then
    echo "Error: deny-list.json not found at $DENY_LIST_FILE" >&2
    exit 1
fi
if [ ! -f "$README_FILE" ]; then
    echo "Error: README not found at $README_FILE" >&2
    exit 1
fi
if ! command -v jq &>/dev/null; then
    echo "Error: jq is required" >&2
    exit 1
fi
if ! command -v python3 &>/dev/null; then
    echo "Error: python3 is required" >&2
    exit 1
fi

START_MARKER="<!-- deny-list-generated-start -->"
END_MARKER="<!-- deny-list-generated-end -->"

if ! grep -qF "$START_MARKER" "$README_FILE"; then
    echo "Error: '$START_MARKER' not found in $README_FILE" >&2
    exit 1
fi

# ── Build the markdown table ───────────────────────────────────────────────────
RULE_COUNT=$(jq '.rules | length' "$DENY_LIST_FILE")
TABLE="| Rule ID | Category | What it matches | Why |"$'\n'"| --- | --- | --- | --- |"

for i in $(seq 0 $((RULE_COUNT - 1))); do
    ID=$(       jq -r ".rules[$i].id"       "$DENY_LIST_FILE")
    CATEGORY=$( jq -r ".rules[$i].category" "$DENY_LIST_FILE")
    WHAT=$(     jq -r ".rules[$i].what"     "$DENY_LIST_FILE")
    WHY=$(      jq -r ".rules[$i].why"      "$DENY_LIST_FILE")
    TABLE="${TABLE}"$'\n'"| \`${ID}\` | ${CATEGORY} | ${WHAT} | ${WHY} |"
done

# ── Replace section in README using python3 ────────────────────────────────────
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT
printf '%s' "$TABLE" > "$TMPFILE"

python3 - "$README_FILE" "$TMPFILE" "$START_MARKER" "$END_MARKER" "$RULE_COUNT" <<'PYEOF'
import sys, re

readme_path, table_path, start, end, rule_count_str = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
rule_count = int(rule_count_str)

with open(readme_path) as f:
    content = f.read()

with open(table_path) as f:
    table = f.read().rstrip('\n')

new_section = start + '\n' + table + '\n' + end
pattern = re.compile(re.escape(start) + '.*?' + re.escape(end), re.DOTALL)
if not pattern.search(content):
    print(f"Error: markers not found in {readme_path}", file=sys.stderr)
    sys.exit(1)

new_content = pattern.sub(new_section, content)
with open(readme_path, 'w') as f:
    f.write(new_content)

print(f"Regenerated deny-list section in {readme_path} ({rule_count} rules).")
PYEOF
