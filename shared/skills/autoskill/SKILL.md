---
name: autoskill
description: Learns from session feedback to extract durable preferences and propose skill updates. Use when the user says "learn from this session", "remember this pattern", or invokes /autoskill.
user-invocable: true
---

# Autoskill

Extract durable preferences and create/update skills from session feedback or documents.

## Modes

| Mode | Trigger | Source |
|------|---------|--------|
| **Session** | `/autoskill`, "learn from this session" | Current conversation |
| **Document** | `/autoskill [url or path]`, "learn from this doc" | Book, article, codebase |

---

# Mode 1: Session Learning

Two independent lanes, both on every activation:

| Lane | Focus |
|------|-------|
| **Lane 1: Preferences** | User corrections, patterns, approvals → extract durable preferences |
| **Lane 2: Flow Violations** | Sequence deviations, illegitimate pauses, stale evidence → audit autonomous flow |

Lane 2 runs only when a workflow was detected (see Workflow Identification). If none detected, skip silently.

## Lane 1: Preference Signals

### Signal Detection

| Signal Type | Value |
|-------------|-------|
| Corrections | Highest — "No, use X instead of Y" |
| Repeated patterns | High — same feedback 2+ times |
| Approvals | Supporting — "Yes, that's right" |

Ignore: one-offs, ambiguous, contradictory signals.

### Quality Filter

Capture if: repeated or stated as general rule, applies to future sessions, specific and actionable, new beyond standard practices.

**Worth capturing:** Project conventions, team preferences, domain terminology, architectural decisions, workflow preferences.

**Skip:** General best practices, language/framework conventions, common library usage.

## Lane 2: Flow Violations

### Workflow Identification

**Tier 1 (authoritative):** Explicit skill invocations (`task-workflow`, `bugfix-workflow`).

**Tier 2 (fallback):** Heuristic — TASK*.md + implementation = task-workflow, bug + regression test = bugfix-workflow. Flag as "inferred."

### Expected Sequences

| Step | task | bugfix |
|------|:----:|:------:|
| /write-tests | C | M |
| implement | M | M |
| GREEN (test-runner) | M | M |
| checkboxes (TASK+PLAN) | M | -- |
| code-critic | M | M |
| minimizer | M | M |
| wizard | M | M |
| /pre-pr-verification | M | M |
| commit + PR | M | M |

M = mandatory, C = conditional, -- = N/A

### Violation Checks

**Check 1: Step Ordering & Completeness** (HIGH confidence)
Verify mandatory steps executed in order. Guard: legitimate pause points (NEEDS_DISCUSSION, 3-strikes, investigation findings, user-initiated, oscillation detected, iteration cap hit) are valid terminal states — don't flag downstream steps.

**Check 2: Illegitimate Pauses** (MED-HIGH confidence)
Detect assistant-initiated stops between mandatory steps without valid reason. Signals: "Should I continue?", "Would you like me to...", stopping after partial completion.

**Check 3: Evidence Freshness** (MED-HIGH confidence)
Code edits after verification invalidate it. Check for claims without fresh evidence, tentative language as verification claim.

### Routing Triage

| Violation Class | Target |
|-----------------|--------|
| Behavior drift | Workflow skill SKILL.md |
| Rule ambiguity | autonomous-flow.md or execution-core.md |
| Enforcement gap | Hook file |

---

# Mode 2: Document Learning

1. Read source (URL or file)
2. Extract techniques, methodologies, principles not already in skills
3. Filter for novelty — skip known/standard content
4. Propose updates to existing skills or new skill creation

---

# Creating New Skills (TDD)

3+ related signals not fitting existing skills → new skill.

1. **RED** — Document the gap (problem observed, desired behavior)
2. **GREEN** — Create minimal `~/.claude/skills/<name>/SKILL.md`
3. **REFACTOR** — Close loopholes, resist scope creep

---

# Signal Routing

```
Signal about...
├── Workflow/process → Skill
├── Agent behavior → Agent definition or agent skill
├── Code style → Rules
├── Global preferences → CLAUDE.md
├── Flow violation → Workflow skill / rule / hook (per routing triage)
└── Doesn't fit → New skill (TDD)
```

---

# Output Format

```markdown
## Autoskill: [session/document title]

### Signals
| # | Type | Quote/Context |
|---|------|---------------|

**Detected:** N updates, N new skills, N flow violations

### Proposed Updates
#### ▸ [1] SKILL-NAME — `HIGH`
**Signal:** "quote"
**File:** path
**Current:** > existing text
**Proposed:** > new text
**Rationale:** One sentence.

### Flow Adherence Report
**Workflow(s) detected:** {type | none (skipped)}

| # | Check | Verdict | Confidence |
|---|-------|---------|------------|
| 1 | Step ordering | PASS/VIOLATION | HIGH/MED |
| 2 | Illegitimate pauses | PASS/VIOLATION | HIGH/MED |
| 3 | Evidence freshness | PASS/VIOLATION | HIGH/MED/LOW |

**Apply changes?** [all / high-only / selective / none]
```

## Confidence Levels

- **HIGH** — Explicit, repeated, or clearly generalizable
- **MED** — Single instance, appears intentional
- **LOW** — Lexical match only. Report-only, never propose edits.

Always wait for explicit approval before editing.

---

# Constraints

- Never delete rules without instruction
- Prefer additive changes over rewrites
- Skip if no actionable signals
- New skills require RED phase first
