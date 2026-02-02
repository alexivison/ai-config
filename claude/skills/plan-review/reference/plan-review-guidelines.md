# Plan Review Reference

Rules for reviewing planning documents. Use `[must]`, `[q]`, `[nit]` labels.

---

## Severity Labels

| Label | Meaning | Blocks |
|-------|---------|--------|
| `[must]` | Missing sections, circular deps, ambiguous reqs | Yes |
| `[q]` | Needs clarification | Yes (until answered) |
| `[nit]` | Formatting, minor suggestions | No |

---

## SPEC.md

### Required Sections

| Section | Check |
|---------|-------|
| Goal/Objective | One sentence describing what this achieves |
| User Stories / Requirements | What users need to accomplish |
| Acceptance Criteria | Measurable, verifiable conditions |
| Out of Scope | What this explicitly does NOT cover |

### Detections

| Issue | Severity |
|-------|----------|
| Missing acceptance criteria | `[must]` |
| Vague requirements ("should be fast") | `[must]` |
| Implementation details in spec | `[nit]` |
| Unrelated features bundled | `[q]` |
| Requirement without acceptance criterion | `[must]` |

---

## DESIGN.md

### Required Sections

| Section | Check |
|---------|-------|
| Architecture Overview | High-level approach (2-3 paragraphs) |
| Key Components | Major modules/services involved |
| Data Flow | How data moves through the system |
| API/Interface Design | Public interfaces if applicable |
| File Structure | Files to be created/modified |

### Detections

| Issue | Severity |
|-------|----------|
| No SPEC.md reference | `[must]` |
| Pattern mismatch with codebase | `[must]` |
| Missing data flow | `[must]` |
| Over-engineering for scope | `[q]` |

---

## PLAN.md

### Required Header

```markdown
# <Feature Name> Implementation Plan

> **Goal:** [One sentence]
> **Architecture:** [2-3 sentences]
> **Tech Stack:** [Technologies]
> **Specification:** [SPEC.md](./SPEC.md) | **Design:** [DESIGN.md](./DESIGN.md)
```

### Required Sections

| Section | Check |
|---------|-------|
| Plan Header | As specified above |
| Task List | Links to TASK*.md with checkboxes |
| Dependencies | Order and blockers between tasks |

### Detections

| Issue | Severity |
|-------|----------|
| Missing header | `[must]` |
| Circular dependencies | `[must]` |
| SPEC requirement not covered by any task | `[must]` |
| No dependency information | `[q]` |

---

## TASK*.md

### Required Sections

| Section | Check |
|---------|-------|
| Issue | Link to tracker or descriptive slug |
| Goal | What this task accomplishes |
| Required Context | Files to read first |
| Files to Modify | Exact paths with actions |
| Steps | Checkbox list of implementation steps |
| Verification | Commands to run for validation |
| Acceptance Criteria | How to know task is complete |

### Detections

| Issue | Severity |
|-------|----------|
| Missing verification | `[must]` |
| Too large (>500 lines, >10 files) | `[must]` |
| Implicit deps ("assumes auth is set up") | `[must]` |
| Vague steps ("implement the feature") | `[q]` |
| Missing context files | `[nit]` |

### Size Limits

| Metric | Limit |
|--------|-------|
| Implementation code | ~200 lines (tests excluded) |
| Files touched | ≤5 (or split the task) |

---

## Cross-Document Checks

| Check | Severity |
|-------|----------|
| Circular task dependencies | `[must]` |
| SPEC requirement missing from tasks | `[must]` |
| Task scope exceeds SPEC | `[q]` |
| Each task independently executable | `[must]` |

---

## Verdicts

| Verdict | Condition |
|---------|-----------|
| **APPROVE** | No `[must]`, all required sections present |
| **REQUEST_CHANGES** | Has `[must]` that can be fixed |
| **NEEDS_DISCUSSION** | Ambiguous requirements, scope concerns |
