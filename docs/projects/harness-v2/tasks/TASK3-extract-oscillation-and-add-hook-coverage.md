# Task 3 — Extract Oscillation And Add Hook Coverage

**Dependencies:** none | **Issue:** TBD

---

## Goal

Reduce hook complexity before the larger migration by extracting oscillation detection into a dedicated library and by closing the glaring test gap around `worktree-guard.sh`.

## Scope Boundary (REQUIRED)

**In scope:**
- Move oscillation detection logic from `agent-trace-stop.sh` into `claude/hooks/lib/oscillation.sh`
- Update `agent-trace-stop.sh` to call the extracted library helpers
- Add a dedicated `worktree-guard` test file and wire it into the hook test runner

**Out of scope (handled by other tasks):**
- Any evidence-model redesign
- Shell transport hardening
- Go CLI or TUI work

**Cross-task consistency check:**
- Extracted oscillation helpers must preserve the simplified evidence model from the completed phase-simplification work
- Later sidebar evidence summaries should be able to rely on unchanged evidence semantics after this refactor

## Reference

Files to study before implementing:

- `claude/hooks/agent-trace-stop.sh` — source logic to extract
- `claude/hooks/lib/evidence.sh` — evidence contract that must remain stable
- `claude/hooks/worktree-guard.sh` — uncovered hook to test
- `claude/hooks/tests/test-agent-trace.sh` — existing hook test style

## Design References (REQUIRED for UI/component tasks)

N/A (non-UI task)

## Data Transformation Checklist (REQUIRED for shape changes)

N/A (no persisted or public shape change in this task)

## Files to Create/Modify

| File | Action |
|------|--------|
| `claude/hooks/agent-trace-stop.sh` | Modify |
| `claude/hooks/lib/oscillation.sh` | Create |
| `claude/hooks/tests/test-agent-trace.sh` | Modify |
| `claude/hooks/tests/test-worktree-guard.sh` | Create |
| `claude/hooks/tests/run-all.sh` | Modify |

## Requirements

**Functionality:**
- Oscillation logic becomes a dedicated reusable library with shell-safe function boundaries
- `agent-trace-stop.sh` retains current verdict behavior and evidence semantics
- `worktree-guard.sh` gains first-class regression coverage

**Key gotchas:**
- Keep helper naming clear enough that later evidence-summary readers can locate the logic quickly
- Avoid smuggling unrelated hook cleanup into this task

## Tests

Test cases:
- Existing agent-trace scenarios still pass after extraction
- New tests cover `worktree-guard` happy path, rejection path, and edge conditions
- Hook test runner includes the new suite

## Acceptance Criteria

- [x] `claude/hooks/lib/oscillation.sh` exists and owns the extracted logic
- [x] `agent-trace-stop.sh` is smaller and delegates to the new library
- [x] `worktree-guard.sh` has a dedicated test file
- [x] Hook regression suite passes
