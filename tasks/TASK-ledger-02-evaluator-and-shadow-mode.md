# Task 2 - Evaluator and Shadow Mode

**Dependencies:** Task 1 | **Issue:** N/A

---

## Goal

Create a shared ledger evaluator and integrate it into PR/codex gates in shadow mode so marker enforcement continues while ledger decisions are computed and compared for parity.

## Scope Boundary (REQUIRED)

**In scope:**

1. Build `ledger-eval.sh` with deterministic evidence freshness logic.
2. Integrate evaluator into:
   - `pr-gate.sh` (shadow compare)
   - `codex-gate.sh` (shadow compare)
3. Add mismatch logging with actionable reason output.

**Out of scope (handled by other tasks):**

1. Ledger enforcement cutover.
2. Marker removal/demotion.
3. Retention cleanup behavior.

**Cross-task consistency check:**

1. Evaluator required events must match the current gate contract:
   - PR gate required markers from `pr-gate.sh:47-60`
   - Codex gate required markers from `codex-gate.sh:52-57` and `codex-gate.sh:28-35`
2. `code_changed` boundary invalidates prior evidence in evaluator output.

## Reference

1. `claude/hooks/pr-gate.sh:46-73` - marker gate logic.
2. `claude/hooks/codex-gate.sh:26-70` - codex marker gate logic.
3. `claude/rules/execution-core.md:108-126` - policy and gate semantics.

## Design References (REQUIRED for UI/component tasks)

N/A (non-UI task).

## Data Transformation Checklist (REQUIRED for shape changes)

- [ ] Ledger JSONL parse tolerates malformed lines
- [ ] Event stream -> freshness boundary (`latest code_changed`)
- [ ] Boundary + required events -> `{allow, missing}` deterministic output
- [ ] Shadow compare output includes both marker verdict and ledger verdict

## Files to Create/Modify

| File | Action |
|------|--------|
| `claude/hooks/lib/ledger-eval.sh` | Create |
| `claude/hooks/pr-gate.sh` | Modify |
| `claude/hooks/codex-gate.sh` | Modify |
| `claude/hooks/tests/test-ledger-eval.sh` | Create |
| `claude/hooks/tests/test-ledger-gates.sh` | Create |

## Requirements

**Functionality:**

1. Shadow mode computes ledger verdict without changing allow/deny behavior.
2. Mismatch logs include:
   - session
   - gate
   - marker verdict
   - ledger verdict
   - missing evidence list

**Key gotchas:**

1. Do not deny actions solely due to ledger mismatch in this task.
2. Keep docs/config-only PR bypass behavior unchanged unless explicitly planned later.

## Tests

1. Evaluator returns expected verdicts for:
   - complete evidence
   - missing required event
   - stale evidence after `code_changed`
2. Shadow-mode gates still match prior marker allow/deny outcomes.

## Verification Commands

1. `bash claude/hooks/tests/test-ledger-eval.sh`
2. `bash claude/hooks/tests/test-ledger-gates.sh`
3. `bash claude/hooks/tests/run-all.sh`

## Acceptance Criteria

- [ ] Ledger evaluator exists and is reused by both gates
- [ ] Shadow mode parity logging works with explicit reasons
- [ ] Marker enforcement remains authoritative in this phase
- [ ] Verification commands pass
