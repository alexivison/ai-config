# Plan Review (Codex)

**Trigger:** "plan review", "review plan", "SPEC.md", "PLAN.md", "TASK*.md"

## Command

```bash
codex exec -s read-only "Review planning documents at {project_path}.

Check against guidelines for:
1. SPEC.md - Goal, User Stories, Acceptance Criteria, Out of Scope
2. DESIGN.md - Architecture Overview, Key Components, Data Flow, API, File Structure
3. PLAN.md - Header, Task List, Dependencies
4. TASK*.md - Issue, Goal, Context, Files, Steps, Verification, Acceptance Criteria

Iteration: {N}
Previous feedback: {if iteration > 1}

Use severity labels:
- [must] - Missing sections, circular deps, ambiguous reqs (blocks)
- [q] - Needs clarification (blocks until answered)
- [nit] - Minor improvements (does not block)

Max iterations: 3 → then NEEDS_DISCUSSION"
```

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
