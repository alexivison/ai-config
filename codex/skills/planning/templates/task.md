# TASK.md Template

**Answers:** "What exactly do I do for this step?"

**Location:** `tasks/` subfolder

**File naming:** `TASK<N>-<kebab-case-title>.md`

## Structure

```markdown
# Task N — <Short Description>

**Dependencies:** <Task X, Task Y> | **Issue:** <ID>

---

## Goal

One paragraph: what this accomplishes and why.

## Scope Boundary (REQUIRED)

**In scope:**
- Specific endpoint/component/function this task handles

**Out of scope (handled by other tasks):**
- What this task does NOT touch

**Cross-task consistency check:**
- If TASK1 adds field X that affects code paths A and B
- Then tasks must exist to handle BOTH paths

## Reference

Files to study before implementing:

- `path/to/similar/implementation` — Reference implementation to follow
- `path/to/types/or/interfaces` — Type/interface definitions to reuse

## Data Transformation Checklist (REQUIRED for shape changes)

For ANY request/response shape change, check:
- [ ] Proto definition
- [ ] Proto → Domain converter
- [ ] Domain model struct
- [ ] Params struct(s) — check ALL variants
- [ ] Params conversion functions
- [ ] Any adapters between param types

## Files to Create/Modify

| File | Action |
|------|--------|
| `path/to/file` | Modify |
| `path/to/new/file` | Create |

## Requirements

**Functionality:**
- Requirement 1
- Requirement 2

**Key gotchas:**
- Important caveat or bug fix to incorporate

## Tests

Test cases:
- Happy path scenario
- Error handling
- Edge case

## Acceptance Criteria

- [ ] Requirement 1 works
- [ ] Requirement 2 works
- [ ] Tests pass
```

## Notes

- Keep tasks independently executable — include all context needed
- **Scope validation**: Ensure task scope matches what dependent tasks expect
