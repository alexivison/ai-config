# Task 5 — Port Agent Trace Hook Subcommands

**Dependencies:** Task 2, Task 3, Task 4 | **Issue:** TBD

---

## Goal

Cut over `SubagentStart` and `SubagentStop` to Go so verdict parsing, evidence writes, oscillation handling, and metrics summaries all run through `party-cli`, while the shell hooks shrink to the minimal Claude-facing shim.

## Scope Boundary (REQUIRED)

**In scope:**
- Add `party-cli hook agent-trace-start`
- Add `party-cli hook agent-trace-stop`
- Port agent trace JSONL logging, evidence-trace logging, verdict extraction, evidence mapping, oscillation handling, and metrics summary recording
- Convert `claude/hooks/agent-trace-start.sh` and `claude/hooks/agent-trace-stop.sh` into shims

**Out of scope (handled by other tasks):**
- Codex trace/gate and skill marker
- PR gate
- Manual metrics CLI shape beyond consuming it

**Cross-task consistency check:**
- Hook subcommands must parse the raw stdin JSON but use the shared evidence, metrics, and oscillation packages for behavior
- Task 6 must reuse any shared verdict-parsing helpers introduced here instead of creating a second parser

## Reference

Files to study before implementing:

- `claude/hooks/agent-trace-start.sh:9` — trace file location and event schema
- `claude/hooks/agent-trace-stop.sh:36` — verdict detection order and tail scan
- `claude/hooks/agent-trace-stop.sh:101` — evidence mapping per agent type
- `claude/hooks/agent-trace-stop.sh:130` — metrics summary extraction
- `claude/hooks/tests/test-agent-trace.sh:107` — hook-level parity fixtures
- `claude/settings.json:116` — `SubagentStart` hook registration
- `claude/settings.json:127` — `SubagentStop` hook registration

## Design References (REQUIRED for UI/component tasks)

N/A (non-UI task)

## Data Transformation Checklist (REQUIRED for shape changes)

- [ ] Proto definition (N/A)
- [ ] Proto -> Domain converter (N/A)
- [ ] Domain model struct for hook payloads and parsed verdicts
- [ ] Params struct(s) for `party-cli hook agent-trace-*`
- [ ] Params conversion functions from raw hook JSON to trace/evidence calls
- [ ] Any adapters between parsed verdict summaries and metrics events

## Files to Create/Modify

| File | Action |
|------|--------|
| `tools/party-cli/internal/trace/agent.go` | Create |
| `tools/party-cli/internal/trace/agent_test.go` | Create |
| `tools/party-cli/cmd/hook_agent_trace.go` | Create |
| `tools/party-cli/cmd/root.go` | Modify |
| `claude/hooks/agent-trace-start.sh` | Modify |
| `claude/hooks/agent-trace-stop.sh` | Modify |

## Requirements

**Functionality:**
- Preserve `~/.claude/logs/agent-trace.jsonl` and `~/.claude/logs/evidence-trace.log`
- Preserve verdict priority and fallback order from `claude/hooks/agent-trace-stop.sh:41-74`
- Preserve evidence mappings for `code-critic`, `minimizer`, `scribe`, `test-runner`, and `check-runner`
- Preserve fail-open handling for invalid JSON and empty messages

**Key gotchas:**
- `REQUEST_CHANGES` must still beat a stray `APPROVE` token elsewhere in the response
- Background-launch responses must remain `unknown` so they do not create false evidence

## Tests

Test cases:
- Start/stop trace events for multiple agent types
- Verdict parsing for APPROVED, REQUEST_CHANGES, NEEDS_DISCUSSION, PASS, FAIL, CLEAN, and unknown cases
- Evidence creation per agent type
- Stale evidence after code changes
- Oscillation-triggered auto-overrides and metrics summary recording

Verification commands:
- `go test ./internal/trace ./internal/oscillation ./internal/metrics ./cmd`
- `bash claude/hooks/tests/test-agent-trace.sh`

## Acceptance Criteria

- [ ] `party-cli hook agent-trace-start` and `party-cli hook agent-trace-stop` own the hook behavior
- [ ] Both shell hook files are reduced to stdin-parsing shims
- [ ] Verdict, evidence, oscillation, and metrics behavior matches the current hook fixtures
- [ ] Go and shell parity tests pass
