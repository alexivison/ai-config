# Task 1 — Port Evidence Core And CLI

**Dependencies:** none | **Issue:** TBD

---

## Goal

Move the evidence contract into typed Go first. This is the risky seam and everything else sits atop it, so the binary must own hash parity, atomic append behavior, and JSONL reads before any hook consumer is cut over.

## Scope Boundary (REQUIRED)

**In scope:**
- Port `evidence_file`, `_resolve_cwd`, merge-base resolution, diff hash, diff stats, atomic append, `append_evidence`, `append_triage_override`, `check_evidence`, and `check_all_evidence` into `internal/evidence`
- Add `party-cli evidence diff-hash|diff-stats|append|check|check-all|override`
- Replace the direct evidence-file readers in `tools/party-cli/internal/tui/sidebar_status.go` with the shared package

**Out of scope (handled by other tasks):**
- Hook shim conversion
- Review metrics, oscillation, or PR/Codex gate logic
- Party session name to Claude UUID resolution

**Cross-task consistency check:**
- Task 5 through Task 7 must consume the evidence package and CLI from this task rather than re-implementing file layout, lock semantics, or stale-evidence checks
- TUI evidence rendering must stop opening `/tmp/claude-evidence-*.jsonl` directly once this task lands

## Reference

Files to study before implementing:

- `claude/hooks/lib/evidence.sh:36` — evidence file naming and `/tmp` path contract
- `claude/hooks/lib/evidence.sh:68` — worktree-aware `_resolve_cwd` repo-match validation
- `claude/hooks/lib/evidence.sh:99` — diff exclusion set and committed-only hash semantics
- `claude/hooks/lib/evidence.sh:157` — atomic append and lock fallback behavior
- `claude/hooks/tests/test-evidence.sh:54` — parity cases for hash, stale evidence, worktrees, and triage overrides
- `tools/party-cli/internal/state/store.go:25` — existing flock pattern already used in Go
- `tools/party-cli/internal/tui/sidebar_status.go:80` — current ad hoc evidence JSONL reader to replace

## Design References (REQUIRED for UI/component tasks)

N/A (non-UI task)

## Data Transformation Checklist (REQUIRED for shape changes)

- [ ] Proto definition (N/A)
- [ ] Proto -> Domain converter (N/A)
- [ ] Domain model struct for evidence records and diagnostics
- [ ] Params struct(s) for Cobra evidence subcommands
- [ ] Params conversion functions from flags/stdin to package calls
- [ ] Any adapters between TUI evidence summary views and full evidence records

## Files to Create/Modify

| File | Action |
|------|--------|
| `tools/party-cli/internal/evidence/evidence.go` | Create |
| `tools/party-cli/internal/evidence/hash.go` | Create |
| `tools/party-cli/internal/evidence/evidence_test.go` | Create |
| `tools/party-cli/cmd/evidence.go` | Create |
| `tools/party-cli/cmd/root.go` | Modify |
| `tools/party-cli/internal/tui/sidebar_status.go` | Modify |
| `tools/party-cli/internal/tui/sidebar_test.go` | Modify |

## Requirements

**Functionality:**
- Preserve `/tmp/claude-evidence-{session_id}.jsonl` and `/tmp/claude-evidence-{session_id}.lock`
- Compute the same diff hash as `claude/hooks/lib/evidence.sh:109-124`, including `clean` and `unknown`
- Preserve `_resolve_cwd` behavior for valid overrides, nonexistent overrides, and cross-repo stale overrides
- Preserve concurrent append safety and stale-evidence diagnostics

**Key gotchas:**
- `git diff` output must be hashed from the same byte stream as the shell version or every downstream gate will lie
- The exclusion set `:!*.md`, `:!*.log`, `:!*.jsonl`, `:!*.tmp` is part of the contract, not a suggestion

## Tests

Test cases:
- Hash parity for clean, committed, staged, unstaged, missing-dir, and worktree-divergence cases
- Concurrent appends with valid JSONL output
- Triage override behavior, including `-run` supersession
- TUI evidence summary and workflow-stage derivation through the shared package

Verification commands:
- `go test ./internal/evidence ./internal/tui ./cmd`
- `bash claude/hooks/tests/test-evidence.sh`

## Acceptance Criteria

- [ ] `internal/evidence` owns evidence reads, writes, and diagnostics
- [ ] `party-cli evidence ...` provides CLI parity for the shell evidence library
- [ ] `tools/party-cli/internal/tui/sidebar_status.go` no longer parses evidence files directly
- [ ] Go tests prove parity for the shell evidence fixture cases
