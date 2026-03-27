# Clean Code Standards

These rules apply when **writing** code — not just reviewing. Follow these proactively during implementation.

## Core Principles

Six principles govern all implementation decisions. Every code change should be evaluated against them.

### 1. SRP — Single Responsibility Principle

A function, class, or module should have one, and only one, reason to change. It should do one thing and do it well.

- **One job per function.** If you need "and" to describe what a function does, split it.
- **One concern per class/module.** Business logic and infrastructure (DB, APIs, logging) belong in separate units.
- **Target 20-30 lines per function.** Under 50 is mandatory (see code-review thresholds), but aim for 20-30 as the sweet spot.
- **Max 3-4 parameters.** Group related parameters into an options object / struct / dataclass when exceeding this.
- **Name functions by what they return or do**, not how: `getUserPermissions` not `queryDatabaseAndFilterResults`.

### 2. DI — Dependency Inversion

High-level modules should not depend on low-level modules. Both should depend on abstractions. Dependencies should be injected, not hardcoded.

- **No `new` for infrastructure inside business logic.** DB clients, API clients, loggers — inject them via constructor or function argument.
- **Depend on interfaces, not implementations.** This makes swapping implementations (including test mocks) trivial.
- **No hardcoded global config access** inside business logic. Pass config values or a config interface.
- **Constructor/function parameters > module-level singletons** for anything that needs to vary between environments or tests.

### 3. YAGNI — You Ain't Gonna Need It

Do not add functionality or complexity until it is actually necessary. Avoid building "generic" solutions for single-use cases.

- **No code for hypothetical futures.** If it's not needed now, don't write it now.
- **No abstractions with only one implementation** (unless required by DI/testing frameworks).
- **No "plugin" systems for simple tasks.** Build the simple version first.
- **Delete unused parameters, imports, and variables** — don't leave them "just in case."
- **Functions called once that add no clarity** should be inlined.

### 4. SoC — Separation of Concerns

The program should be divided into distinct sections, each addressing a separate concern (Logic, Data, UI, Infrastructure).

- **No SQL/database queries inside UI components.** Data access belongs in a repository/data layer.
- **No HTTP status codes or API formatting inside core business services.** Transport concerns belong at the boundary.
- **No business rules inside infrastructure code.** Validators, transformers, and policies are domain logic.
- **Collocate related logic.** Don't scatter pieces of one feature across distant parts of a file.
- **Imports at top, exports at bottom, logic in between.** Keep file structure predictable.

### 5. DRY — Don't Repeat Yourself

Every piece of knowledge or logic must have a single, unambiguous representation within the system.

- **String literals** used 2+ times → extract to a named constant.
- **Numeric literals** (other than 0, 1, -1) → extract to a named constant with a descriptive name.
- **Code blocks** repeated 2+ times (even 3-5 lines) → extract to a helper function.
- **Conditionals** checking the same compound expression in multiple places → extract to a well-named boolean variable or predicate function.
- **Object shapes / config patterns** duplicated across call sites → extract to a shared builder or factory.
- **Validation logic** (e.g., regex patterns) must have a single source of truth — not copy-pasted across files.

### 6. KISS — Keep It Simple, Stupid

Simple code is easier to read, maintain, and test than "clever" code.

- **Max 3 levels of nesting.** Flatten with early returns, guard clauses, or extraction.
- **No complex ternary operators.** If a ternary needs a comment to understand, use if/else.
- **No "clever" one-liners** that are hard to parse at a glance. Readable steps beat compact expressions.
- **Early returns** over nested if/else chains.
- **Consistent patterns** — if three similar operations exist, they should look the same structurally.

## Variables and Constants

- **Name by meaning, not by type:** `maxRetries` not `num3`, `apiBaseUrl` not `urlString`.
- **Extract complex expressions** into named intermediate variables for readability:
  ```
  // Bad
  if (user.role === 'admin' && user.org.plan === 'enterprise' && !user.suspended) { ... }

  // Good
  const isActiveEnterpriseAdmin = user.role === 'admin' && user.org.plan === 'enterprise' && !user.suspended;
  if (isActiveEnterpriseAdmin) { ... }
  ```
- **No magic values.** Every literal that isn't self-evident needs a named constant:
  ```
  // Bad
  setTimeout(fn, 86400000);

  // Good
  const ONE_DAY_MS = 86_400_000;
  setTimeout(fn, ONE_DAY_MS);
  ```

## When Writing New Code

Before moving on from any function or block, self-check:
1. **SRP** — Is this function doing more than one thing? → Split.
2. **DI** — Am I hardcoding a dependency I should inject? → Inject it.
3. **YAGNI** — Am I building for a requirement that doesn't exist yet? → Remove it.
4. **SoC** — Am I mixing concerns (e.g., DB logic in a handler)? → Separate them.
5. **DRY** — Are there repeated literals or logic blocks? → Extract.
6. **KISS** — Could someone understand this without context? → If not, simplify.
