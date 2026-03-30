# Task 7 — Port PR Gate Hook And Diagnostics

**Dependencies:** Task 1, Task 2, Task 5, Task 6 | **Issue:** TBD

---

## Goal

Move the PR gate into Go only after the evidence producers are already on `party-cli`, so the deny/allow decision consumes the same shared contracts that the migrated hooks now write.

## Scope Boundary (REQUIRED)

**In scope:**
- Add `internal/gate` PR evaluation logic
- Add `party-cli hook pr-gate`
- Port docs-only bypass, quick-tier size checks, full-tier evidence checks, and stale-evidence diagnostics
- Convert `claude/hooks/pr-gate.sh` into a shim

**Out of scope (handled by other tasks):**
- Workflow skills that emit `quick-tier`
- Non-PR Bash hooks
- Codex or agent trace producers beyond consuming their evidence

**Cross-task consistency check:**
- Gate evaluation must read the evidence and resolver packages from Tasks 1 and 2 and the evidence producers from Tasks 5 and 6
- Task 8 must not delete the shell gate logic until this Go gate is passing the current shell fixtures

## Reference

Files to study before implementing:

- `claude/hooks/pr-gate.sh:30` — PR-create interception and docs-only bypass
- `claude/hooks/pr-gate.sh:55` — quick-tier gating and size thresholds
- `claude/hooks/pr-gate.sh:75` — stale-evidence diagnostics and deny JSON shape
- `claude/hooks/tests/test-pr-gate.sh:69` — docs-only fixture matrix
- `claude/hooks/tests/test-pr-gate.sh:157` — full-gate and stale-evidence fixtures
- `claude/hooks/tests/test-pr-gate.sh:197` — quick-tier fixtures
- `claude/rules/execution-core.md:95` — tier definitions
- `claude/rules/execution-core.md:178` — PR gate contract

## Design References (REQUIRED for UI/component tasks)

N/A (non-UI task)

## Data Transformation Checklist (REQUIRED for shape changes)

- [ ] Proto definition (N/A)
- [ ] Proto -> Domain converter (N/A)
- [ ] Domain model struct for gate input, diff stats, and deny diagnostics
- [ ] Params struct(s) for `party-cli hook pr-gate`
- [ ] Params conversion functions from hook JSON to gate evaluation
- [ ] Any adapters between gate diagnostics and Claude hook deny JSON

## Files to Create/Modify

| File | Action |
|------|--------|
| `tools/party-cli/internal/gate/pr.go` | Create |
| `tools/party-cli/internal/gate/pr_test.go` | Create |
| `tools/party-cli/cmd/hook_pr_gate.go` | Create |
| `tools/party-cli/cmd/root.go` | Modify |
| `claude/hooks/pr-gate.sh` | Modify |

## Requirements

**Functionality:**
- Intercept only `gh pr create`
- Preserve the docs/config-only bypass file-pattern behavior
- Preserve quick-tier limits: `<=30` changed lines, `<=3` files, `0` new files, plus explicit `quick-tier` evidence
- Preserve full-tier evidence requirements and stale-evidence diagnostics
- Preserve fail-open behavior when session or command data cannot be determined

**Key gotchas:**
- Small diffs without `quick-tier` evidence must still fall through to the full gate
- A current-hash `REQUEST_CHANGES` from a critic is an active failure, not a stale-evidence hint

## Tests

Test cases:
- Docs-only bypass across markdown, assets, and build-file edge cases
- Full gate allow/deny behavior with missing, present, and stale evidence
- Quick-tier allow/deny behavior for small diffs, large diffs, and new files
- Non-PR Bash commands pass through untouched

Verification commands:
- `go test ./internal/gate ./cmd`
- `bash claude/hooks/tests/test-pr-gate.sh`

## Acceptance Criteria

- [ ] `party-cli hook pr-gate` owns PR gate evaluation
- [ ] `claude/hooks/pr-gate.sh` is reduced to a shim
- [ ] Docs-only, quick-tier, full-tier, and stale-evidence behavior match the current shell fixtures
- [ ] Go and shell parity tests pass
