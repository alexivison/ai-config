# Task 3 — Agent-Agnostic Layouts and Role-Based Pane Tags

**Dependencies:** Task 2
**Branch:** `feature/multi-agent-planning`

## Goal

Refactor the three layout functions (`launchClassic`, `launchSidebar`, `launchMaster`) to accept a role→command map instead of `codexCmd`/`claudeCmd` strings, and tag panes with role-based `@party_role` values (`"primary"`, `"companion"`) instead of agent names (`"claude"`, `"codex"`). Add backward-compat fallback in `ResolveRole()`.

## Scope Boundary

**In scope:**
- `tools/party-cli/internal/session/layout.go` — All three layout functions + `Resize()`
- `tools/party-cli/internal/tmux/query.go` — `ResolveRole()` backward-compat fallback
- `tools/party-cli/internal/tmux/client.go` — Replace `WindowCodex`/`WindowWorkspace` constants

**Out of scope:**
- TUI (Task 5)
- Messaging (Task 4)
- Promote (Task 6)

## Reference Files

### Layout functions (the files being refactored)

- `tools/party-cli/internal/session/layout.go` — **Read the entire file (222 lines).** Key sections:
  - Lines 32-70: `launchClassic()` — creates Codex pane (p0, role="codex"), Claude pane (p1, role="claude"), Shell pane (p2, role="shell"). Batch sets `@party_role`.
  - Lines 75-146: `launchSidebar()` — Window 0: Codex (role="codex"). Window 1: party-cli sidebar (role="sidebar"), Claude (role="claude"), Shell (role="shell").
  - Lines 148-185: `launchMaster()` — Tracker (role="tracker"), Claude (role="claude"), Shell (role="shell"). No Codex pane.
  - Lines 190-221: `Resize()` — finds panes by role ("sidebar", "tracker", "codex" for left pane, "shell" for right). Must accept new role names.

### Pane resolution

- `tools/party-cli/internal/tmux/query.go` — `ResolveRole()` function. Currently looks for exact `@party_role` match. Add fallback: if `"primary"` not found, try `"claude"`; if `"companion"` not found, try `"codex"`.
- `tools/party-cli/internal/tmux/client.go` lines 24-25 — `WindowCodex = 0`, `WindowWorkspace = 1` constants. These should become configurable or at minimum use role-agnostic names.

### Launch config (from Task 2)

- `tools/party-cli/internal/session/launch.go` — After Task 2, `launchConfig.agentCmds` is `map[agent.Role]string`. The `launchSession()` function passes the right commands to layout functions.

## Files to Create/Modify

| File | Action | Key Changes |
|------|--------|-------------|
| `tools/party-cli/internal/session/layout.go` | Modify | All three layouts accept role→command map; `@party_role` values change to `"primary"`, `"companion"` |
| `tools/party-cli/internal/session/launch.go` | Modify | `launchSession()` passes `agentCmds` map to layout functions |
| `tools/party-cli/internal/tmux/query.go` | Modify | `ResolveRole()` fallback: `"primary"` → `"claude"`, `"companion"` → `"codex"` |
| `tools/party-cli/internal/tmux/client.go` | Modify | Rename constants: `WindowCodex` → `WindowCompanion`, `WindowWorkspace` unchanged |

## Requirements

### Layout Function Signatures

Change from:
```go
func (s *Service) launchClassic(ctx context.Context, session, cwd, codexCmd, claudeCmd string) error
func (s *Service) launchSidebar(ctx context.Context, session, cwd, codexCmd, claudeCmd, title string, isWorker bool) error
func (s *Service) launchMaster(ctx context.Context, session, cwd, claudeCmd string) error
```

To:
```go
func (s *Service) launchClassic(ctx context.Context, session, cwd string, cmds map[agent.Role]string) error
func (s *Service) launchSidebar(ctx context.Context, session, cwd, title string, isWorker bool, cmds map[agent.Role]string) error
func (s *Service) launchMaster(ctx context.Context, session, cwd string, cmds map[agent.Role]string) error
```

### Classic Layout Changes

Current pane setup: `codexCmd` → p0 (role="codex"), `claudeCmd` → p1 (role="claude"), shell → p2 (role="shell").

New: `cmds[RoleCompanion]` → p0 (role="companion"), `cmds[RolePrimary]` → p1 (role="primary"), shell → p2 (role="shell").

If `cmds[RoleCompanion]` is empty (no companion configured), skip p0 and use a 2-pane layout: primary | shell.

### Sidebar Layout Changes

Current: Window 0 → Codex (role="codex"). Window 1 → sidebar (role="sidebar"), Claude (role="claude"), Shell (role="shell").

New: Window 0 → companion (role="companion"). Window 1 → tracker (role="tracker"), primary (role="primary"), Shell (role="shell").

**Note:** The sidebar pane (w1p0) in worker mode now gets role `"tracker"` instead of `"sidebar"`. This unifies the naming — both master and non-master sessions use the same TUI in their left pane (Task 5 makes them render the same unified tracker).

If no companion: skip Window 0 entirely. Only create Window 1 (the now-only window becomes index 0).

### Master Layout Changes

Current: Tracker (role="tracker"), Claude (role="claude"), Shell (role="shell").

New: Tracker (role="tracker"), primary (role="primary"), Shell (role="shell").

Master layout doesn't create a companion pane (unchanged behavior).

### Resize Changes

Current `Resize()` looks for left pane with role `"sidebar"`, `"tracker"`, or `"codex"`. Update to also accept `"companion"` and `"primary"` as left pane roles (the companion pane is the left pane in classic layout).

**No-companion edge case:** In a 2-pane layout (primary + shell only), there is no left pane to resize. `Resize()` should return a descriptive error like `"no left pane found (2-pane layout)"` or no-op gracefully. Do not error with the generic `"no left pane"` message — it should be clear that the layout simply doesn't have a left pane, not that something is broken.

### ResolveRole Fallback

In `tmux/query.go`, the `ResolveRole()` function searches for `@party_role` matching the given string. Add a fallback map:

```go
var roleFallbacks = map[string]string{
    "primary":   "claude",
    "companion": "codex",
}
```

If the exact role is not found, try the fallback before returning `ErrRoleNotFound`. This ensures old sessions (with `@party_role="claude"`) still work after the code update.

### Window Constant Rename

In `tmux/client.go`:
```go
const (
    WindowCompanion = 0  // was WindowCodex
    WindowWorkspace = 1  // unchanged
)
```

Update all references throughout the codebase (grep for `tmux.WindowCodex`).

## Tests

- Classic layout with both agents → 3 panes created with roles "companion", "primary", "shell"
- Classic layout with no companion → 2 panes: "primary", "shell"
- Sidebar layout with companion → Window 0 has "companion", Window 1 has "tracker", "primary", "shell"
- Sidebar layout with no companion → only one window with "tracker", "primary", "shell"
- Master layout → "tracker", "primary", "shell" (no companion pane)
- `ResolveRole("primary")` on a session with `@party_role="claude"` → returns the pane (fallback)
- `ResolveRole("companion")` on a session with `@party_role="codex"` → returns the pane (fallback)
- `Resize()` works with new role names

## Acceptance Criteria

- [x] All three layout functions accept role→command maps
- [x] `@party_role` values are `"primary"`, `"companion"`, `"tracker"`, `"shell"`
- [x] `ResolveRole()` has backward-compat fallback for old role names
- [x] `WindowCodex` renamed to `WindowCompanion`
- [x] No-companion layout works (2-pane or single-window)
- [x] All existing session and layout tests pass
