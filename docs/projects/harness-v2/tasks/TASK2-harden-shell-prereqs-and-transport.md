# Task 2 — Harden Shell Prereqs And Transport

**Dependencies:** Task 1 | **Issue:** TBD

---

## Goal

Fix the highest-value shell reliability faults before the port begins: missing prerequisites must fail loudly, temp files must clean themselves, pane routing must stop guessing, and dropped tmux sends must become visible.

## Scope Boundary (REQUIRED)

**In scope:**
- Add an early `jq` requirement check to shared shell state paths in `session/party-lib.sh`
- Ensure temp files created by shell helpers are cleaned via traps
- Quote `$lib_path` in the tmux hook source path
- Remove legacy pane-routing fallback and require authoritative `@party_role`
- Emit tmux send failures to stderr with actionable context

**Out of scope (handled by other tasks):**
- Go-based tmux transport or Go-based state management
- Lifecycle layout changes for sidebar mode
- Hook-library extraction and tests

**Cross-task consistency check:**
- Any helper renamed here must be reflected in retained callers such as `tmux-codex.sh`
- Strict role routing introduced here becomes the contract later Go services and shell wrappers must preserve

## Reference

Files to study before implementing:

- `session/party-lib.sh` — manifest helpers, temp files, routing, tmux send
- `session/party-master.sh` — existing `jq` enforcement precedent
- `tmux/tmux.conf` — tmux hook source path quoting target
- `claude/skills/codex-transport/scripts/tmux-codex.sh` — retained shell caller

## Design References (REQUIRED for UI/component tasks)

N/A (non-UI task)

## Data Transformation Checklist (REQUIRED for shape changes)

N/A (no persisted or public shape change in this task)

## Files to Create/Modify

| File | Action |
|------|--------|
| `session/party-lib.sh` | Modify |
| `session/party-master.sh` | Modify if shared prereq helper is extracted |
| `tmux/tmux.conf` | Modify |
| `claude/skills/codex-transport/scripts/tmux-codex.sh` | Modify if helper names or stderr handling change |
| `tests/test-party-routing.sh` | Modify |
| `tests/test-party-lib.sh` | Create or modify if a focused shell test is warranted |

## Requirements

**Functionality:**
- All shell manifest mutations fail fast and clearly when `jq` is unavailable
- Routing resolves panes only through authoritative `@party_role` metadata
- `tmux_send` failures include target, timeout, and payload context on stderr
- Temp files created by helper paths are removed on success and failure

**Key gotchas:**
- `tmux-codex.sh` still depends on `party-lib.sh`; do not break its basic routing contract while removing fallback behavior
- Keep error text stable enough for shell tests to assert on it

## Tests

Test cases:
- Missing-`jq` shell paths fail with a clear error and non-zero exit
- Routing fails closed when no pane exposes the requested role
- Timed-out tmux sends now produce stderr output
- Temp files are cleaned on both successful and failing helper executions

## Acceptance Criteria

- [x] `party-lib.sh` enforces `jq` before any manifest mutation
- [x] Legacy pane-routing fallback is removed and `@party_role` is mandatory
- [x] tmux send failures are visible on stderr
- [x] Hook sourcing uses a quoted `$lib_path`
- [x] Temp file cleanup is trap-based and verified by tests
