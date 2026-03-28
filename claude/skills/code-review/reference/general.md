# Code Review Reference

Rules for reviewing code changes. Use `[must]`, `[q]`, `[nit]` labels.

---

## Severity Labels

| Label | Meaning | Blocks |
|-------|---------|--------|
| `[must]` | Bugs, security, maintainability violations | Yes |
| `[q]` | Clarification or justification request | No |
| `[nit]` | Style, minor suggestions | No |

---

## Core Principles

Five architectural principles form the backbone of every review. **LoB is the primary principle** — when other principles conflict with it, LoB wins unless there's an explicit justification. Each violation maps to a severity level and a standard feedback template.

### 1. LoB — Locality of Behavior

> The behaviour of a unit of code should be as obvious as possible by looking only at that unit of code.

**Detection:** Functions whose behavior can't be understood without reading 3+ other files. "Spooky action at a distance" — logic in file A that silently controls behavior in file B. Single-use abstractions that force readers to jump to another file. Side effects hidden behind layers of indirection. Core logic that depends on mutable external state instead of explicit inputs/outputs.

**Feedback template:** "Understanding this [function/component] requires reading [File A], [File B], and [File C]. Collocate the behavior here or inline the abstraction so the logic is obvious on inspection."

| Violation | Severity |
|-----------|----------|
| Behavior requires reading 3+ files to understand | `[must]` |
| Single-use helper in a separate file that should be inlined | `[must]` |
| DRY extraction that scatters behavior across files for <3 use sites | `[q]` |
| Side effects hidden behind multiple layers of indirection | `[q]` |
| Core logic depending on mutable external state instead of explicit inputs | `[q]` |

> **LoB vs DRY:** When DRY extraction would move behavior to another file, prefer locality unless the logic is reused in 3+ places. Flag cross-file extractions with fewer use sites as a LoB violation.

### 2. SRP — Single Responsibility Principle

> A function, class, or module should have one, and only one, reason to change. It should do one thing and do it well.

**Detection:** Functions with "and" in the name, functions >25 lines doing multiple things, classes handling both business logic and infrastructure (e.g., validation + database saving).

**Feedback template:** "This [function/class] is handling multiple concerns: [Concern A] and [Concern B]. Split [Concern B] into a separate function within this file to improve testability and focus."

| Violation | Severity |
|-----------|----------|
| Function does multiple unrelated things | `[must]` |
| Function >50 lines | `[must]` |
| Function >25 lines doing 2+ things | `[q]` |

### 3. YAGNI — You Ain't Gonna Need It

> Do not add functionality or complexity until it is actually necessary. Avoid building "generic" solutions for single-use cases.

**Detection:** Unused parameters, over-engineered "plugin" systems for simple tasks, "future-proofing" comments (e.g., "we might need this later"), abstractions with only one implementation.

**Feedback template:** "This implementation adds complexity for a future requirement that doesn't exist yet. Revert to the simplest version that solves the current task to keep the codebase lean."

| Violation | Severity |
|-----------|----------|
| Code for hypothetical future needs | `[q]` |
| Abstraction with only one implementation (no testing justification) | `[q]` |
| Unused parameters, imports, or variables | `[must]` |
| "Plugin" architecture for single-use case | `[q]` |

### 4. DRY — Don't Repeat Yourself

> Every piece of knowledge or logic must have a single, unambiguous representation within the system.

**Detection:** Identical logic blocks, duplicated validation regex, copy-pasted unit tests with only minor value changes, repeated string/number literals.

**Feedback template:** "Logic for [Action] is duplicated in [Location A] and [Location B]. Extract this into a shared helper to ensure a single point of truth — but keep it in the same file if both locations are in the same file."

| Violation | Severity |
|-----------|----------|
| Duplicate code >5 lines (or >3 lines repeated 3+ times) | `[must]` |
| Same string/number literal used 2+ times without named constant | `[must]` |
| Duplicated validation logic across files | `[must]` |
| Copy-pasted tests that should use parameterization | `[q]` |

> **DRY is subordinate to LoB.** Cross-file extraction for <3 use sites is a LoB violation. Prefer same-file helpers or tolerate minor duplication to preserve locality.

### 5. KISS — Keep It Simple, Stupid

> Simple code is easier to read, maintain, and test than "clever" code.

**Detection:** Deeply nested conditionals (3+ levels), complex ternary operators, "clever" one-liners that are hard to parse at a glance, compound boolean expressions not extracted to named variables.

**Feedback template:** "This logic is unnecessarily complex. Use guard clauses to flatten the nesting or break this 'clever' expression into readable steps."

| Violation | Severity |
|-----------|----------|
| Nesting depth >4 levels | `[must]` |
| Nesting depth >3 levels | `[q]` |
| Compound boolean expression (3+ clauses) not extracted | `[must]` |
| Complex ternary needing a comment to understand | `[q]` |
| "Clever" one-liner that's hard to parse | `[q]` |

---

## Maintainability Thresholds

### Blocking `[must]`

| Issue | Threshold |
|-------|-----------|
| Function length | >50 lines |
| Nesting depth | >4 levels |
| Parameters | >5 |
| Duplicate code | >5 lines repeated (or >3 lines repeated 3+ times) |
| Magic numbers/strings | Literals used 2+ times without a named constant |
| Inline complex conditionals | Compound boolean expressions (3+ clauses) not extracted to a named variable |
| Behavior locality | Understanding requires reading 3+ files |

### Warning `[q]`

| Issue | Threshold |
|-------|-----------|
| Function length | >30 lines |
| Nesting depth | >3 levels |
| Parameters | >4 |
| Unnamed numeric literals | Any non-obvious number (not 0, 1, -1) without a named constant |
| String literal reuse | Same string literal used 2+ times in a file |
| Cross-file DRY extraction | Shared utility with <3 use sites |

### Complexity Delta Rule

Any change that **degrades** maintainability is `[must]`:
- Readable function becomes hard to follow
- Nesting increases significantly
- New code smell introduced
- Behavior that was local becomes scattered across files

Regressions block even if absolute values are acceptable.

---

## Quality Checklist

| Check | Principle | Severity if violated |
|-------|-----------|---------------------|
| Behavior scattered across 3+ files | LoB | `[must]` |
| Single-use abstraction in separate file | LoB | `[must]` |
| Hidden side effects behind indirection | LoB | `[q]` |
| Naming: unclear or misleading | KISS | `[q]` |
| Naming: single letters (except loop index) | KISS | `[q]` |
| Tests missing for new code | SRP | `[must]` |
| Tests missing for bug fix | SRP | `[must]` |
| Comments: outdated or misleading | — | `[must]` |
| Comments: missing on non-obvious logic | KISS | `[q]` |
| YAGNI: unnecessary features/complexity | YAGNI | `[q]` |
| DRY: repeated code/string/number patterns | DRY | `[must]` |
| Magic values: unexplained literals | DRY | `[q]` |
| God function: does multiple unrelated things | SRP | `[must]` |
| Style guide violation | — | `[nit]` |

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
| **APPROVE** | No `[must]` findings |
| **REQUEST_CHANGES** | Has one or more `[must]` findings |
| **NEEDS_DISCUSSION** | Architectural concerns, unclear requirements |
