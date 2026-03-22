# Task 6 — Port Tmux Service And Pane Capture

**Dependencies:** Task 4, Task 5 | **Issue:** TBD

---

## Goal

Establish one typed tmux service for session queries, pane lookup, delivery-confirmed sends, capture, popup helpers, and window-management helpers. CLI commands and TUI views should both depend on this layer instead of shelling out ad hoc.

## Scope Boundary (REQUIRED)

**In scope:**
- Port tmux session and pane query helpers into `internal/tmux`
- Port role-based pane resolution with strict `@party_role` semantics
- Add delivery-confirmed send behavior with explicit results
- Port pane capture and popup helpers
- Add window-management helpers for the hidden-window model (window 0 = Codex, window 1 = workspace)

**Out of scope (handled by other tasks):**
- Session lifecycle orchestration
- `tmux-codex.sh` ownership or Codex transport migration
- Final TUI behavior beyond shared service calls

**Cross-task consistency check:**
- The send-result type created here becomes the shared contract for CLI messaging and TUI actions
- Window-management helpers must match the hidden-window conventions from Task 9 (window 0 = Codex, window 1 = workspace)

## Reference

Files to study before implementing:

- `session/party-lib.sh` — tmux send and pane-routing precedent
- `tools/party-tracker/workers.go` — current snippet capture behavior
- `tools/party-tracker/actions.go` — tmux action wrapper precedent
- `tmux/tmux.conf` — popup/layout assumptions

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
| `tools/party-cli/internal/tmux/client.go` | Create |
| `tools/party-cli/internal/tmux/query.go` | Create |
| `tools/party-cli/internal/tmux/send.go` | Create |
| `tools/party-cli/internal/tmux/capture.go` | Create |
| `tools/party-cli/internal/tmux/popup.go` | Create |
| `tools/party-cli/internal/tmux/*_test.go` | Create |

## Requirements

**Functionality:**
- Query sessions and panes through typed functions
- Resolve pane targets through strict role metadata only
- Return explicit delivery results instead of best-effort exit codes
- Capture pane content and launch tmux popups through reusable helpers
- Share window-management helpers for targeting Codex (window 0) and workspace panes (window 1)

**Key gotchas:**
- Keep the tmux layer free of business logic that belongs in lifecycle or message services
- Do not take ownership of `tmux-codex.sh`; this task prepares the Go layer for other flows only

## Tests

Test cases:
- Session and pane query parsing
- Strict role lookup success, not-found, and ambiguous cases
- Delivery success and timeout/error cases
- Pane capture and popup command construction
- Window-management helper targeting (window 0 for Codex, window 1 for workspace)

## Acceptance Criteria

- [ ] Shared tmux service exists with typed query, send, capture, and popup helpers
- [ ] Role lookup is strict and explicit
- [ ] Delivery results are no longer silent
- [ ] Window-management helpers correctly target window 0 (Codex) and window 1 (workspace)
- [ ] tmux package tests pass
