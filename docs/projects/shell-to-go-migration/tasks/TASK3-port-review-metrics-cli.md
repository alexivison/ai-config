# Task 3 — Port Review Metrics CLI

**Dependencies:** Task 1 | **Issue:** TBD

---

## Goal

Move review metrics recording and reporting into Go so every future hook task writes through one typed package, while operators keep a familiar CLI surface for triage and session reporting.

## Scope Boundary (REQUIRED)

**In scope:**
- Port metrics file naming, event writers, iteration counting, report generation, and JSON export into `internal/metrics`
- Add `party-cli metrics finding|summary|triage|resolved|cycle|report|export|report-all`
- Reduce `claude/hooks/scripts/review-metrics.sh` to a thin wrapper over the Go command

**Out of scope (handled by other tasks):**
- Automatic hook producers (`agent-trace-stop`, `codex-trace`) beyond consuming the package later
- Oscillation logic
- Gate logic

**Cross-task consistency check:**
- Task 5 and Task 6 must use the same package and command surface for automatic metrics writes
- No second metrics writer may remain in shell after this task except the wrapper script

## Reference

Files to study before implementing:

- `claude/hooks/lib/review-metrics.sh:26` — metrics file location and event schemas
- `claude/hooks/lib/review-metrics.sh:244` — human-readable report structure
- `claude/hooks/scripts/review-metrics.sh:24` — current CLI surface and argument order
- `claude/hooks/tests/test-review-metrics.sh:64` — event-parity fixtures and CLI coverage
- `claude/rules/execution-core.md:54` — metrics semantics and expected events
- `tools/party-cli/cmd/root.go:85` — Cobra command wiring pattern to follow

## Design References (REQUIRED for UI/component tasks)

N/A (non-UI task)

## Data Transformation Checklist (REQUIRED for shape changes)

- [ ] Proto definition (N/A)
- [ ] Proto -> Domain converter (N/A)
- [ ] Domain model struct for metrics events and report aggregates
- [ ] Params struct(s) for metrics subcommands
- [ ] Params conversion functions from CLI arguments to metrics events
- [ ] Any adapters between raw JSONL events and report/export views

## Files to Create/Modify

| File | Action |
|------|--------|
| `tools/party-cli/internal/metrics/metrics.go` | Create |
| `tools/party-cli/internal/metrics/report.go` | Create |
| `tools/party-cli/internal/metrics/metrics_test.go` | Create |
| `tools/party-cli/cmd/metrics.go` | Create |
| `tools/party-cli/cmd/root.go` | Modify |
| `claude/hooks/scripts/review-metrics.sh` | Modify |

## Requirements

**Functionality:**
- Preserve `~/.claude/logs/review-metrics/{session_id}.jsonl`
- Preserve `finding_raised`, `findings_summary`, `triage`, `resolved`, and `review_cycle` event shapes
- Preserve per-source auto-incremented `iteration` behavior for summary events
- Preserve report/export/report-all CLI parity closely enough for the current shell tests to pass

**Key gotchas:**
- Metrics writes still depend on evidence-derived diff hashes, so this task must call the Task 1 package rather than duplicate hash logic
- Human-readable report formatting need not be byte-identical, but the headings, counts, and semantic sections in the current tests must survive

## Tests

Test cases:
- One-event and multi-event metrics writes with valid JSONL output
- Iteration auto-increment per source
- Report output sections and exported JSON arrays
- Concurrent metrics writes without JSON corruption
- Wrapper CLI parity for all existing modes

Verification commands:
- `go test ./internal/metrics ./cmd`
- `bash claude/hooks/tests/test-review-metrics.sh`

## Acceptance Criteria

- [ ] `internal/metrics` owns metrics storage and reporting
- [ ] `party-cli metrics ...` covers every existing shell CLI mode
- [ ] `claude/hooks/scripts/review-metrics.sh` is reduced to a wrapper
- [ ] Go and shell parity tests pass for the existing metrics fixtures
