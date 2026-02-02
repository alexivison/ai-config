# Code Review Reference

Rules for reviewing code changes. Use `[must]`, `[q]`, `[nit]` labels.

---

## Severity Labels

| Label | Meaning | Blocks |
|-------|---------|--------|
| `[must]` | Bugs, security, maintainability violations | Yes |
| `[q]` | Needs clarification or justification | Yes (until answered) |
| `[nit]` | Style, minor suggestions | No |

---

## Maintainability Thresholds

### Blocking `[must]`

| Issue | Threshold |
|-------|-----------|
| Function length | >50 lines |
| Nesting depth | >4 levels |
| Parameters | >5 |
| Duplicate code | >10 lines repeated |

### Warning `[q]`

| Issue | Threshold |
|-------|-----------|
| Function length | >30 lines |
| Nesting depth | >3 levels |
| Parameters | >4 |

### Complexity Delta Rule

Any change that **degrades** maintainability is `[must]}`:
- Readable function becomes hard to follow
- Nesting increases significantly
- New code smell introduced

Regressions block even if absolute values are acceptable.

---

## Quality Checklist

| Check | Severity if violated |
|-------|---------------------|
| Naming: unclear or misleading | `[q]` |
| Naming: single letters (except loop index) | `[q]` |
| Tests missing for new code | `[must]` |
| Tests missing for bug fix | `[must]` |
| Comments: outdated or misleading | `[must]` |
| Comments: missing on non-obvious logic | `[q]` |
| YAGNI: unnecessary features/complexity | `[q]` |
| Style guide violation | `[nit]` |

---

## Feature Flags

| Check | Severity |
|-------|----------|
| Flag OFF breaks existing behavior | `[must]` |
| Only one path tested | `[must]` |
| Dead code after rollout | `[q]` |

---

## Verdicts

| Verdict | Condition |
|---------|-----------|
| **APPROVE** | No `[must]}`, no unanswered `[q]` |
| **REQUEST_CHANGES** | Has `[must]` or unanswered `[q]` |
| **NEEDS_DISCUSSION** | Architectural concerns, unclear requirements |
