# Task 7 — Generalize Hooks

**Dependencies:** Task 1
**Branch:** `feature/multi-agent-planning`

## Goal

Rename and parameterize shell hooks to be companion-agnostic. Make `pr-gate.sh` config-driven for evidence requirements. All hooks consume `party-cli agent query` (from Task 1) instead of hardcoding Codex/Wizard names.

## Scope Boundary

**In scope:**
- `claude/hooks/codex-gate.sh` → `claude/hooks/companion-gate.sh`
- `claude/hooks/codex-trace.sh` → `claude/hooks/companion-trace.sh`
- `claude/hooks/wizard-guard.sh` → `claude/hooks/companion-guard.sh`
- `claude/hooks/claude-state.sh` → `claude/hooks/primary-state.sh`
- `claude/hooks/pr-gate.sh` — Config-driven evidence requirements
- Symlinks at old paths for transition period
- Update hook test files

**Out of scope:**
- `claude/settings.json` updates (Task 8 — so the old paths still work during development)
- Transport role-resolution changes (Task 4 handles those; this task only needs to keep matching the existing transport filenames/CLI surface)
- TUI (Task 5)

## Reference Files

### Hooks being renamed

- `claude/hooks/codex-gate.sh` — **Read the entire file (50 lines).** Gates `tmux-codex.sh --approve`. The rename changes: (1) match pattern from `tmux-codex.sh` to the companion transport command, (2) use `party-cli agent query companion-name` to resolve the companion name dynamically.
- `claude/hooks/codex-trace.sh` — PostToolUse hook that traces Codex interactions. Records evidence with type "codex". After rename: evidence type = companion name from config.
- `claude/hooks/wizard-guard.sh` — **Read the entire file.** Blocks direct tmux commands targeting Codex/Wizard panes (enforces use of transport script). After rename: queries `party-cli agent query roles` to discover companion role names.
- `claude/hooks/claude-state.sh` — Tracks Claude's lifecycle events, writes `claude-state.json`. After rename: the hook filename changes, but the output artifact stays `claude-state.json` in v1.
- `claude/hooks/pr-gate.sh` — **Read the entire file (lines relevant to evidence).** Currently hardcodes required evidence types. After change: calls `party-cli agent query evidence-required` to get the list dynamically.

### Hook library

- `claude/hooks/lib/evidence.sh` — `append_evidence()` already accepts agent type as a string parameter. Keep the evidence file path on `/tmp/claude-evidence-*` in v1; do not rename the artifact in this task.
- `claude/hooks/register-agent-id.sh` — Keep writing `claude-session-id` / `claude_session_id` in v1. This task only renames the hook filename, not the persisted artifact names.
- `claude/hooks/session-cleanup.sh` — Still cleans up `claude-evidence-*` files in v1. No change required unless artifact names change in a future project.

### Hook tests

- `claude/hooks/tests/test-codex-gate.sh` — Tests for the gate hook. Must be updated for new file name and behavior.
- `claude/hooks/tests/test-codex-trace.sh` — Tests for the trace hook.

### party-cli agent query (from Task 1)

- `tools/party-cli/cmd/agent.go` — The bridge subcommand. Hooks call this to get companion name, role names, evidence requirements without parsing TOML themselves.

## Files to Create/Modify

| File | Action | Key Changes |
|------|--------|-------------|
| `claude/hooks/companion-gate.sh` | Create (copy+modify from `codex-gate.sh`) | Match companion transport command by name; use `party-cli agent query` |
| `claude/hooks/companion-trace.sh` | Create (copy+modify from `codex-trace.sh`) | Evidence type = companion name from config |
| `claude/hooks/companion-guard.sh` | Create (copy+modify from `wizard-guard.sh`) | Query roles dynamically |
| `claude/hooks/primary-state.sh` | Create (copy+modify from `claude-state.sh`) | Hook name becomes role-based; output stays `claude-state.json` |
| `claude/hooks/pr-gate.sh` | Modify | Call `party-cli agent query evidence-required` |
| `claude/hooks/codex-gate.sh` | Replace with symlink → `companion-gate.sh` |
| `claude/hooks/codex-trace.sh` | Replace with symlink → `companion-trace.sh` |
| `claude/hooks/wizard-guard.sh` | Replace with symlink → `companion-guard.sh` |
| `claude/hooks/claude-state.sh` | Replace with symlink → `primary-state.sh` |
| `claude/hooks/tests/test-codex-gate.sh` | Modify | Update for new hook name/behavior |
| `claude/hooks/tests/test-codex-trace.sh` | Modify | Update for new hook name/behavior |
| `claude/hooks/tests/test-claude-state.sh` | Modify | Update for renamed `primary-state.sh` |
| `claude/hooks/tests/run-all.sh` | Modify | Update test file references |

## Requirements

### companion-gate.sh

Current `codex-gate.sh` matches `tmux-codex\.sh` in the command string. The new version:

1. Calls `party-cli agent query companion-name` to get the companion name
2. If no companion configured → allow all commands (no gating needed)
3. Matches the companion transport script pattern in the command
4. Blocks `--approve` for any companion (not just Codex)

Key pattern change:
```bash
# Before:
if echo "$COMMAND" | grep -qE 'tmux-codex\.sh +--approve'; then

# After:
COMPANION_NAME=$(party-cli agent query companion-name 2>/dev/null || echo "")
if [ -z "$COMPANION_NAME" ]; then
  echo '{}'; exit 0  # No companion configured, nothing to gate
fi
if echo "$COMMAND" | grep -qE "(tmux-codex|party-cli +transport).*--approve"; then
```

### companion-trace.sh

Current `codex-trace.sh` records evidence with type "codex". The new version uses the companion name from config as the evidence type:

```bash
COMPANION_NAME=$(party-cli agent query companion-name 2>/dev/null || echo "codex")
append_evidence "$SESSION_ID" "$COMPANION_NAME" "$VERDICT" "$FINDINGS_FILE"
```

### companion-guard.sh

Current `wizard-guard.sh` blocks raw `tmux send-keys` targeting Codex/Wizard patterns. The new version:

```bash
COMPANION_ROLES=$(party-cli agent query roles 2>/dev/null || echo "companion")
# Build regex from roles
ROLE_PATTERN=$(echo "$COMPANION_ROLES" | tr '\n' '|' | sed 's/|$//')
# Match tmux commands targeting companion pane roles
```

### primary-state.sh

Current `claude-state.sh` writes `claude-state.json`. Keep that output file in v1; only the hook filename changes:

```bash
STATE_FILE="$RUNTIME_DIR/claude-state.json"
```

Do **not** rename `claude-session-id`, `claude_session_id`, or `/tmp/claude-evidence-*` in this task. Those artifacts are consumed by `register-agent-id.sh`, `lib/evidence.sh`, `session-cleanup.sh`, TUI readers, and reporting scripts, and they only exist when Claude is primary anyway.

### pr-gate.sh Changes

Current hardcodes: `REQUIRED="pr-verified code-critic minimizer codex test-runner check-runner"`.

New: calls `party-cli agent query evidence-required`:

```bash
REQUIRED=$(party-cli agent query evidence-required 2>/dev/null)
if [ -z "$REQUIRED" ]; then
  # Fallback to default
  REQUIRED="pr-verified code-critic minimizer codex test-runner check-runner"
fi
```

### Symlinks

Replace original files with symlinks so any existing references (settings.json, scripts) continue to work:

```bash
ln -sf companion-gate.sh claude/hooks/codex-gate.sh
ln -sf companion-trace.sh claude/hooks/codex-trace.sh
ln -sf companion-guard.sh claude/hooks/wizard-guard.sh
ln -sf primary-state.sh claude/hooks/claude-state.sh
```

## Tests

- companion-gate blocks `--approve` when companion is configured
- companion-gate allows all commands when no companion configured
- companion-trace records evidence with companion name as type
- companion-guard blocks raw tmux to companion roles
- primary-state still writes `claude-state.json`
- pr-gate reads evidence requirements from `party-cli agent query`
- Symlinks at old paths work

## Acceptance Criteria

- [x] Four new hook files created with role-based logic
- [x] Old hook files replaced with symlinks
- [x] Hooks use `party-cli agent query` for dynamic resolution
- [x] `pr-gate.sh` reads evidence requirements from config
- [x] Runtime artifact names stay unchanged in v1 (`claude-state.json`, `claude-session-id`, `/tmp/claude-evidence-*`)
- [x] All hook tests updated and passing
- [x] Hooks fail open gracefully when `party-cli` is not available
