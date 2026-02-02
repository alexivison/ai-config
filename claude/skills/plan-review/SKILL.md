---
name: plan-review
description: Guidelines for reviewing planning documents (SPEC.md, DESIGN.md, PLAN.md, TASK*.md). Preloaded by plan-reviewer agent.
user-invocable: false
allowed-tools: Read, Grep, Glob
---

# Plan Review Guidelines

Review planning documents for completeness, clarity, and agent-executability.

## Reference Documentation

For detailed checklists, common issues, and examples, see `~/.claude/skills/plan-review/reference/plan-review-guidelines.md`. Load when reviewing unfamiliar patterns.

## Severity Levels

- **[must]** - Missing required sections, circular dependencies, ambiguous requirements - must fix
- **[q]** - Questions needing clarification before implementation
- **[nit]** - Minor improvements, formatting suggestions

## Quick Checklists

### SPEC.md
Required: Goal, User Stories, Acceptance Criteria, Out of Scope

### DESIGN.md
Required: Architecture Overview, Key Components, Data Flow, API/Interface, File Structure

### PLAN.md
Required: Header (Goal/Architecture/Tech Stack/Links), Task List, Dependencies

### TASK*.md
Required: Issue, Goal, Context, Files to Modify, Steps, Verification, Acceptance Criteria

## Key Quality Criteria

1. **Measurability** - Every requirement has verifiable acceptance criteria
2. **No Circular Dependencies** - Tasks form a DAG, not a cycle
3. **Agent-Executability** - Each task standalone with explicit paths and verification
4. **Appropriate Scope** - SPEC=requirements, DESIGN=architecture, TASK=implementation

## Output Format

```
## Plan Review Report

### Summary
One paragraph: overall quality assessment.

### Document: [filename]

#### Must Fix
- **Section** - Issue description. WHY it matters.

#### Questions
- **Section** - What needs clarification.

#### Nits
- **Section** - Suggestion for improvement.

### Verdict
**APPROVE** or **REQUEST_CHANGES** or **NEEDS_DISCUSSION**
One sentence explanation.
```

## Verdict Criteria

| Verdict | Condition |
|---------|-----------|
| APPROVE | No [must] issues, all required sections present |
| REQUEST_CHANGES | Has [must] issues that can be fixed |
| NEEDS_DISCUSSION | Ambiguous requirements, conflicting constraints, scope concerns |
