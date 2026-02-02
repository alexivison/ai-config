# Architecture Review Reference

Rules for reviewing structural patterns and complexity. Use `[must]`, `[q]`, `[nit]` labels.

---

## Severity Labels

| Label | Meaning | Blocks |
|-------|---------|--------|
| `[must]` | Architectural violations, blocking thresholds | Yes |
| `[q]` | Needs justification, warning thresholds | Yes (until answered) |
| `[nit]` | Suggestions | No |

---

## Metrics Thresholds

| Metric | Warn `[q]` | Block `[must]` |
|--------|------------|----------------|
| Cyclomatic complexity | >10 | >15 |
| Function length | >30 lines | >50 lines |
| File length | >300 lines | >500 lines |
| Nesting depth | >3 levels | >4 levels |
| Parameters | >4 | >5 |
| Duplicate code blocks | >2 | >3 |
| TODO/FIXME count | >3 | >5 |

**Trigger deep review if:** Any metric exceeds warn threshold.

---

## Complexity Delta Rule

**Regressions are `[must]`:**

| Condition | Severity |
|-----------|----------|
| CC increases by >5 | `[must]` |
| Any metric crosses from below to above block threshold | `[must]` |
| New code smell introduced | `[must]` |

---

## Code Smells

### Blocking `[must]`

| Smell | Detection |
|-------|-----------|
| Long Function | >50 lines |
| Long Parameter List | >5 params |
| Deep Nesting | >4 levels |
| Duplicate Code | >10 lines repeated |
| God Class/Function | Multiple unrelated responsibilities |

### Warning `[q]`

| Smell | Detection |
|-------|-----------|
| Feature Envy | Function uses another class's data more than its own |
| Shotgun Surgery | One change requires edits across many files |
| Primitive Obsession | Related primitives not grouped into object |
| Boolean Flags | Function behavior controlled by boolean params |

---

## Structural Violations

### SRP Violations `[q]`

| Detection |
|-----------|
| Name contains "And" or "Or" |
| Cannot describe purpose in one sentence |
| Multiple unrelated dependencies |
| Changes for different reasons |

### Layer Violations `[must]`

| Detection |
|-----------|
| Presentation layer accesses data layer directly |
| Lower layer depends on upper layer |
| Domain depends on infrastructure implementation |

---

## Verdicts

| Verdict | Condition |
|---------|-----------|
| **SKIP** | All metrics below warn thresholds |
| **APPROVE** | Deep review passed, no `[must]` issues |
| **REQUEST_CHANGES** | Has `[must]` or unresolved `[q]` |
| **NEEDS_DISCUSSION** | Major refactoring needed |
