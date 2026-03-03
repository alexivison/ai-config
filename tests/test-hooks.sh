#!/usr/bin/env bash
# Canonical hook tests live in claude/hooks/tests.
# Keep this wrapper so top-level test runners and docs keep one entrypoint.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash "$REPO_ROOT/claude/hooks/tests/run-all.sh"
