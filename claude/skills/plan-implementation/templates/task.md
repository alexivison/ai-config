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

## Scope Boundary (REQUIRED)

**Purpose:** Prevent scope mismatch between tasks. Explicitly state what IS and ISN'T in scope.

**In scope:**
- Specific endpoint/component/function this task handles
- Example: "Create endpoint only" or "Desktop view only" or "v2 API only"

**Out of scope (handled by other tasks):**
- What this task does NOT touch
- Example: "Update endpoint (TASK3)" or "Mobile view (TASK4)"

**Cross-task consistency check:**
- If TASK1 adds field X that affects code paths A and B
- Then tasks must exist to handle BOTH paths
- Example: "TASK1 adds `user_context` to schema — this task handles path A, TASK3 handles path B"

## Reference

Files to study before implementing (single source of truth):

- `path/to/similar/implementation` — Reference implementation to follow
- `path/to/types/or/interfaces` — Type/interface definitions to reuse

## Data Transformation Checklist (REQUIRED for shape changes)

**Purpose:** Ensure data flows through ALL transformation points without silent drops.

For ANY request/response shape change (new fields, modified fields, renamed fields), check:
- [ ] Proto definition
- [ ] Proto → Domain converter (`translator.go`)
- [ ] Domain model struct
- [ ] Params struct(s) — **check ALL variants** (streaming, non-streaming, etc.)
- [ ] Params conversion functions — **CRITICAL: often missed**
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
- **Scope validation**: Ensure task scope matches what dependent tasks expect
