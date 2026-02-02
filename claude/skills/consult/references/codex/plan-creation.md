# Plan Creation (Codex)

**Trigger:** "create plan", "plan feature", "break down", "implementation plan"

Creates comprehensive planning documents for a feature. Codex analyzes the codebase and generates structured plans.

## Command

```bash
codex exec -s read-only "Create implementation plan for: {feature description}.

Analyze the codebase to understand:
1. Existing patterns and architecture
2. Related components and dependencies
3. Test patterns used in the project

Generate planning documents:

## SPEC.md
- Overview and goals
- User stories (as a..., I want..., so that...)
- Requirements with clear acceptance criteria
- Out of scope items

## DESIGN.md (if substantial feature)
- Architecture decisions
- Component design
- Data flow
- API contracts (if applicable)

## PLAN.md
- Task breakdown table with dependencies
- Execution order
- Risk areas

## TASK-XX.md (for each task)
- Objective
- Requirements
- Acceptance criteria (checkboxes)
- Files to modify
- Test cases

Each task should be:
- Self-contained (~200 LOC max)
- Independently executable by an agent
- Clear acceptance criteria

Output the documents in markdown format."
```

## Output Format

```markdown
## Plan Creation (Codex)

**Feature**: {feature name}
**Tasks**: {N} tasks created

### Documents Created
- SPEC.md - {summary}
- DESIGN.md - {summary if created}
- PLAN.md - {N} tasks, {dependency summary}
- TASK-01.md through TASK-{N}.md

### Task Overview
| Task | Description | Dependencies | Est. LOC |
|------|-------------|--------------|----------|
| TASK-01 | {desc} | None | ~50 |
| TASK-02 | {desc} | TASK-01 | ~100 |

### Suggested Execution Order
1. TASK-01 (no dependencies)
2. TASK-02 (after TASK-01)
...

<documents>
{Full SPEC.md content}
---
{Full DESIGN.md content if applicable}
---
{Full PLAN.md content}
---
{Full TASK-01.md content}
---
{Full TASK-02.md content}
...
</documents>
```

**Note:** Main agent writes documents to `doc/projects/{feature}/` from the `<documents>` section.
