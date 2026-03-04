# Task 4 - Marker Demotion and Retention

**Dependencies:** Task 3 | **Issue:** N/A

---

## Goal

Demote markers to compatibility cache, formalize ledger retention/cleanup, and finalize operator documentation for steady-state ledger-first operation.

## Scope Boundary (REQUIRED)

**In scope:**

1. Reduce marker coupling in hooks (keep minimal compatibility path).
2. Add ledger retention cleanup policy at session start.
3. Update docs to define steady-state ledger-first behavior.

**Out of scope (handled by other tasks):**

1. Additional feature-level workflow policy changes.
2. New transport queue/retry protocol.
3. External ledger storage.

**Cross-task consistency check:**

1. Gates remain functional with markers absent when `CLAUDE_LEDGER_MODE=enforce`.
2. Cleanup does not delete active-session ledger files.

## Reference

1. `claude/hooks/session-cleanup.sh:10-16` - existing marker cleanup.
2. `claude/hooks/marker-invalidate.sh:35-55` - current marker invalidation coupling.
3. `README.md:72-99` - session/runtime documentation style.

## Design References (REQUIRED for UI/component tasks)

N/A (non-UI task).

## Data Transformation Checklist (REQUIRED for shape changes)

- [ ] Retention filter maps filesystem state -> preserved/deleted ledger files
- [ ] Compatibility marker path remains non-authoritative
- [ ] Docs align with actual mode behavior and fallback semantics

## Files to Create/Modify

| File | Action |
|------|--------|
| `claude/hooks/session-cleanup.sh` | Modify |
| `claude/hooks/agent-trace.sh` | Modify |
| `claude/hooks/codex-trace.sh` | Modify |
| `claude/hooks/skill-marker.sh` | Modify |
| `claude/hooks/marker-invalidate.sh` | Modify |
| `README.md` | Modify |
| `claude/rules/execution-core.md` | Modify |
| `claude/hooks/tests/test-ledger-gates.sh` | Modify |

## Requirements

**Functionality:**

1. Ledger files are retained for a defined window (example: 14 days) and then pruned.
2. Marker writes are optional compatibility behavior, not required for enforcement.
3. Documentation clearly states operational mode and rollback path.

**Key gotchas:**

1. Do not remove marker compatibility before ledger enforce tests are green.
2. Avoid cleanup race conditions with active sessions.

## Tests

1. Enforce-mode tests with markers disabled.
2. Retention cleanup tests against synthetic old/new ledgers.
3. Full hook suite regression.

## Verification Commands

1. `bash claude/hooks/tests/test-ledger-gates.sh`
2. `bash claude/hooks/tests/run-all.sh`
3. `bash tests/run-tests.sh`

## Acceptance Criteria

- [ ] Ledger-first operation works without marker dependency in enforce mode
- [ ] Retention cleanup is safe and deterministic
- [ ] Migration docs reflect final behavior and rollback switch
- [ ] Verification commands pass
