# Ledger Migration Implementation Plan

> **Goal:** Replace marker-file workflow truth with an event-sourced ledger while preserving existing behavior during phased rollout.
>
> **Architecture:** Hooks emit canonical evidence events into an append-only session ledger. Gates evaluate ledger state (with code-change invalidation boundaries) to decide allow/deny. Markers remain compatibility cache during migration and are later demoted.
>
> **Tech Stack:** Bash, jq, git, shell test harness (`tests/` + `claude/hooks/tests/`)
>
> **Design:** [DESIGN.md](./DESIGN.md)

## Scope

This plan covers Claude hook/gate evidence plumbing in this repo only:

1. Event writer and evaluator libraries.
2. Hook dual-write and gate integration.
3. Test expansion and phased mode rollout.

Out of scope:

1. tmux transport reliability rewrite.
2. Remote or shared persistent store.
3. Changes to review policy semantics.

## Task Granularity

- [x] **Standard** - ~200 lines of implementation (tests excluded), split if >5 files (default)
- [ ] **Atomic** - 2-5 minute steps with checkpoints (for high-risk: auth, payments, migrations)

## Tasks

- [ ] [Task 1](./tasks/TASK-ledger-01-schema-and-writer.md) - Define ledger schema, writer library, and dual-write event emission in existing hooks (deps: none)
- [ ] [Task 2](./tasks/TASK-ledger-02-evaluator-and-shadow-mode.md) - Build ledger evaluator and run gates in marker-enforced shadow mode with mismatch logging (deps: Task 1)
- [ ] [Task 3](./tasks/TASK-ledger-03-enforcement-cutover.md) - Switch gates to ledger enforcement with marker fallback and explicit mode control (deps: Task 2)
- [ ] [Task 4](./tasks/TASK-ledger-04-marker-demotion-and-retention.md) - Demote markers to compatibility cache, add ledger retention cleanup, and finalize docs/tests (deps: Task 3)

## Coverage Matrix

| Evidence Requirement | Produced In | Gate(s) Affected | Verified By |
|----------------------|-------------|------------------|-------------|
| `code_critic_approved` | Task 1 (`agent-trace.sh`) | codex + PR gates | Task 2 tests |
| `minimizer_approved` | Task 1 (`agent-trace.sh`) | codex + PR gates | Task 2 tests |
| `tests_passed` | Task 1 (`agent-trace.sh`) | PR gate | Task 2 tests |
| `checks_passed` | Task 1 (`agent-trace.sh`) | PR gate | Task 2 tests |
| `codex_review_completed` | Task 1 (`codex-trace.sh`) | codex + PR gates | Task 2 tests |
| `codex_approved` | Task 1 (`codex-trace.sh`) | PR gate | Task 2 tests |
| `pre_pr_verified` | Task 1 (`skill-marker.sh`) | PR gate | Task 2 tests |
| `code_changed` invalidation boundary | Task 1 (`marker-invalidate.sh`) | codex + PR gates | Task 2 tests |

## Dependency Graph

```
Task 1 ---> Task 2 ---> Task 3 ---> Task 4
```

## Task Handoff State

| After Task | State |
|------------|-------|
| Task 1 | Ledger schema and writer exist; hooks dual-write events and markers; marker enforcement unchanged |
| Task 2 | Evaluator exists; gates compute ledger verdict in shadow mode; mismatch logs available |
| Task 3 | Gates enforce ledger verdict; marker fallback still present |
| Task 4 | Marker path demoted; retention/cleanup finalized; migration docs complete |

## External Dependencies

| Dependency | Status | Blocking |
|------------|--------|----------|
| `jq` availability in hook runtime | Existing | Task 1 |
| Existing hook tests green baseline | Existing | Task 2+ |

## Verification Commands (per phase)

1. Baseline:
   - `bash tests/run-tests.sh`
2. Hook suites:
   - `bash claude/hooks/tests/run-all.sh`
3. Targeted new ledger tests (after implementation):
   - `bash claude/hooks/tests/test-ledger-lib.sh`
   - `bash claude/hooks/tests/test-ledger-eval.sh`
   - `bash claude/hooks/tests/test-ledger-gates.sh`

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

1. Source request: migrate marker truth to ledger with phased safety.
2. Reconciled by: dual-write -> shadow -> enforce -> marker demotion.
3. No unresolved conflicts.

## Definition of Done

- [ ] All task checkboxes complete
- [ ] All verification commands pass
- [ ] Gates can run in `off`, `shadow`, and `enforce` modes as specified
- [ ] PR and codex gate decisions are explainable from ledger evidence
