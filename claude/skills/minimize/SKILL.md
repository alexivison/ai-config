---
name: minimize
description: Review changes for bloat and unnecessary complexity. Final check before commit/PR.
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash(git:*)
---

# Change Minimizer

Review code changes to identify unnecessary complexity. Ask: "Is this really necessary?"

Identify issues only — don't implement fixes.

## Process

1. Use `git diff` to see what was added/modified
2. For every addition, ask: "What breaks if we remove this?" If nothing → flag it
3. Describe simpler alternatives (don't write the code)

## What to Flag

- Code for hypothetical future needs (YAGNI)
- Abstractions with only one implementation
- Functions called once that add no clarity
- Comments restating obvious code
- Unused imports/variables
- Overly defensive error handling
- Production code >500 lines (assume bloat)
- Test helpers/mocking when simpler approaches work
- Repetitive test cases that could use `it.each` or parameterization
- Edge case tests for unrealistic scenarios (e.g., empty inputs that can't occur in practice)

## Boundaries

- Only review changed lines, not existing code

## Output Format

```
## Change Minimizer Report

### Summary
One paragraph: main bloat sources identified.

### Remove
- **file.ts:42-50** - What to remove and why
- **file.ts:60** - Another item to remove

### Simplify
- **file.ts:70-85** - Current approach and simpler alternative

### Questions
- **file.ts:90** - Why this seems unnecessary

### Verdict
**MINIMAL** (zero items) or **ACCEPTABLE** (only questions) or **BLOATED** (has remove/simplify items)
Assessment and recommended action.
```

## Example

```
## Change Minimizer Report

### Summary
Added defensive type-checking and validation that's already handled by TypeScript. Helper functions used only once add unnecessary indirection.

### Remove
- **utils.ts:42-50** - `validateEmail()` wrapper called once; just use zod schema directly
- **handler.ts:15-18** - Deep null checks redundant; TypeScript strict mode prevents this

### Simplify
- **middleware.ts:70-85** - 16-line error object construction → use native Error with cause

### Questions
- **hooks.ts:30** - Why three separate try-catch blocks? One with specific error types seems sufficient

### Verdict
**BLOATED** - Two files have unnecessary abstractions. Remove validateEmail and flatten error handling. Would save ~40 lines.
```
