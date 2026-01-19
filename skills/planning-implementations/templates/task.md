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

- `src/path/to/similar.ts` — Reference implementation to follow
- `src/path/to/types.ts` — Type definitions to reuse

## Files to Create/Modify

| File | Action |
|------|--------|
| `src/api/users.ts` | Modify |
| `src/types/user.ts` | Create |

## Requirements

**Functionality:**
- Requirement 1
- Requirement 2

**Key gotchas:**
- Important caveat or bug fix to incorporate

## Tests

Test cases (implementer writes the actual test code):
- Happy path scenario
- Error handling
- Edge case

## Verification

```bash
pnpm tsc --noEmit && pnpm lint && pnpm test src/path/to/file
```

## Acceptance Criteria

- [ ] Requirement 1 works
- [ ] Requirement 2 works
- [ ] Tests pass
```

## Guidelines

- **Requirements over implementation:** Focus on what, not how
- **Reference existing code:** Point to implementations, don't duplicate them
- **Tests as bullet points:** List test cases, not detailed test code
- **Key gotchas only:** Include critical bugs/caveats, skip obvious details
- **Max 300 lines per PR:** Split if larger
