# Harness V2 — Simplification And Evolution Implementation Plan

> **Goal:** Simplify the harness first, then converge the surviving session system into one Go binary that runs as a Bubble Tea TUI when invoked as `party-cli` and as a scriptable CLI when invoked as `party-cli <subcommand>`.
>
> **Architecture:** Phase 1 hardens the current shell and hook layer. Phase 2 introduces `tools/party-cli/` as the shared implementation surface for state, tmux, and TUI foundations, then launches it in pane `0` (window 1) for sidebar and tracker layouts while Codex runs in a hidden window 0, preserving `PARTY_LAYOUT=classic` as a fallback. Phase 3 ports lifecycle, messaging, worker/master TUI behavior, picker flows, and cutover, while explicitly retaining `session/party-lib.sh` as the routing dependency for `tmux-codex.sh`.
>
> **Tech Stack:** Bash, tmux 3.6a, jq, Go 1.25.7, Cobra, Bubble Tea, Lip Gloss, Markdown
>
> **Specification:** [SPEC.md](./SPEC.md) | **Design:** [DESIGN.md](./DESIGN.md)

## Scope

This plan covers the current session harness under `session/`, the absorbed `docs/projects/sidebar-tui/` work, the existing `tools/party-tracker/` module, hook/rule debt called out in research, and the tmux transport seams that the new binary must share. It builds on the completed simplification baseline in `docs/projects/phase-simplification/PLAN.md` and does not reopen that project beyond the already-requested cleanup work around oscillation handling.

The former standalone sidebar evaluation phase is removed. `docs/projects/sidebar-tui/` is now an absorbed source project: its useful ideas become part of Harness V2, and no separate sidebar approval gate remains.

## Task Granularity

- [x] **Standard** — each task owns one coherent PR-sized slice, usually one command family, one UI surface, or one cleanup theme
- [ ] **Atomic** — not needed; the risky work is migration sequencing and contract ownership, not minute-by-minute execution

## Tasks

### Phase 1: Cleanup & Hardening

`quick-fix-workflow` target: Task 1 and Task 2 should remain eligible where the final diffs stay within the quick-fix limits. Task 3 is intentionally larger because it introduces a new hook library and dedicated tests.

- [x] [Task 1](./tasks/TASK1-prune-dead-code-and-docs-debt.md) — Remove dead transition code, backward-compat argument shims, stale task metadata, and merge the too-thin general rule file into `CLAUDE.md` (deps: none)
- [x] [Task 2](./tasks/TASK2-harden-shell-prereqs-and-transport.md) — Fail fast on missing `jq`, tighten temp-file and hook quoting behavior, require authoritative pane-role routing, and surface tmux send failures on stderr (deps: Task 1)
- [x] [Task 3](./tasks/TASK3-extract-oscillation-and-add-hook-coverage.md) — Extract oscillation detection into `claude/hooks/lib/oscillation.sh` and add the missing dedicated `worktree-guard` hook suite (deps: none)

### Phase 2: Unified Binary Foundation

- [x] [Task 4](./tasks/TASK4-scaffold-unified-party-cli.md) — Create `tools/party-cli/` with Cobra root/no-arg TUI behavior, shared config/logging, and package seams for state, tmux, session, and TUI code (deps: Task 2, Task 3)
- [x] [Task 5](./tasks/TASK5-port-state-store-and-discovery.md) — Port manifest CRUD, flock-based locking, and session discovery into typed Go state packages while preserving the current manifest schema (deps: Task 4)
- [x] [Task 6](./tasks/TASK6-port-tmux-service-and-pane-capture.md) — Port tmux session queries, role resolution, delivery-confirmed sends, pane capture, popup helpers, and window-management helpers into shared Go packages (deps: Task 4, Task 5)
- [x] [Task 7](./tasks/TASK7-absorb-tracker-runtime-into-tui-foundation.md) — Reuse `party-tracker` Bubble Tea structure, Lip Gloss palette, and narrow-width behavior inside `party-cli`, with auto-selection between worker sidebar mode and master tracker mode (deps: Task 5, Task 6)
- [x] [Task 8](./tasks/TASK8-port-read-only-cli-commands.md) — Port `list`, `status`, and `prune` as safe read-only CLI commands backed by the shared state and tmux services (deps: Task 5, Task 6)
- [x] [Task 9](./tasks/TASK9-launch-party-cli-pane-and-sidebar-layouts.md) — Launch `party-cli` in window 1 (pane `0`), keep master tracker layout, add sidebar layout as opt-in for standard and worker sessions (`PARTY_LAYOUT=classic` stays default), move Codex to a hidden window 0 within the same tmux session, and configure the tmux status bar to visually distinguish agent windows from workspace windows (deps: Task 6, Task 7, Task 8)

### Phase 3: Feature Parity + TUI Views

- [x] [Task 10](./tasks/TASK10-port-session-lifecycle-and-worker-spawn.md) — Port `start`, `continue`, `stop`, `delete`, `promote`, and worker-spawn flows while Bash entrypoints still coexist as wrappers (deps: Task 8, Task 9)
- [ ] [Task 11](./tasks/TASK11-port-messaging-and-report-back-commands.md) — Port `relay`, `broadcast`, `read`, `report`, and worker enumeration onto the delivery-confirmed tmux service without taking ownership of `tmux-codex.sh` itself (deps: Task 8, Task 9, Task 10)
- [ ] [Task 12](./tasks/TASK12-build-worker-sidebar-view.md) — Build the worker/standalone sidebar view with Codex status, evidence summary, session info, offline handling, and peek popup backed by `codex-status.json` plus pane capture (deps: Task 7, Task 9, Task 11)
- [ ] [Task 13](./tasks/TASK13-build-master-tracker-view.md) — Build the master tracker view inside `party-cli` with worker list, attach, relay, spawn, and manifest inspection, reusing the existing tracker interaction patterns (deps: Task 7, Task 10, Task 11)
- [ ] [Task 14](./tasks/TASK14-absorb-picker-into-unified-binary.md) — Replace the Bash picker flow with `party-cli picker`, preserving preview/selection behavior through the new read/write services and an `fzf` fallback where it still buys simplicity (deps: Task 8, Task 10)
- [ ] [Task 15](./tasks/TASK15-cut-over-wrappers-and-retire-duplicate-bash.md) — Make `party-cli` the primary implementation surface, reduce `party.sh`, `party-master.sh`, `party-relay.sh`, and `party-picker.sh` to thin wrappers or retire them, and explicitly retain `party-lib.sh` for `tmux-codex.sh` and classic routing (deps: Task 12, Task 13, Task 14)

## Coverage Matrix

| New Field/Endpoint | Added In | Code Paths Affected | Handled By | Converter Functions |
|--------------------|----------|---------------------|------------|---------------------|
| `party-cli` root no-arg TUI mode | Task 4 | pane `0` entrypoint, local operator launch, test harnesses | Task 4 through Task 15 | Cobra parse -> `cmd/root.go` -> `internal/tui` launcher |
| Shared typed state/discovery layer | Task 5 | manifest CRUD, discovery, visible-session filtering, tracker/sidebar data loads | Task 5 through Task 15 | replaces `party_state_*` and `discover_session()` in `session/party-lib.sh:67-213`, `session/party-lib.sh:295-332` |
| Shared tmux service with delivery result | Task 6 | session queries, pane lookup, relay, popup, snippet capture, later TUI actions | Task 6 through Task 15 | replaces `tmux_send()` and direct `exec.Command("tmux", ...)` callers in `session/party-lib.sh:347-390`, `tools/party-tracker/actions.go:24-66`, `tools/party-tracker/workers.go:74-127` |
| Shared TUI foundation with mode auto-selection | Task 7 | worker sidebar shell, master tracker shell, width-adaptive rendering | Task 7, Task 9, Task 12, Task 13, Task 15 | worker/master manifest -> TUI mode selection |
| `party-cli list|status|prune` | Task 8 | operator inspection, cleanup flow, later picker/query reuse | Task 8, Task 10, Task 14, Task 15 | replaces `party_list()` and `party_prune_manifests()` in `session/party.sh:364-438` |
| `PARTY_LAYOUT=sidebar|classic` launch contract | Task 9 | standard/worker launch, resume, docs, fallback semantics | Task 9 through Task 15 | env parse -> pane layout + hidden-window creation |
| Hidden Codex window (window 0) | Task 9 | shell launchers, routing helpers, worker sidebar, tmux status bar theming | Task 9, Task 11, Task 12, Task 15 | session window management; no manifest schema change, no separate session |
| `party-cli start|continue|stop|delete|promote|spawn` | Task 10 | standard sessions, worker sessions, master promotion, teardown | Task 10, Task 13, Task 14, Task 15 | replaces `party_start()`, `party_continue()`, `party_launch_master()`, `party_promote()` and related shell flows |
| `party-cli relay|broadcast|read|report|workers` | Task 11 | master/worker messaging, report-back workflows, tracker actions, shell wrapper cutover | Task 11, Task 12, Task 13, Task 15 | replaces `session/party-relay.sh:45-218` and current worker report-back usage in `claude/CLAUDE.md:88-92`, `claude/skills/party-dispatch/SKILL.md:103` |
| Runtime status file `codex-status.json` | Task 12 | `tmux-codex.sh` writes dispatch/in-progress state, `tmux-claude.sh` writes completion/idle state; worker sidebar reads on poll | Task 12, Task 15 | two-script status JSON -> worker sidebar card view model |
| `party-cli` master tracker actions | Task 13 | attach, relay, spawn, manifest inspect, worker snippets | Task 13, Task 15 | shared state/tmux services -> TUI commands |
| `party-cli picker` | Task 14 | interactive attach/resume/delete flows and preview rendering | Task 14, Task 15 | replaces `session/party-picker.sh:21-181` and `session/party-preview.sh:21-64` |
| Thin-wrapper cutover with `party-lib.sh` retained | Task 15 | shell entrypoints, docs, tests, tmux-codex dependency boundary | Task 15 | shell argv/env -> `party-cli` subcommands, except retained `party-lib.sh` routing helpers |

**Validation:** The revised plan keeps persisted schema change to a minimum. The only new durable contract is the `sidebar|classic` layout behavior (classic default, sidebar opt-in until Task 10 proves promotion parity) plus the hidden-window architecture (window 0 = Codex, window 1 = workspace panes); `party-lib.sh` remains the library seam for `tmux-codex.sh`, so the plan no longer pretends Bash disappears entirely. Session death automatically destroys all windows — no orphan problem, no companion cleanup.

**Open concern — manifest locking coexistence (Task 5):** Task 5 introduces flock-based locking in Go, but Bash writers (`party-lib.sh:44-63`, `party.sh:82-83`, `tmux-claude.sh:12-17`) still use the mkdir lock protocol. During the migration window both sides would mutate manifests under different locks. Task 5 must either keep the mkdir protocol in Go until Bash writers are retired, or convert both Bash and Go to a shared lock-file scheme in the same task.

## Dependency Graph

```text
                                                         ┌───> Task 7 ─────────────────────────────┐
Task 1 ───> Task 2 ──┐                                  │                                          │
                      ├───> Task 4 ───> Task 5 ───> Task 6                                         │
Task 3 ───────────────┘                    │             │                                          │
                                           └─────────────┴───> Task 8 ───> Task 9 ───> Task 10 ───>│───> Task 11 ───┬───> Task 12 ───┐
                                                                             │           │          │                │                │
                                                                             │           └──────────┼── Task 14 ─────┤                │
                                                                             │                      │                ├───> Task 13 ───┼───> Task 15
                                                                             │                      └────────────────┘                │
                                                                             └────────────────────────────────────────────────────────┘

Key cross-edges: Task 7 ──> {Task 9, Task 12, Task 13}; Task 8 ──> {Task 11, Task 14}
Task 9 ──> Task 12; Task 10 ──> {Task 13, Task 14}
```

## Task Handoff State

| After Task | State |
|------------|-------|
| Task 1 | Dead transition code, backward-compat shims, and stale rule/task debris are removed |
| Task 2 | Shell flows fail loudly on missing prerequisites, only authoritative pane metadata is trusted, and tmux send failures are visible |
| Task 3 | Oscillation logic is isolated and `worktree-guard.sh` has dedicated regression coverage |
| Task 4 | `tools/party-cli/` builds, and the root command cleanly distinguishes no-arg TUI mode from subcommand CLI mode |
| Task 5 | Manifest CRUD, locking, and visible-session discovery exist in typed Go without changing the manifest schema |
| Task 6 | Shared tmux queries, delivery results, capture, popup, and window-management helpers exist for both CLI and TUI surfaces |
| Task 7 | `party-cli` can render a reusable TUI shell and choose master versus worker mode from live session context |
| Task 8 | Read-only CLI parity exists for list/status/prune, backed by the shared Go services |
| Task 9 | Real sessions can launch with `party-cli` in window 1 (pane `0`), support sidebar layout as opt-in (`PARTY_LAYOUT=sidebar`), preserve classic as default, keep Codex alive in a hidden window 0 when sidebar mode is active, and visually distinguish agent vs. workspace windows in the tmux status bar |
| Task 10 | Lifecycle commands and worker spawning work through `party-cli`, with shell entrypoints still available as wrappers |
| Task 11 | Relay, broadcast, read, report, and worker-enumeration flows run through `party-cli` with explicit delivery results |
| Task 12 | Worker sidebar users see Codex status, evidence summaries, session context, and a guarded peek popup in the unified TUI |
| Task 13 | Master users get the former tracker behavior from the same `party-cli` binary that powers worker sidebars and CLI commands |
| Task 14 | Picker flows no longer depend on the old Bash pipeline and preview glue |
| Task 15 | Duplicate Bash entrypoints are retired or thinned, `party-cli` is the primary implementation surface, and `party-lib.sh` remains the declared tmux-codex dependency |

## External Dependencies

| Dependency | Status | Blocking |
|------------|--------|----------|
| `jq` for Bash-era manifest access | Present today but inconsistently enforced | Tasks 1, 2 |
| tmux 3.6a pane/session behavior and popup support | Existing harness contract | Tasks 2, 6, 9, 10, 11, 12, 13, 14, 15 |
| Go 1.25.7 toolchain | Already required by `tools/party-tracker` | Tasks 4 through 15 |
| Cobra | Command tree and flag/env binding (Viper removed — no config files or hierarchical config to justify it; `os.Getenv()` + Cobra flags suffice) | Task 4 onward |
| Bubble Tea, Lip Gloss, Bubbles | Already in the tracker module and reused here | Tasks 7, 12, 13 |
| `fzf` or a clear built-in fallback | Existing picker dependency | Task 14 |

## Plan Evaluation Record

PLAN_EVALUATION_VERDICT: PASS

Evidence:
- [x] Existing standards referenced with concrete paths
- [x] Data transformation points mapped
- [x] Tasks have explicit scope boundaries
- [x] Dependencies and verification commands listed per task
- [x] Requirements reconciled against source inputs
- [x] Whole-architecture coherence evaluated
- [x] UI-bearing tasks point at design artifacts

Source reconciliation:
- The new plan resolves the earlier architectural hole by keeping `tmux-codex.sh` on `session/party-lib.sh`. That dependency is explicit in `claude/skills/codex-transport/scripts/tmux-codex.sh:9`, `claude/skills/codex-transport/scripts/tmux-codex.sh:31`, and `claude/skills/codex-transport/scripts/tmux-codex.sh:37`.
- The old tracker is not discarded; its reusable rendering and action patterns are plainly visible in `tools/party-tracker/main.go:81-358`, `tools/party-tracker/main.go:427`, `tools/party-tracker/workers.go:65-153`, and `tools/party-tracker/actions.go:24-66`.
- Worker report-back remains in scope this time. It is part of the live relay surface at `session/party-relay.sh:7-8`, `session/party-relay.sh:45-51`, `session/party-relay.sh:215-218`, and it is documented as a current workflow in `claude/CLAUDE.md:88-92` and `claude/skills/party-dispatch/SKILL.md:103`.
- The hidden-Codex concern from `docs/projects/sidebar-tui/` is absorbed rather than evaluated separately. The revised plan keeps only the pieces still needed for the unified binary: sidebar layout, hidden Codex window, runtime status file, classic fallback, and popup peek.
- `docs/projects/phase-simplification/PLAN.md` remains the accepted evidence-model baseline; only the follow-on cleanup from research is carried forward here.

## Definition of Done

- [ ] All task checkboxes complete
- [ ] Phase 1 removes the known dead-code and silent-failure paths from the research brief
- [ ] `party-cli` runs as TUI with no args and as CLI with subcommands from the same binary
- [ ] Standard and worker sessions support sidebar layout with Codex in hidden window 0 (opt-in via `PARTY_LAYOUT=sidebar` until promotion + status parity are proven, then flipped to default), with `PARTY_LAYOUT=classic` preserving the old visible-Codex path
- [ ] Master tracker behavior lives inside `party-cli`
- [ ] Lifecycle, relay, report-back, picker, and tracker flows are owned by `party-cli`
- [ ] `tmux-codex.sh` continues to function through retained `party-lib.sh` helpers
- [ ] Bash entrypoints are retired or reduced to thin wrappers where planned
- [ ] Regression suites for shell, hooks, and Go all pass
- [ ] SPEC acceptance criteria are satisfied
