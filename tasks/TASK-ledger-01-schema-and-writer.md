# Task 1 - Ledger Schema and Writer

**Dependencies:** none | **Issue:** N/A

---

## Goal

Introduce a canonical event schema and shared ledger writer, then dual-write events from existing marker-producing hooks so the ledger starts collecting authoritative evidence without changing gate behavior yet.

## Scope Boundary (REQUIRED)

**In scope:**

1. Define event schema and append helper in `claude/hooks/lib/ledger.sh`.
2. Emit canonical events from:
   - `agent-trace.sh`
   - `codex-trace.sh`
   - `skill-marker.sh`
   - `marker-invalidate.sh`
3. Preserve existing marker behavior unchanged.

**Out of scope (handled by other tasks):**

1. Gate decision logic changes (`pr-gate.sh`, `codex-gate.sh`).
2. Mode cutover to ledger enforcement.
3. Marker demotion and retention policy.

**Cross-task consistency check:**

1. Every marker currently required by gates must map to at least one canonical ledger event in this task.
2. `code_changed` invalidation event must be emitted now so Task 2 evaluator can enforce freshness boundaries.

## Reference

1. `claude/hooks/agent-trace.sh:106-129` - current marker writes.
2. `claude/hooks/codex-trace.sh:50-75` - codex evidence marker flow.
3. `claude/hooks/skill-marker.sh:24-29` - `/pre-pr-verification` marker source.
4. `claude/hooks/marker-invalidate.sh:35-55` - invalidation behavior.

## Design References (REQUIRED for UI/component tasks)

N/A (non-UI task).

## Data Transformation Checklist (REQUIRED for shape changes)

- [ ] Hook payload -> canonical event mapping for all producer hooks
- [ ] Event serialization uses stable JSON keys/order expectations
- [ ] Append operation is atomic per event line
- [ ] Required fields populated (`v`, `ts`, `session`, `repo`, `branch`, `head`, `event`, `actor`)
- [ ] Invalid/unknown payloads fail safely (no crash)

## Files to Create/Modify

| File | Action |
|------|--------|
| `claude/hooks/lib/ledger.sh` | Create |
| `claude/hooks/agent-trace.sh` | Modify |
| `claude/hooks/codex-trace.sh` | Modify |
| `claude/hooks/skill-marker.sh` | Modify |
| `claude/hooks/marker-invalidate.sh` | Modify |
| `claude/hooks/tests/test-ledger-lib.sh` | Create |

## Requirements

**Functionality:**

1. Canonical events are dual-written alongside existing markers.
2. Ledger path is session-scoped: `~/.claude/state/ledger/<session_id>.jsonl`.
3. Existing marker-based gates remain unaffected.

**Key gotchas:**

1. Avoid duplicate writes for a single hook call.
2. Do not break current hook fail-open behavior.
3. Handle missing `session_id` consistently (skip write, no crash).

## Tests

1. Writer emits valid JSONL lines with required fields.
2. Writer skips invalid inputs safely.
3. Existing hook tests remain green.

## Verification Commands

1. `bash claude/hooks/tests/test-ledger-lib.sh`
2. `bash claude/hooks/tests/run-all.sh`
3. `bash tests/test-hooks.sh`

## Acceptance Criteria

- [ ] Ledger writer library exists with schema validation helpers
- [ ] All producer hooks emit canonical events and still create legacy markers
- [ ] No gate behavior changes observed in this task
- [ ] Verification commands pass
