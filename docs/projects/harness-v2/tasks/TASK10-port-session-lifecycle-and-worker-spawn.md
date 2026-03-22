# Task 10 — Port Session Lifecycle And Worker Spawn

**Dependencies:** Task 8, Task 9 | **Issue:** TBD

---

## Goal

Port the mutating session lifecycle to Go: create, continue, stop, delete, promote, and spawn workers. After this task, the main session topology should be controllable through `party-cli`, even if shell wrappers still exist.

## Scope Boundary (REQUIRED)

**In scope:**
- Add `start`, `continue`, `stop`, `delete`, and `promote` subcommands
- Port worker-spawn flow for masters into the unified binary
- Reuse shared state, tmux, and TUI launch contracts
- Keep shell entrypoints working as coexistence wrappers

**Out of scope (handled by other tasks):**
- Relay, broadcast, read, or report-back behavior
- Final worker sidebar widgets and master tracker actions
- Final wrapper retirement

**Cross-task consistency check:**
- Worker spawning here must produce session layouts and hidden-window behavior compatible with Task 9
- Later tracker actions in Task 13 should call the same lifecycle services defined here rather than invent local spawn logic

## Reference

Files to study before implementing:

- `session/party.sh` — start, continue, stop, delete flows
- `session/party-master.sh` — promote and master launch behavior
- `tools/party-cli/internal/state/*` — manifest persistence
- `tools/party-cli/internal/tmux/*` — tmux layout and routing helpers

## Design References (REQUIRED for UI/component tasks)

- `../diagrams/end-state-architecture.svg`
- `../diagrams/session-layouts.svg`

## Data Transformation Checklist (REQUIRED for shape changes)

- [ ] Proto definition (N/A unless a typed file contract is introduced)
- [ ] Proto -> Domain converter (N/A unless a typed file contract is introduced)
- [ ] Domain model struct
- [ ] Params struct(s) — check ALL variants
- [ ] Params conversion functions
- [ ] Any adapters between param types

## Files to Create/Modify

| File | Action |
|------|--------|
| `tools/party-cli/cmd/start.go` | Create |
| `tools/party-cli/cmd/continue.go` | Create |
| `tools/party-cli/cmd/stop.go` | Create |
| `tools/party-cli/cmd/delete.go` | Create |
| `tools/party-cli/cmd/promote.go` | Create |
| `tools/party-cli/cmd/spawn.go` | Create |
| `tools/party-cli/internal/session/*` | Create or modify |
| `tools/party-cli/internal/session/*_test.go` | Create |
| `session/party.sh` | Modify if wrapper delegation is added incrementally |
| `session/party-master.sh` | Modify if wrapper delegation is added incrementally |

## Requirements

**Functionality:**
- Lifecycle commands preserve current master/worker semantics
- Worker spawn creates the same pane/layout contracts expected by sidebar mode
- Commands return explicit failures instead of silent partial work
- Bash entrypoints may delegate, but live behavior must now be owned by Go services

**Key gotchas:**
- Promotion must correctly replace worker or standalone layout with master tracker layout
- Resume/continue behavior should preserve existing Claude and Codex resume semantics
- **Promotion with sidebar mode (blocking, deferred from Task 9):** The current shell promotion path (`session/party-master.sh:126-133`) resolves a visible `codex` role pane and respawns the tracker into it. In sidebar mode there is no visible Codex pane — Codex runs in hidden window 0. Promotion in sidebar mode MUST: (1) replace the sidebar pane (window 1, pane `0`) with the tracker view, (2) window 0 remains as-is (Codex stays available for the promoted master), (3) update the manifest `session_type` to `master`, (4) handle the case where classic-layout sessions are promoted (no hidden window to manage). Note: direct master launches have no window 0; promoted masters retain it from their worker/standalone origin. Both layout modes must produce functional post-promotion master state. Test both paths.

## Tests

Test cases:
- Start/continue flows for standalone, worker, and master sessions
- Stop/delete cleanup with sidebar hidden windows present
- Promote flow from worker or standalone to master (classic layout)
- Promote flow from worker or standalone to master (sidebar layout — window 0 remains, pane replacement in window 1)
- Promote idempotency: promoting an already-master session is a no-op
- Worker spawn from a master session

## Acceptance Criteria

- [x] `party-cli` owns lifecycle commands and worker spawn behavior
- [x] Session creation and teardown preserve current layout semantics
- [x] Promotion works in both classic and sidebar layout modes
- [x] Sidebar promotion replaces sidebar pane (window 1) with tracker; window 0 (Codex) remains
- [x] Shell entrypoints can coexist as wrappers without diverging behavior
- [x] Lifecycle tests pass
