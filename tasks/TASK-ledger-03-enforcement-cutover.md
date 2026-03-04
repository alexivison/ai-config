# Task 3 - Ledger Enforcement Cutover

**Dependencies:** Task 2 | **Issue:** N/A

---

## Goal

Promote ledger verdicts from observational to authoritative for PR and codex gates, with explicit mode control and marker fallback for safe rollback.

## Scope Boundary (REQUIRED)

**In scope:**

1. Add mode switch behavior:
   - `CLAUDE_LEDGER_MODE=off|shadow|enforce`
2. In `enforce`, gate allow/deny is driven by ledger evaluator.
3. Markers remain fallback when ledger cannot be read.

**Out of scope (handled by other tasks):**

1. Removing marker writes from producer hooks.
2. Final cleanup/retention changes.
3. Transport protocol improvements.

**Cross-task consistency check:**

1. In `off`, behavior is identical to current marker-only flow.
2. In `shadow`, behavior matches Task 2.
3. In `enforce`, denials are explainable solely by missing/stale ledger events.

## Reference

1. `claude/hooks/pr-gate.sh:62-73` - deny response structure.
2. `claude/hooks/codex-gate.sh:59-70` - deny response structure.
3. `claude/settings.json:86-111` - hook execution environment.

## Design References (REQUIRED for UI/component tasks)

N/A (non-UI task).

## Data Transformation Checklist (REQUIRED for shape changes)

- [ ] Mode value parsing with defaults
- [ ] Ledger result -> deny reason text mapping
- [ ] Fallback path clearly distinguished in logs
- [ ] No contradictory allow/deny behavior when ledger unavailable

## Files to Create/Modify

| File | Action |
|------|--------|
| `claude/hooks/pr-gate.sh` | Modify |
| `claude/hooks/codex-gate.sh` | Modify |
| `claude/rules/execution-core.md` | Modify |
| `claude/CLAUDE.md` | Modify |
| `claude/hooks/tests/test-ledger-gates.sh` | Modify |

## Requirements

**Functionality:**

1. `off`: marker-only enforcement.
2. `shadow`: marker enforcement + ledger comparison logs.
3. `enforce`: ledger enforcement + marker fallback only on evaluator failure.

**Key gotchas:**

1. Avoid silent fallback in `enforce`; emit explicit fallback log.
2. Deny reasons must list missing evidence events consistently.

## Tests

1. Mode matrix tests for both gates.
2. Regression tests for existing marker-only scenarios.
3. Negative tests with stale evidence and missing codex completion.

## Verification Commands

1. `bash claude/hooks/tests/test-ledger-gates.sh`
2. `bash claude/hooks/tests/run-all.sh`
3. `bash tests/test-hooks.sh`

## Acceptance Criteria

- [ ] Gates support all three modes with deterministic behavior
- [ ] `enforce` mode denial reasons map to ledger evaluator output
- [ ] Marker fallback works and is observable in logs
- [ ] Verification commands pass
