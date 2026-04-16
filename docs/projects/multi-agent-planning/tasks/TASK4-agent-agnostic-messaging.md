# Task 4 — Agent-Agnostic Messaging

**Dependencies:** Task 3
**Branch:** `feature/multi-agent-planning`

## Goal

Refactor all messaging functions (`Relay`, `Broadcast`, `Read`, `Report`) and the existing shell transport layer to resolve panes by role instead of hardcoded `"claude"` / `"codex"`. Update the `tmux.CodexTarget()` function and `tmux.FilterWizardLines()` to be role-agnostic.

## Scope Boundary

**In scope:**
- `tools/party-cli/internal/message/message.go` — All messaging functions
- `tools/party-cli/internal/tmux/popup.go` — Rename `CodexTarget()` → `CompanionTarget()`
- `tools/party-cli/internal/tmux/query.go` — Rename `FilterWizardLines()` if applicable
- `session/party-lib.sh` — Role-resolution helper fallback for `primary` / `companion`
- `session/party-relay.sh` — Companion relay helper still works after role-tag migration
- `claude/skills/codex-transport/scripts/tmux-codex.sh` — Resolve the companion pane by role internally
- `codex/skills/claude-transport/scripts/tmux-claude.sh` — Resolve the primary pane by role internally

**Out of scope:**
- TUI changes (Task 5)
- Porting the shell transport layer to Go (the scripts remain shell-based)

**Additional call sites outside `message.go`** — also grep for `"claude"` in `ResolveRole` calls in:
- `tools/party-cli/internal/picker/picker.go` (~line 232) — resolves Claude pane for preview. Change to `"primary"`.
- `tools/party-cli/internal/tui/tracker_actions.go` (~line 168) — resolves Claude pane for snippet capture. This is Task 5 scope, but verify it's covered there.

## Reference Files

### Messaging (the main file being refactored)

- `tools/party-cli/internal/message/message.go` — **Read the entire file (244 lines).** Every function that resolves a pane does it via:
  ```go
  target, err := s.client.ResolveRole(ctx, workerID, "claude", tmux.WindowWorkspace)
  ```
  This `"claude"` string is hardcoded in 4 places:
  - `Relay()` — master → worker's primary pane (line ~47)
  - `Broadcast()` — master → all workers' primary panes (line ~96)
  - `Read()` — capture worker's primary pane (line ~105)
  - `Report()` — worker → master's primary pane (line ~127)

  Note: `Workers()` does NOT call `ResolveRole` — it checks session liveness only.

### tmux helpers

- `tools/party-cli/internal/tmux/popup.go` — `CodexTarget()` function returns `fmt.Sprintf("%s:0.0", sessionID)` — hardcoded to window 0, pane 0. Used by TUI for companion pane operations.
- `tools/party-cli/internal/tmux/query.go` — `FilterWizardLines()` filters pane capture output. The name is agent-specific but the logic is generic (filters empty lines and ANSI sequences). Rename for clarity.
- `tools/party-cli/internal/tmux/client.go` — After Task 3, `WindowCompanion = 0` (was `WindowCodex`).

### Message service

- `tools/party-cli/internal/message/message.go` lines 12-17 — `Service` struct with `store` and `client`. The service currently has no knowledge of agent roles. It needs to know the primary role's `@party_role` name (always `"primary"` after Task 3, but using the role constant is cleaner).

### Shell transport helpers

- `session/party-lib.sh` — `party_role_pane_target()` currently matches the requested role exactly, and `party_codex_pane_target()` hardcodes `"codex"`. After Task 3 changes pane tags to `"primary"` / `"companion"`, the shell helper needs the same backward-compat fallback map as Go `ResolveRole()`.
- `session/party-relay.sh` — `--wizard` currently resolves the companion pane through `party_codex_pane_target()`. Keep the CLI surface for backward compatibility, but route internally through the role-based helper.
- `codex/skills/claude-transport/scripts/tmux-claude.sh` — currently resolves `party_role_pane_target "$SESSION_NAME" "claude"` and prefixes outbound messages with `[CODEX]`. Update it to target the primary role internally and emit the role-based prefix for new sessions.
- `claude/skills/codex-transport/scripts/tmux-codex.sh` — mirror the same change on the Claude→companion path: resolve the companion role internally and emit the role-based prefix for new sessions.

## Files to Create/Modify

| File | Action | Key Changes |
|------|--------|-------------|
| `tools/party-cli/internal/message/message.go` | Modify | Replace all `"claude"` in `ResolveRole()` calls with `"primary"` |
| `tools/party-cli/internal/tmux/popup.go` | Modify | Rename `CodexTarget()` → `CompanionTarget()` |
| `tools/party-cli/internal/tmux/query.go` | Modify | Rename `FilterWizardLines()` → `FilterAgentLines()` (optional, low priority) |
| `session/party-lib.sh` | Modify | Add shell-side fallback for `primary` / `companion`; keep old helper names as wrappers |
| `session/party-relay.sh` | Modify | Continue supporting `--wizard`, but target the companion role internally |
| `claude/skills/codex-transport/scripts/tmux-codex.sh` | Modify | Resolve companion pane by role; keep filename for backward compatibility |
| `codex/skills/claude-transport/scripts/tmux-claude.sh` | Modify | Resolve primary pane by role; keep filename for backward compatibility |

## Requirements

### Messaging Changes

Every `ResolveRole(ctx, sessionID, "claude", tmux.WindowWorkspace)` call changes to:

```go
ResolveRole(ctx, sessionID, "primary", tmux.WindowWorkspace)
```

This is a straightforward string replacement in 5 call sites. The `ResolveRole()` fallback from Task 3 ensures this works with both old sessions (tagged `"claude"`) and new sessions (tagged `"primary"`).

The message prefixes (`[MASTER]`, `[WORKER:id]`) are unchanged — they're role-based already.

### Shell Transport Compatibility

The role-tag migration in Task 3 changes pane metadata from `claude` / `codex` to `primary` / `companion`. The shell transport layer must be updated in the same task slice or the default review workflow breaks immediately.

Required behavior:

- `party_role_pane_target()` accepts `primary` / `companion` and falls back to `claude` / `codex` for existing sessions
- `party_codex_pane_target()` becomes a thin backward-compatible wrapper around a new role-based companion helper (or is renamed with a wrapper kept in place)
- `tmux-claude.sh` targets the primary role internally instead of hardcoding `"claude"`
- `tmux-codex.sh` targets the companion role internally instead of hardcoding `"codex"`
- Script filenames stay unchanged in v1; only their internal routing and message prefixes become role-based

Do **not** rename runtime artifacts here. The existing `codex-thread-id`, `codex-status.json`, and related status plumbing stay on their current filenames in v1 for backward compatibility.

### CompanionTarget()

Rename `CodexTarget(sessionID)` to `CompanionTarget(sessionID)`. The function body stays the same (returns `"{session}:0.0"` — companion is always window 0, pane 0). Update all callers.

Callers of `CodexTarget()` (grep the codebase):
- `tools/party-cli/internal/tui/model.go` — used for sending messages to Wizard, checking Codex pane alive. These callers move to Task 5 (TUI refactor), but the rename should happen here so Task 5 doesn't reference the old name.

### FilterWizardLines() rename

Optional cosmetic rename to `FilterAgentLines()`. The function at `tmux/query.go` filters pane output generically — it doesn't have Wizard/Codex-specific logic. Low priority; skip if it creates too many test changes.

## Tests

- `Relay()` with new session (role="primary" on pane) → message delivered
- `Relay()` with old session (role="claude" on pane) → message delivered (via ResolveRole fallback)
- `Broadcast()` delivers to all workers' primary panes
- `Read()` captures from worker's primary pane
- `Report()` delivers to master's primary pane
- `CompanionTarget()` returns correct target string
- `party_role_pane_target primary` resolves a pane tagged `primary` and still falls back to `claude`
- `party_role_pane_target companion` resolves a pane tagged `companion` and still falls back to `codex`
- `tmux-claude.sh` delivers to a pane tagged `primary`
- `tmux-codex.sh` delivers to a pane tagged `companion`
- All existing message tests pass (update the mock pane role from "claude" to "primary" in test fixtures)

## Acceptance Criteria

- [x] No `"claude"` string appears in `message/message.go` role resolution
- [x] `CodexTarget()` renamed to `CompanionTarget()`
- [x] All messaging functions resolve `"primary"` role
- [x] Shell transport helpers/scripts work with `@party_role="primary"` / `"companion"` and still tolerate legacy sessions
- [x] All existing message tests pass
