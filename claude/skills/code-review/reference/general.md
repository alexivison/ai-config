# Code Review Reference — Correctness

This reference is loaded by the **code-critic** agent. It covers SRP, DRY, and correctness checks. Locality, simplicity, and bloat are handled by the minimizer agent separately.

---

Severity labels and verdicts: see `~/.claude/reference/severity-verdict.md`.

---

## Principles

### SRP — Single Responsibility Principle

> A function, class, or module should have one, and only one, reason to change. It should do one thing and do it well.

**Detection:** Functions with "and" in the name, functions >30 lines doing multiple things, classes handling both business logic and infrastructure (e.g., validation + database saving).

**Feedback template:** "This [function/class] is handling multiple concerns: [Concern A] and [Concern B]. Split [Concern B] into a separate function within this file to improve testability and focus."

| Violation | Severity |
|-----------|----------|
| Function does multiple unrelated things | `[must]` |
| Function >50 lines | `[must]` |
| Function >30 lines doing 2+ things | `[q]` |

### DRY — Don't Repeat Yourself

> Every piece of knowledge or logic must have a single, unambiguous representation within the system.

**Detection:** Identical logic blocks, duplicated validation regex, copy-pasted unit tests with only minor value changes, repeated string/number literals.

**Feedback template:** "Logic for [Action] is duplicated in [Location A] and [Location B]. Extract this into a same-file helper to ensure a single point of truth."

| Violation | Severity |
|-----------|----------|
| Duplicate code >5 lines (or >3 lines repeated 3+ times) | `[must]` |
| Magic number/string literal used without named constant | `[must]` |
| Duplicated validation logic across files (3+ use sites) | `[must]` |
| Copy-pasted tests that should use parameterization | `[q]` |
| Same string literal used 2+ times in a file without constant | `[q]` |

> **DRY respects locality.** Prefer same-file extraction. Only extract to a shared file when logic is reused in 3+ places.

---

## Additional Thresholds

| Issue | `[must]` | `[q]` |
|-------|----------|-------|
| Function length | >50 lines | >30 lines |
| Parameters | >5 | >4 |

### Complexity Delta Rule

Any change that **degrades** maintainability is `[must]`:
- Readable function becomes hard to follow
- New code smell introduced

Regressions block even if absolute values are acceptable.

---

## Quality Checklist

| Check | Severity |
|-------|----------|
| Tests missing for new code or bug fix | `[must]` |
| Naming: unclear, misleading, or single-letter (except loop index) | `[q]` |
| Comments: outdated or misleading | `[must]` |
| Comments: missing on non-obvious logic | `[q]` |
| Style guide violation | `[nit]` |

---

## Feature Flags

| Check | Severity |
|-------|----------|
| Flag OFF breaks existing behavior | `[must]` |
| Only one path tested | `[must]` |
| Dead code after rollout | `[q]` |

---

