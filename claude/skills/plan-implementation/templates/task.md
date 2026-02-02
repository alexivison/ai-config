# TASK.md Template

**Answers:** "What exactly do I do for this step?"

**Location:** `tasks/` subfolder

**File naming:** `TASK<N>-<kebab-case-title>.md`

Examples:
- `tasks/TASK1-setup-database-schema.md`
- `tasks/TASK2-create-api-endpoints.md`
- `tasks/TASK3-add-frontend-components.md`

## Structure

```markdown
# Task N — <Short Description>

**Dependencies:** <Task X, Task Y> | **Issue:** <ID>

---

## Goal

One paragraph: what this accomplishes and why.

## Reference

Files to study before implementing (single source of truth):

- `path/to/similar/implementation` — Reference implementation to follow
- `path/to/types/or/interfaces` — Type/interface definitions to reuse

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

Test cases (implementer writes the actual test code, see `@write-tests`):
- Happy path scenario
- Error handling
- Edge case

## Acceptance Criteria

- [ ] Requirement 1 works
- [ ] Requirement 2 works
- [ ] Tests pass
```

## Notes

- Adjust file paths and verification commands based on project structure
- Reference skills with `@skill-name` (e.g., `@write-tests` for testing methodology)
- Keep tasks independently executable — include all context needed
