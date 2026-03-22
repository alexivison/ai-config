# Task 5 — Port State Store And Discovery

**Dependencies:** Task 4 | **Issue:** TBD

---

## Goal

Move manifest CRUD, locking, and session discovery into typed Go code first. This is the safest high-value port because it underpins every later CLI and TUI feature without yet mutating live tmux state.

## Scope Boundary (REQUIRED)

**In scope:**
- Port manifest read/write/update helpers into `internal/state`
- Replace lock-directory behavior with flock-based locking
- Port session discovery and visible-session filtering rules
- Discovery returns all party sessions (no companion filtering needed — hidden-window model means Codex lives within the same session, not a separate one)

**Out of scope (handled by other tasks):**
- tmux pane lookup or tmux sends
- Lifecycle commands and session launch
- TUI rendering logic

**Cross-task consistency check:**
- Discovery returns all party sessions; no session-level filtering needed since Codex runs in a hidden window within each session
- Manifest structs defined here must be reused by both CLI commands and TUI views; later tasks should not fork alternate state models

## Reference

Files to study before implementing:

- `session/party-lib.sh` — manifest CRUD and discovery behavior
- `session/party.sh` — list/prune consumers of discovery output
- `tools/party-tracker/workers.go` — current manifest-reading precedent

## Design References (REQUIRED for UI/component tasks)

N/A (non-UI task)

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
| `tools/party-cli/internal/state/manifest.go` | Create |
| `tools/party-cli/internal/state/store.go` | Create |
| `tools/party-cli/internal/state/discovery.go` | Create |
| `tools/party-cli/internal/state/*_test.go` | Create |

## Requirements

**Functionality:**
- Preserve the current manifest schema and field meanings
- Use flock-based locking with explicit timeout/error behavior
- Discovery returns all party sessions (hidden-window model eliminates the need for session-level filtering)
- Read/write behavior is testable without a live tmux server

**Key gotchas:**
- Keep JSON field handling tolerant of older manifests already on disk
- Avoid coupling discovery too tightly to tmux-specific logic that belongs in Task 6

## Tests

Test cases:
- Manifest create/read/update/delete paths
- Lock contention and timeout behavior
- Discovery returns all party sessions without session-level filtering
- Compatibility with older manifests missing optional fields

## Acceptance Criteria

- [ ] Typed Go state store preserves existing manifest schema
- [ ] Flock-based locking replaces directory-lock behavior
- [ ] Session discovery is implemented (no companion filtering needed — hidden-window model)
- [ ] State package tests pass
