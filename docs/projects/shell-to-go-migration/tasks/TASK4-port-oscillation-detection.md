# Task 4 — Port Oscillation Detection

**Dependencies:** Task 1 | **Issue:** TBD

---

## Goal

Port oscillation detection into Go before the agent hook cutover so the tricky override logic is tested in isolation rather than rediscovered during a larger trace migration.

## Scope Boundary (REQUIRED)

**In scope:**
- Port `compute_finding_fingerprint()` and `detect_oscillation()` into `internal/oscillation`
- Preserve same-hash alternation and cross-hash repeated-finding behavior
- Expose a package API that Task 5 can call from `agent-trace-stop`

**Out of scope (handled by other tasks):**
- Hook shim conversion
- Metrics recording itself
- Codex or PR gate logic

**Cross-task consistency check:**
- Task 5 must call this package for critic verdict tracking; it must not recreate `*-run` or `*-fp` writes inline
- Auto-triage overrides must keep using the evidence package from Task 1

## Reference

Files to study before implementing:

- `claude/hooks/lib/oscillation.sh:17` — fingerprint normalization pipeline
- `claude/hooks/lib/oscillation.sh:42` — same-hash and cross-hash detection logic
- `claude/rules/execution-core.md:50` — behavioral contract for oscillation handling
- `claude/hooks/tests/test-agent-trace.sh:220` — same-hash alternation fixtures
- `claude/hooks/tests/test-evidence.sh:320` — override supersession behavior that oscillation relies upon

## Design References (REQUIRED for UI/component tasks)

N/A (non-UI task)

## Data Transformation Checklist (REQUIRED for shape changes)

- [ ] Proto definition (N/A)
- [ ] Proto -> Domain converter (N/A)
- [ ] Domain model struct for verdict history and normalized fingerprints
- [ ] Params struct(s) for oscillation inputs
- [ ] Params conversion functions from trace verdicts to oscillation checks
- [ ] Any adapters between oscillation results and evidence override writes

## Files to Create/Modify

| File | Action |
|------|--------|
| `tools/party-cli/internal/oscillation/oscillation.go` | Create |
| `tools/party-cli/internal/oscillation/oscillation_test.go` | Create |
| `tools/party-cli/internal/evidence/evidence.go` | Modify |

## Requirements

**Functionality:**
- Preserve A->B->A same-hash alternation detection across `code-critic`, `minimizer`, and `scribe`
- Preserve cross-hash repeated-finding detection for `minimizer` only
- Preserve the current override rationale text closely enough for auditability
- Record `*-run` and `*-fp` evidence through the shared evidence package

**Key gotchas:**
- The fingerprint normalizer must match the shell `sed|tr|sed|shasum` pipeline closely, or cross-hash detection will quietly drift
- `code-critic` must remain exempt from cross-hash repeated-finding overrides

## Tests

Test cases:
- Same-hash alternating verdicts trigger a triage override
- Consecutive identical verdicts do not false-positive
- Cross-hash repeated minimizer complaints trigger after three distinct hashes
- Other critic types do not cross-trigger minimizer rules

Verification commands:
- `go test ./internal/oscillation ./internal/evidence`
- `bash claude/hooks/tests/test-agent-trace.sh`

## Acceptance Criteria

- [ ] `internal/oscillation` owns oscillation detection behavior
- [ ] Same-hash and cross-hash parity fixtures match the current shell behavior
- [ ] Override writes still flow through the shared evidence package
- [ ] Task 5 can consume the package without re-implementing the logic
