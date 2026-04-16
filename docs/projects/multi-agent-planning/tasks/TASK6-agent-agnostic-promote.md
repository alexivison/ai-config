# Task 6 — Agent-Agnostic Promote

**Dependencies:** Task 3
**Branch:** `feature/multi-agent-planning`

## Goal

Refactor `promote.go` to use role-based pane resolution and agent-agnostic master mode. The promote operation converts a session to master by replacing the companion pane (or sidebar pane) with the tracker and injecting master orchestration instructions via the primary agent's `MasterPrompt()`.

## Scope Boundary

**In scope:**
- `tools/party-cli/internal/session/promote.go` — Use role-based resolution, agent-agnostic master mode

**Out of scope:**
- TUI (Task 5)
- Hooks (Task 7)

## Reference Files

- `tools/party-cli/internal/session/promote.go` — **Read the entire file (112 lines).** Key sections:
  - Lines 14-75: `Promote()` — reads manifest, resolves layout, updates manifest to master, clears `codex_thread_id` extra and `CODEX_THREAD_ID` env var. Must generalize: clear ALL companion resume IDs and env vars (iterate `manifest.Agents[]` for companion role entries).
  - Lines 52-53: `WindowCodex` constant — now `WindowCompanion` from Task 3
  - Lines 77-91: `promoteClassic()` — resolves pane by role `"codex"` → change to `"companion"`. Respawns with tracker CLI.
  - Lines 93-111: `promoteSidebar()` — replaces sidebar pane (w1p0) with tracker, kills companion window 0. The window 0 kill uses `tmux.WindowCodex` → now `tmux.WindowCompanion`.

## Files to Create/Modify

| File | Action | Key Changes |
|------|--------|-------------|
| `tools/party-cli/internal/session/promote.go` | Modify | Role-based resolution; clear companion from `manifest.Agents[]`; use `WindowCompanion` |

## Requirements

### promoteClassic Changes

```go
// Before:
codexPane, err := s.Client.ResolveRole(ctx, sessionID, "codex", -1)

// After:
companionPane, err := s.Client.ResolveRole(ctx, sessionID, "companion", -1)
```

The `ResolveRole()` fallback from Task 3 handles old sessions with `@party_role="codex"`.

### promoteSidebar Changes

```go
// Before:
codexWindow := fmt.Sprintf("%s:%d", sessionID, tmux.WindowCodex)

// After:
companionWindow := fmt.Sprintf("%s:%d", sessionID, tmux.WindowCompanion)
```

### Manifest Cleanup

Current: deletes `codex_thread_id` from extras and unsets `CODEX_THREAD_ID` env var.

New: iterate `manifest.Agents[]` and remove companion entries. For each removed agent, unset its env var:

```go
s.Store.Update(sessionID, func(m *state.Manifest) {
    m.SessionType = "master"
    m.WindowName = newWinName
    // Remove companion agents
    var kept []state.AgentManifest
    for _, a := range m.Agents {
        if a.Role != "companion" {
            kept = append(kept, a)
        }
    }
    m.Agents = kept
    // Also clean old-format extras for backward compat
    delete(m.Extra, "codex_thread_id")
})

// Unset companion env vars
for _, a := range removedAgents {
    _ = s.Client.UnsetEnvironment(ctx, sessionID, a.EnvVar)
}
```

## Tests

- Promote classic session → companion pane replaced with tracker, role changed to "tracker"
- Promote sidebar session → sidebar pane replaced with tracker, companion window killed
- Promote updates `manifest.Agents[]` to remove companion entries
- Promote clears companion env vars
- Promote already-master → no-op (idempotent)
- Old session with `@party_role="codex"` → fallback resolves, promote works

## Acceptance Criteria

- [x] `promoteClassic()` resolves `"companion"` role (not `"codex"`)
- [x] `promoteSidebar()` uses `WindowCompanion` (not `WindowCodex`)
- [x] Manifest cleanup removes companion from `Agents[]`
- [x] Old-format extras (`codex_thread_id`) also cleaned for backward compat
- [x] All existing promote tests pass
