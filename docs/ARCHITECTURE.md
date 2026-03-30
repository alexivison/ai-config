# Harness Architecture

## What This Harness Is

An **implementation governance engine**. It governs how code gets built, reviewed, and shipped — not how work gets planned.

Its job is three things:

1. **Enforce discipline** — RED→GREEN test evidence, diff_hash freshness, no stale approvals
2. **Review rigorously** — code-critic, minimizer, scribe, codex (The Wizard), sentinel, with formal dispute resolution
3. **Gate delivery** — PR gate requires evidence at the current diff_hash, no self-approval, no shortcuts

## What This Harness Is Not

It is **not a planning tool**. It does not care:

- What format the task was specified in (TASK*.md, OpenSpec, Linear ticket, napkin sketch)
- What planning system produced the requirements (our plan-workflow, OpenSpec, Notion, a conversation)
- Whether the planning system uses checkboxes, kanban boards, or carrier pigeons

The engine needs exactly four things from any planning source, all as plain text:

```
work_packet:
  scope:
    in_scope: [text]       # What this task covers
    out_of_scope: [text]   # What it must not touch
  requirements: [text]     # What to verify against the diff
  goal: text               # One-line summary for PR / review context
```

Any planning system that can produce these four fields plugs into the execution engine. The engine runs the same review pipeline, the same evidence gates, the same PR enforcement regardless of where the work came from.

## The Execution Spine

This is the engine's core sequence and the source of its value:

```
/write-tests (RED evidence)
    ↓
implement (GREEN evidence)
    ↓
minimality + scope gate
    ↓
code-critic + minimizer + scribe  (parallel, gating)
    ↓
codex review + sentinel  (mandatory, no iteration cap)
    ↓
dispute resolution if needed
    ↓
/pre-pr-verification (test-runner + check-runner)
    ↓
PR gate (evidence at current diff_hash)
    ↓
draft PR
```

Every step produces evidence. Evidence is bound to the diff_hash — editing code after approval automatically invalidates all prior evidence. You cannot ship without fresh proof.

## The Review Layers

| Reviewer | Role | Gating? |
|----------|------|---------|
| **code-critic** | Correctness, SRP, DRY, bugs | Yes |
| **minimizer** | Unnecessary complexity, bloat, scope creep | Yes |
| **scribe** | Requirements fulfillment — did we build what was asked? | Yes |
| **codex (The Wizard)** | Deep reasoning review, no iteration cap | Yes |
| **sentinel** | Adversarial security and integration review | Advisory |

All reviewers receive the same inputs from the work_packet: scope (text) and requirements (text). They are planning-format-blind.

## Planning Providers

Planning systems connect to the engine through **providers**. A provider's job is to resolve its native artifacts into a `work_packet`. The engine does not know or care how that resolution happens.

### Classic Provider (TASK*.md)

The original provider. Reads a TASK file, extracts "In Scope" / "Out of Scope" sections, requirements, and a goal summary.

### OpenSpec Provider

Reads `proposal.md`, `specs/` deltas, `design.md`, and the selected task from `tasks.md`. Extracts scope from proposal capability boundaries and design Non-Goals. Extracts requirements from Given-When-Then scenarios in delta specs. Produces the same text-based work_packet.

### Future Providers

Any system that can produce scope + requirements + goal as text. Linear tickets, Notion docs, GitHub issues, verbal descriptions — all valid inputs as long as the provider can extract the four fields.

## Key Design Principles

- **Planning may move, execution doth not.** The engine's review and evidence spine is the valuable part. Planning format is a replaceable input.
- **Evidence before claims.** No assertions without proof. Test output, file:line references, grep results. "Should work" is not evidence.
- **Fresh evidence only.** diff_hash binding means stale approvals are automatically ignored. Edit code after approval → re-verify everything.
- **No self-approval.** The Wizard decides the verdict. Workers cannot approve their own work.
- **Dispute, don't bypass.** When reviewers disagree, the protocol is structured debate with evidence — not ignoring findings or capping iterations.

## File Map

| Path | Purpose |
|------|---------|
| `claude/rules/execution-core.md` | The execution sequence, gates, decision matrix, dispute resolution |
| `claude/rules/clean-code.md` | Code quality standards (LoB, SRP, YAGNI, DRY, KISS) |
| `claude/skills/task-workflow/SKILL.md` | The execution engine skill |
| `claude/agents/scribe.md` | Requirements fulfillment auditor |
| `claude/agents/code-critic.md` | Correctness reviewer |
| `claude/agents/minimizer.md` | Complexity reviewer |
| `claude/agents/sentinel.md` | Adversarial reviewer |
| `claude/hooks/lib/evidence.sh` | Evidence system (JSONL, diff_hash) |
| `claude/hooks/pr-gate.sh` | PR creation gate |
| `claude/skills/codex-transport/` | Wizard communication layer |
