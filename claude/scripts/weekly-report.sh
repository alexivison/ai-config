#!/bin/bash
# Weekly report of Claude Code activity
# Collects investigations, logs, and session summaries

set -e

CLAUDE_DIR="$HOME/.claude"
REPORTS_DIR="$HOME/Documents/Claude-Reports"
WEEK=$(date +%Y-W%V)
EXPORT_DIR="$REPORTS_DIR/$WEEK"

# Create export directory
mkdir -p "$EXPORT_DIR"

# Date range for this week (last 7 days)
SINCE=$(date -v-7d +%Y-%m-%d 2>/dev/null || date -d '7 days ago' +%Y-%m-%d)
TODAY=$(date +%Y-%m-%d)

echo "Generating weekly report: $SINCE to $TODAY"
echo "Output: $EXPORT_DIR"

# Copy recent investigations
if [ -d "$CLAUDE_DIR/investigations" ]; then
  find "$CLAUDE_DIR/investigations" -type f -mtime -7 -exec cp {} "$EXPORT_DIR/" \; 2>/dev/null
  echo "  - Investigations: copied recent files"
fi

# Copy recent log analyses
if [ -d "$CLAUDE_DIR/logs" ]; then
  find "$CLAUDE_DIR/logs" -type f -mtime -7 -exec cp {} "$EXPORT_DIR/" \; 2>/dev/null
  echo "  - Logs: copied recent files"
fi

# Create summary document
SUMMARY="$EXPORT_DIR/SUMMARY.md"
cat > "$SUMMARY" << EOF
# Weekly Report: $WEEK

**Period:** $SINCE to $TODAY
**Generated:** $(date +%Y-%m-%d\ %H:%M)

## Investigations

EOF

# List investigation files
if ls "$EXPORT_DIR"/*.md 1>/dev/null 2>&1; then
  for f in "$EXPORT_DIR"/*.md; do
    [ "$(basename "$f")" = "SUMMARY.md" ] && continue
    BASENAME=$(basename "$f")
    TITLE=$(grep -m1 "^#" "$f" 2>/dev/null | sed 's/^#* *//' || echo "$BASENAME")
    echo "- [$TITLE]($BASENAME)" >> "$SUMMARY"
  done
else
  echo "_No investigations this week_" >> "$SUMMARY"
fi

cat >> "$SUMMARY" << EOF

## Session Stats

EOF

if [ -f "$CLAUDE_DIR/history.jsonl" ]; then
  TOTAL_LINES=$(wc -l < "$CLAUDE_DIR/history.jsonl" | tr -d ' ')
  echo "- Total history entries: $TOTAL_LINES" >> "$SUMMARY"
fi

# List projects worked on
if [ -d "$CLAUDE_DIR/projects" ]; then
  echo "" >> "$SUMMARY"
  echo "## Projects" >> "$SUMMARY"
  echo "" >> "$SUMMARY"

  # Build pattern from $HOME to strip user-specific prefix
  # e.g., /Users/john -> -Users-john- (escaped path format)
  HOME_PATTERN=$(echo "$HOME" | sed 's/\//-/g')

  find "$CLAUDE_DIR/projects" -mindepth 1 -maxdepth 1 -type d -mtime -7 -exec basename {} \; 2>/dev/null | while read -r proj; do
    # Handle .claude config folder specially
    if echo "$proj" | grep -q -- '--claude$'; then
      echo "- .claude (config)" >> "$SUMMARY"
      continue
    fi

    # Strip home directory prefix and common code directories
    # e.g., "-Users-john-Code-myproject" -> "myproject"
    clean_name=$(echo "$proj" | sed "s/^${HOME_PATTERN}-//" | sed 's/^Code-//' | sed 's/^-//')

    # Skip if still looks like a raw path, common dirs, or empty
    case "$clean_name" in
      ""|Users-*|Home-*|Code) continue ;;
    esac
    echo "- $clean_name" >> "$SUMMARY"
  done
fi

echo ""
echo "Done. Summary: $SUMMARY"
