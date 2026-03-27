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

Six architectural principles form the backbone of every review. Each violation maps to a severity level and a standard feedback template.

### 1. SRP — Single Responsibility Principle

> A function, class, or module should have one, and only one, reason to change. It should do one thing and do it well.

**Detection:** Functions with "and" in the name, functions >25 lines doing multiple things, classes handling both business logic and infrastructure (e.g., validation + database saving).

**Feedback template:** "This [function/class] is handling multiple concerns: [Concern A] and [Concern B]. Split [Concern B] into a separate dedicated unit to improve testability and focus."

| Violation | Severity |
|-----------|----------|
| Function does multiple unrelated things | `[must]` |
| Class mixes business logic and infrastructure | `[must]` |
| Function >50 lines | `[must]` |
| Function >25 lines doing 2+ things | `[q]` |

### 2. DI — Dependency Inversion

> High-level modules should not depend on low-level modules. Both should depend on abstractions (interfaces). Dependencies should be injected rather than hardcoded.

**Detection:** `new` keyword inside a class constructor or function body for infrastructure services (DB clients, APIs, loggers). Hardcoded global config access inside business logic.

**Feedback template:** "The code is tightly coupled to [Specific Tool]. Inject this dependency via the constructor or as a function argument using an interface. This allows us to pass mocks during testing."

| Violation | Severity |
|-----------|----------|
| Hardcoded infrastructure dependency in business logic | `[must]` |
| Global config access inside core domain code | `[q]` |
| Missing interface for injected dependency | `[q]` |

### 3. YAGNI — You Ain't Gonna Need It

> Do not add functionality or complexity until it is actually necessary. Avoid building "generic" solutions for single-use cases.

**Detection:** Unused parameters, over-engineered "plugin" systems for simple tasks, "future-proofing" comments (e.g., "we might need this later"), abstractions with only one implementation.

**Feedback template:** "This implementation adds complexity for a future requirement that doesn't exist yet. Revert to the simplest version that solves the current task to keep the codebase lean."

| Violation | Severity |
|-----------|----------|
| Code for hypothetical future needs | `[q]` |
| Abstraction with only one implementation (no DI/testing justification) | `[q]` |
| Unused parameters, imports, or variables | `[must]` |
| "Plugin" architecture for single-use case | `[q]` |

### 4. SoC — Separation of Concerns

> The program should be divided into distinct sections, each addressing a separate concern (Logic, Data, UI, Infrastructure).

**Detection:** SQL/database queries inside UI components, HTTP status codes or API logic inside core business services, business rules embedded in infrastructure code.

**Feedback template:** "Infrastructure details ([e.g., SQL/API calls]) are leaking into the [Domain/UI] layer. Move this logic to a dedicated [Repository/Service] layer."

| Violation | Severity |
|-----------|----------|
| Infrastructure logic in domain/UI layer | `[must]` |
| Business rules in infrastructure code | `[must]` |
| Transport concerns (HTTP codes, headers) in business services | `[q]` |

### 5. DRY — Don't Repeat Yourself

> Every piece of knowledge or logic must have a single, unambiguous representation within the system.

**Detection:** Identical logic blocks, duplicated validation regex, copy-pasted unit tests with only minor value changes, repeated string/number literals.

**Feedback template:** "Logic for [Action] is duplicated in [Location A] and [Location B]. Extract this into a shared utility or helper to ensure a single point of truth."

| Violation | Severity |
|-----------|----------|
| Duplicate code >5 lines (or >3 lines repeated 3+ times) | `[must]` |
| Same string/number literal used 2+ times without named constant | `[must]` |
| Duplicated validation logic across files | `[must]` |
| Copy-pasted tests that should use parameterization | `[q]` |

### 6. KISS — Keep It Simple, Stupid

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

### Warning `[q]`

| Issue | Threshold |
|-------|-----------|
| Function length | >30 lines |
| Nesting depth | >3 levels |
| Parameters | >4 |
| Unnamed numeric literals | Any non-obvious number (not 0, 1, -1) without a named constant |
| String literal reuse | Same string literal used 2+ times in a file |

### Complexity Delta Rule

Any change that **degrades** maintainability is `[must]`:
- Readable function becomes hard to follow
- Nesting increases significantly
- New code smell introduced

Regressions block even if absolute values are acceptable.

---

## Quality Checklist

| Check | Principle | Severity if violated |
|-------|-----------|---------------------|
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
| Hardcoded infrastructure dependency | DI | `[must]` |
| Infrastructure logic in wrong layer | SoC | `[must]` |
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
