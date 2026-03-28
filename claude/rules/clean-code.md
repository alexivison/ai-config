# Clean Code Standards

These rules apply when **writing** code — not just reviewing. Follow these proactively during implementation.

## Core Principles

Five principles govern all implementation decisions. Every code change should be evaluated against them. **LoB is the primary principle** — when other principles conflict with it, LoB wins unless there's an explicit justification.

### 1. LoB — Locality of Behavior

The behaviour of a unit of code should be as obvious as possible by looking only at that unit of code.

- **A reader should understand what a function does without opening other files.** If understanding requires tracing through 3+ files, the behavior is too scattered.
- **Collocate related logic.** Don't scatter pieces of one feature across distant parts of a file or across multiple files.
- **Prefer same-file helpers over cross-file utilities.** Only extract to a separate file when the logic is genuinely reused in 3+ places.
- **Inline single-use abstractions** that force readers to jump elsewhere. A function called once that adds no clarity should be inlined.
- **Keep side effects visible.** If a function mutates state, calls an API, or writes to disk, that should be obvious at the call site — not hidden behind layers of indirection.
- **Favor pure transformations.** Core logic should be input-in, output-out. Push side effects (DB, API, filesystem) to the boundaries so the core is self-contained and testable.

> **LoB vs DRY tension:** DRY says "extract shared logic." LoB says "keep behavior visible here." When extraction would move behavior to another file, prefer locality unless the logic is reused in 3+ places. A little repetition is better than a lot of indirection.

### 2. SRP — Single Responsibility Principle

A function, class, or module should have one, and only one, reason to change. It should do one thing and do it well.

- **One job per function.** If you need "and" to describe what a function does, split it.
- **Target 20-30 lines per function.** Under 50 is mandatory (see code-review thresholds), but aim for 20-30 as the sweet spot.
- **Max 3-4 parameters.** Group related parameters into an options object / struct / dataclass when exceeding this.
- **Name functions by what they return or do**, not how: `getUserPermissions` not `queryDatabaseAndFilterResults`.
- **When splitting, prefer splitting within the same file** to preserve locality. Only move to a new file when the extracted unit is independently reusable.

### 3. YAGNI — You Ain't Gonna Need It

Do not add functionality or complexity until it is actually necessary. Avoid building "generic" solutions for single-use cases.

- **No code for hypothetical futures.** If it's not needed now, don't write it now.
- **No abstractions with only one implementation** (unless required by testing frameworks).
- **No "plugin" systems for simple tasks.** Build the simple version first.
- **Delete unused parameters, imports, and variables** — don't leave them "just in case."
- **Functions called once that add no clarity** should be inlined (this also serves LoB).

### 4. DRY — Don't Repeat Yourself

Every piece of knowledge or logic must have a single, unambiguous representation within the system.

- **String literals** used 2+ times → extract to a named constant (same file preferred).
- **Numeric literals** (other than 0, 1, -1) → extract to a named constant with a descriptive name.
- **Code blocks** repeated in 3+ places → extract to a helper function. Prefer same-file helpers; only create a shared utility file when used across 3+ files.
- **Conditionals** checking the same compound expression in multiple places → extract to a well-named boolean variable or predicate function.
- **Validation logic** (e.g., regex patterns) must have a single source of truth — not copy-pasted across files.

> **DRY is subordinate to LoB.** Two identical 5-line blocks in the same file are fine to extract locally. Two similar blocks in different files may be better left duplicated if extracting them would force both files to depend on a shared module, scattering behavior.

### 5. KISS — Keep It Simple, Stupid

Simple code is easier to read, maintain, and test than "clever" code.

- **Max 3 levels of nesting.** Flatten with early returns, guard clauses, or extraction.
- **No complex ternary operators.** If a ternary needs a comment to understand, use if/else.
- **No "clever" one-liners** that are hard to parse at a glance. Readable steps beat compact expressions.
- **Early returns** over nested if/else chains.
- **Consistent patterns** — if three similar operations exist, they should look the same structurally.
- **Imports at top, exports at bottom, logic in between.** Keep file structure predictable.

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
1. **LoB** — Can someone understand this function without opening other files? → If not, inline or collocate.
2. **SRP** — Is this function doing more than one thing? → Split (within the same file).
3. **YAGNI** — Am I building for a requirement that doesn't exist yet? → Remove it.
4. **DRY** — Are there repeated literals or logic blocks? → Extract locally. Only share across files if used in 3+ places.
5. **KISS** — Could someone understand this without context? → If not, simplify.
