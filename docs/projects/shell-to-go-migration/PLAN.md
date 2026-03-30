# Shell-To-Go Hook Migration Implementation Plan

> **Goal:** Migrate the remaining shell-based hook and harness logic into `party-cli` subcommands without changing the live hook contract, evidence JSONL schema, or PR gate semantics.
>
> **Architecture:** Land the Go seams in dependency order: `internal/evidence` first, then Claude UUID resolution, metrics, oscillation, and finally hook-facing trace and gate subcommands under `party-cli hook ...`. Shell entrypoints remain tiny `jq`-based shims because Claude registers shell commands in `claude/settings.json:84-164`; the binary becomes the single implementation surface while `/tmp` evidence files and `~/.claude/logs` metrics files remain backward compatible.
>
> **Tech Stack:** Bash shims, `jq`, Go 1.25.x, Cobra, tmux, git, JSONL
>
> **Specification:** external task brief in this request | **Design:** inline in this PLAN and TASK files

## Scope

This plan covers the remaining shell-owned hook systems anchored in `claude/hooks/lib/evidence.sh:36-352`, `claude/hooks/lib/session-id-helper.sh:18-100`, `claude/hooks/lib/review-metrics.sh:26-412`, `claude/hooks/lib/oscillation.sh:17-105`, `claude/hooks/agent-trace-stop.sh:15-157`, `claude/hooks/codex-trace.sh:13-177`, `claude/hooks/pr-gate.sh:17-94`, and `claude/hooks/skill-marker.sh:7-34`. The receiving Go seams already exist in `tools/party-cli/cmd/root.go:66-104`, `tools/party-cli/internal/state/store.go:25-217`, `tools/party-cli/internal/tmux/query.go:40-102`, `tools/party-cli/internal/session/start.go:15-128`, and `tools/party-cli/internal/tui/model.go:409-460`.

In scope:
- Evidence storage, hashing, checks, triage overrides, and TUI evidence readers
- Party session name to Claude UUID resolution for tracker and hook-adjacent flows
- Review metrics recording, reporting, and the review-metrics CLI surface
- Oscillation detection, agent trace hooks, Codex trace/gate hooks, PR gate, and skill marker
- Incremental conversion of shell hook entrypoints into thin shims that `exec party-cli ...`

Out of scope:
- `tmux-codex.sh`, `tmux-claude.sh`, `session/party.sh`, and `session/party-relay.sh`
- `worktree-track.sh`, `worktree-guard.sh`, `wizard-guard.sh`, `session-cleanup.sh`, `register-agent-id.sh`, and `push-lint-reminder.sh`
- Any new binary besides `party-cli`

## CLI Shape

- `party-cli evidence diff-hash|diff-stats|append|check|check-all|override`
- `party-cli session resolve-claude-id`
- `party-cli metrics finding|summary|triage|resolved|cycle|report|export|report-all`
- `party-cli hook agent-trace-start|agent-trace-stop|codex-trace|codex-gate|pr-gate|skill-marker`
- `internal/oscillation`, `internal/trace`, and `internal/gate` stay package seams; the hook subcommands are the only public execution surface for automated hook traffic

Each shim keeps Claude's shell contract: parse the minimal routing fields from stdin with `jq`, pass them as flags, and forward the raw JSON payload on stdin so Go owns the real parsing and response formatting.

## Phase Scope And Risk

| Phase | Tasks | Estimated Files Touched | Estimated New Go | Estimated Shell Deleted/Reduced | Primary Risk |
|-------|-------|-------------------------|------------------|----------------------------------|--------------|
| Phase 1: Foundations | Tasks 1-3 | 18-26 | 1200-1700 LOC | 0-80 LOC | High: diff-hash parity, file-lock semantics, UUID resolution order |
| Phase 2: Hook Logic | Tasks 4-7 | 24-34 | 1500-2200 LOC | 700-1100 LOC | Medium-high: verdict parsing mistakes or false PR/Codex blocks |
| Phase 3: Cutover | Task 8 | 10-16 | 400-700 LOC | 500-900 LOC | Medium: retiring shell business logic without breaking operator muscle memory |

## Task Granularity

- [x] **Standard** — each PR owns one shared package seam or one hook family with its shim cutover
- [ ] **Atomic** — not used; the risky work is contract parity, not minute-by-minute editing

## Tasks

### Phase 1: Foundations

- [ ] [Task 1](./tasks/TASK1-port-evidence-core-and-cli.md) — Port the evidence core into `internal/evidence`, wire `party-cli evidence ...`, and replace the ad hoc TUI evidence readers with the shared package (deps: none)
- [ ] [Task 2](./tasks/TASK2-port-session-namespace-resolution.md) — Port party session name to Claude UUID resolution into Go and make tracker/TUI evidence lookup use one shared resolver (deps: Task 1)
- [ ] [Task 3](./tasks/TASK3-port-review-metrics-cli.md) — Port review metrics recording/reporting into `internal/metrics` and `party-cli metrics ...`, then reduce the shell metrics script to a wrapper (deps: Task 1)

### Phase 2: Hook Logic

- [ ] [Task 4](./tasks/TASK4-port-oscillation-detection.md) — Port oscillation detection into `internal/oscillation` with same-hash and cross-hash parity fixtures (deps: Task 1)
- [ ] [Task 5](./tasks/TASK5-port-agent-trace-hook-subcommands.md) — Port `SubagentStart` and `SubagentStop` into `party-cli hook agent-trace-*` and reduce both shell hooks to shims (deps: Task 2, Task 3, Task 4)
- [ ] [Task 6](./tasks/TASK6-port-codex-hooks-and-skill-marker.md) — Port Codex trace/gate and skill-marker flows into `party-cli hook ...` subcommands and retire their shell logic (deps: Task 2, Task 3)
- [ ] [Task 7](./tasks/TASK7-port-pr-gate-hook-and-diagnostics.md) — Port PR gate evaluation into `internal/gate` and `party-cli hook pr-gate`, preserving docs-only and quick-tier behavior (deps: Task 1, Task 2, Task 5, Task 6)

### Phase 3: Cutover

- [ ] [Task 8](./tasks/TASK8-cut-over-shims-and-retire-shell-libraries.md) — Finish the cutover by retiring legacy shell business logic, consolidating regression coverage in Go, and keeping only thin shell shims at the hook edge (deps: Task 5, Task 6, Task 7)

## Coverage Matrix

| New Field/Endpoint | Added In | Code Paths Affected | Handled By | Converter Functions |
|--------------------|----------|---------------------|------------|---------------------|
| Evidence JSONL reader/writer parity via `party-cli evidence ...` | Task 1 | TUI sidebar/tracker, later hook subcommands, stale-evidence diagnostics | Tasks 1, 4, 5, 6, 7, 8 | `internal/evidence.Record` marshal/unmarshal, diff-hash builder, worktree resolver |
| Party session name -> Claude UUID resolver via `party-cli session resolve-claude-id` | Task 2 | `internal/tui/model.go`, `internal/tui/tracker_actions.go`, manual metrics flows, future hook helpers | Tasks 2, 5, 6, 7, 8 | manifest `claude_session_id`, tmux env query, worktree override scan, evidence-file scan |
| Review metrics JSONL and reports via `party-cli metrics ...` | Task 3 | manual triage/resolution, agent-trace stop, codex-trace, session reports | Tasks 3, 5, 6, 8 | `internal/metrics.Event` marshal/unmarshal, iteration counter, report renderer |
| Oscillation override pipeline | Task 4 | critic verdict processing in agent-trace stop | Tasks 4, 5, 8 | verdict fingerprint normalizer, evidence append/override bridge |
| Hook endpoints under `party-cli hook ...` | Tasks 5-7 | Claude hook commands in `claude/settings.json:84-164` | Tasks 5, 6, 7, 8 | stdin JSON -> hook input struct -> evidence/metrics/gate packages |
| Shell shim contract at the Claude edge | Task 8 | `claude/hooks/*.sh`, retained wrapper scripts, docs/examples | Task 8 | `jq` stdin extraction -> Cobra flags, raw stdin passthrough, hook JSON response encoder |

**Validation:** No persisted schema changes are planned. The migration is about moving ownership, not inventing a new file format. Existing evidence and metrics files must remain readable after each merged task.

## Dependency Graph

```text
Task 1 ───┬───> Task 2 ───┬───> Task 5 ───┐
          │               │               │
          │               ├───> Task 6 ───┼───> Task 7 ───> Task 8
          │               │               │
          ├───> Task 3 ───┘               │
          │                               │
          └───> Task 4 ───────────────────┘
```

## Task Handoff State

| After Task | State |
|------------|-------|
| Task 1 | `party-cli` owns evidence reads/writes, hash computation, diagnostics, and TUI evidence rendering helpers |
| Task 2 | One Go resolver can map a party session name to the Claude UUID used by evidence and metrics files |
| Task 3 | Metrics writes and reports flow through `party-cli metrics ...`; the shell metrics script is only a wrapper |
| Task 4 | Oscillation detection is package-owned and ready for hook consumers |
| Task 5 | Subagent start/stop hooks execute Go code through shims and preserve verdict/evidence/metrics behavior |
| Task 6 | Codex trace/gate and skill marker run through Go subcommands with shell shims only |
| Task 7 | PR creation is gated by Go code, with docs-only, quick-tier, and stale-evidence behavior preserved |
| Task 8 | Hook business logic lives only in Go; shell files are compatibility edges and smoke-test surfaces |

## External Dependencies

| Dependency | Status | Blocking |
|------------|--------|----------|
| Claude hook registration stays shell-command based in `claude/settings.json:84-164` | Fixed contract | Tasks 5-8 |
| `jq` remains available for the thin shell shims | Existing dependency | Tasks 5-8 |
| Git diff semantics from `claude/hooks/lib/evidence.sh:43-152` | Existing contract | Tasks 1-7 |
| tmux session/env inspection from `tools/party-cli/internal/tmux/query.go:40-102` and `claude/hooks/register-agent-id.sh:31-37` | Existing contract | Tasks 2, 5, 6, 7 |
| Shell parity corpus in `claude/hooks/tests/test-*.sh` | Existing oracle | Tasks 1-8 |
| TOON findings file shape consumed by `claude/hooks/codex-trace.sh:81-161` | Existing contract | Task 6 |

## Plan Evaluation Record

PLAN_EVALUATION_VERDICT: PASS

Evidence:
- [x] Existing standards referenced with concrete paths
- [x] Data transformation points mapped
- [x] Tasks have explicit scope boundaries
- [x] Dependencies and verification commands listed per task
- [x] Requirements reconciled against source inputs
- [x] Whole-architecture coherence evaluated
- [x] UI/component tasks include design references

Source reconciliation:
- The brief lists `session-id-helper.sh` as a dependency of agent/codex/pr-gate flows, but the current hook files mostly consume `session_id` directly from hook JSON (`claude/hooks/agent-trace-stop.sh:28`, `claude/hooks/codex-trace.sh:33`, `claude/hooks/pr-gate.sh:21`). The resolver still belongs in scope because the tracker and TUI evidence paths rely on the party-session-to-Claude-UUID bridge (`tools/party-cli/internal/tui/tracker_actions.go:153-164`, `tools/party-cli/internal/tui/model.go:409-429`).
- No new SPEC.md or DESIGN.md is introduced here because the user explicitly requested PLAN/TASK artifacts only; the external task brief and the task files carry the design detail that the planning template normally expects.
- The shell edge remains intentionally narrow because `claude/settings.json:84-164` registers shell commands, not binaries. The migration target is one implementation surface behind those shims, not the removal of `.sh` files altogether.

## Definition of Done

- [ ] All task checkboxes complete
- [ ] Every migrated hook entrypoint is a thin shell shim that `exec`s `party-cli`
- [ ] Evidence and metrics JSONL formats remain backward compatible with existing files
- [ ] Diff hash, diff stats, worktree resolution, and oscillation parity are proven by Go tests against the shell fixture corpus
- [ ] Tracker and sidebar evidence lookup work from a party session name via the shared UUID resolver
- [ ] Excluded shell scripts remain shell-owned and untouched
- [ ] Relevant Go tests and retained shell smoke tests pass
