# Task 6 — Port Codex Hooks And Skill Marker

**Dependencies:** Task 2, Task 3 | **Issue:** TBD

---

## Goal

Move the wizard-facing hooks into Go so Codex approval, TOON metrics parsing, self-approval blocking, and `pr-verified` skill evidence all pass through one typed surface instead of three separate shell scripts.

## Scope Boundary (REQUIRED)

**In scope:**
- Add `party-cli hook codex-trace`
- Add `party-cli hook codex-gate`
- Add `party-cli hook skill-marker`
- Port TOON findings parsing, Codex sentinels, triage overrides, and skill-marker evidence writes
- Convert `claude/hooks/codex-trace.sh`, `claude/hooks/codex-gate.sh`, and `claude/hooks/skill-marker.sh` into shims

**Out of scope (handled by other tasks):**
- `tmux-codex.sh` transport or prompt orchestration
- PR gate logic
- Agent trace hook behavior

**Cross-task consistency check:**
- The Codex approval contract stays `--review-complete` plus `CODEX_REVIEW_RAN`; Task 7 consumes the same codex evidence entry when deciding PR readiness
- Skill-marker evidence must flow through the shared evidence package, not direct JSONL writes

## Reference

Files to study before implementing:

- `claude/hooks/codex-trace.sh:61` — Codex approval sentinel handling
- `claude/hooks/codex-trace.sh:81` — TOON findings parsing and metrics writes
- `claude/hooks/codex-trace.sh:164` — triage-override handling
- `claude/hooks/codex-gate.sh:31` — self-approval block semantics
- `claude/hooks/skill-marker.sh:27` — `pre-pr-verification` to `pr-verified` mapping
- `claude/hooks/tests/test-codex-trace.sh:93` — codex trace fixtures
- `claude/hooks/tests/test-codex-gate.sh:67` — codex gate fixtures
- `claude/settings.json:84` — PreToolUse hook registration for `codex-gate.sh`
- `claude/settings.json:138` — PostToolUse and Skill hook registrations

## Design References (REQUIRED for UI/component tasks)

N/A (non-UI task)

## Data Transformation Checklist (REQUIRED for shape changes)

- [ ] Proto definition (N/A)
- [ ] Proto -> Domain converter (N/A)
- [ ] Domain model struct for Codex hook payloads, TOON rows, and skill events
- [ ] Params struct(s) for `party-cli hook codex-*` and `party-cli hook skill-marker`
- [ ] Params conversion functions from hook JSON and findings files to evidence/metrics events
- [ ] Any adapters between TOON rows and review-metrics events

## Files to Create/Modify

| File | Action |
|------|--------|
| `tools/party-cli/internal/trace/codex.go` | Create |
| `tools/party-cli/internal/trace/codex_test.go` | Create |
| `tools/party-cli/internal/gate/codex.go` | Create |
| `tools/party-cli/cmd/hook_codex.go` | Create |
| `tools/party-cli/cmd/hook_skill_marker.go` | Create |
| `tools/party-cli/cmd/root.go` | Modify |
| `claude/hooks/codex-trace.sh` | Modify |
| `claude/hooks/codex-gate.sh` | Modify |
| `claude/hooks/skill-marker.sh` | Modify |

## Requirements

**Functionality:**
- Preserve the `CODEX_REVIEW_RAN` plus `CODEX APPROVED` requirement before writing codex evidence
- Preserve object-vs-string Bash tool response handling
- Preserve triage override handling and TOON findings parsing into review metrics
- Preserve the self-approval block for `tmux-codex.sh --approve`
- Preserve `pre-pr-verification -> pr-verified` evidence mapping

**Key gotchas:**
- Missing findings files are allowed and must still produce a summary event from the verdict alone
- `codex-gate` is intentionally narrow; do not accidentally turn it into a phase gate

## Tests

Test cases:
- Approval, request-changes, and missing-sentinel Codex flows
- Findings-file parsing into individual metrics and summary metrics
- `TRIAGE_OVERRIDE` handling for valid and invalid types
- `--approve` blocking with all other Codex commands still allowed
- Skill-marker evidence creation only for the `Skill` tool and the expected skill name

Verification commands:
- `go test ./internal/trace ./internal/gate ./internal/metrics ./cmd`
- `bash claude/hooks/tests/test-codex-trace.sh`
- `bash claude/hooks/tests/test-codex-gate.sh`

## Acceptance Criteria

- [ ] `party-cli hook codex-trace`, `party-cli hook codex-gate`, and `party-cli hook skill-marker` own the behavior
- [ ] The three shell hook files are reduced to shims
- [ ] Codex evidence, TOON metrics parsing, and self-approval blocking match current fixtures
- [ ] Go and shell parity tests pass
