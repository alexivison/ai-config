# Plan Review (Codex)

**Trigger:** "plan review", "review plan", "SPEC.md", "PLAN.md", "TASK*.md"

Reviews planning documents for completeness, clarity, and agent-executability.

## Command

```bash
codex exec -s read-only "Review planning documents at {project_path}.

Check for:
1. SPEC.md - Clear requirements, acceptance criteria, user stories
2. DESIGN.md - Architecture decisions, component design (if substantial feature)
3. PLAN.md - Task breakdown, dependencies, no circular deps
4. TASK*.md - Each task is self-contained, has clear acceptance criteria

Iteration: {N}
Previous feedback: {if iteration > 1}

Use severity labels:
- [must] - Missing sections, circular deps, ambiguous reqs (blocks approval)
- [q] - Questions needing clarification (blocks until answered)
- [nit] - Minor improvements (does not block)

Max iterations: 3 → then NEEDS_DISCUSSION"
```

## Severity Labels

| Label | Meaning | Blocks? |
|-------|---------|---------|
| `[must]` | Missing sections, circular deps, ambiguous reqs | Yes |
| `[q]` | Questions needing clarification | Yes (until answered) |
| `[nit]` | Minor improvements | No |

## Output Format (VERDICT FIRST for marker detection)

```markdown
## Plan Review (Codex)

**Verdict**: **APPROVE** | **REQUEST_CHANGES** | **NEEDS_DISCUSSION**
**Iteration**: {N}
**Project**: {project_path}

### Previous Feedback Status (if iteration > 1)
| Issue | Status |
|-------|--------|
| [must] Missing acceptance criteria | Fixed |

### Summary
{One paragraph assessment}

### Must Fix
- **SPEC.md:Acceptance Criteria** - Missing measurable conditions

### Questions
- **PLAN.md:Dependencies** - Is task 3 blocked by task 2?

### Nits
- **TASK-01.md** - Consider adding complexity estimate
```

## Iteration Support

- Track iteration count in prompt
- Include previous feedback status if iteration > 1
- **Max iterations:** 3 → then NEEDS_DISCUSSION
