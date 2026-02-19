#!/usr/bin/env bash
set -euo pipefail

VERDICT="${1:?Usage: codex-verdict.sh approve|request_changes|needs_discussion}"
case "$(echo "$VERDICT" | tr '[:upper:]' '[:lower:]')" in
  approve)           echo "CODEX APPROVED" ;;
  request_changes)   echo "CODEX REQUEST_CHANGES" ;;
  needs_discussion)  echo "CODEX NEEDS_DISCUSSION" ;;
  *) echo "Error: Unknown verdict '$VERDICT'" >&2; exit 1 ;;
esac
