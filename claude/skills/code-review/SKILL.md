---
name: code-review
description: >-
  Review code for correctness, bugs, and guideline compliance. Produces a
  structured report with severity-labeled findings ([must]/[q]/[nit]) and a
  verdict. Loaded by the code-critic agent for SRP, DRY, and correctness checks.
  Locality, simplicity, and bloat are handled by the minimizer agent separately.
user-invocable: false
allowed-tools: Read, Grep, Glob, Bash(git:*)
---

# Code Review — Correctness

Review the current changes for correctness, bugs, and structural quality. Identify issues only — don't implement fixes.

## Reference Documentation

- **General**: `~/.claude/skills/code-review/reference/general.md` — SRP, DRY, thresholds, quality checklist
- **Frontend**: `~/.claude/skills/code-review/reference/frontend.md` — React, TypeScript, CSS, testing patterns

Load relevant reference docs based on what's being reviewed.

## Principles (this skill's scope)

1. **SRP** — Single Responsibility: one reason to change per unit
2. **DRY** — Don't Repeat Yourself: single source of truth *(respects locality — prefer same-file extraction)*

Locality (LoB), simplicity (KISS), and bloat (YAGNI) are the minimizer's domain. Do not duplicate that work.

## Severity Levels

- **[must]** - Bugs, security issues, principle violations - must fix
- **[q]** - Questions needing clarification
- **[nit]** - Minor improvements, style suggestions

## Process

1. Use `git diff` to see staged/unstaged changes
2. Check SRP and DRY against the diff
3. Check for bugs, regressions, missing tests, security issues
4. Review against language-specific guidelines in reference documentation
5. Be specific with file:line references
6. Tag each finding with the violated principle (e.g., `[SRP]`, `[DRY]`)
7. Explain WHY something is an issue (not just what's wrong)

## Output Format

```
## Code Review Report

### Summary
One paragraph: what's good, what needs work.

### Must Fix
- **file.ts:42** - Brief description of critical issue
- **file.ts:55-60** - Another critical issue

### Questions
- **file.ts:78** - Question that needs clarification

### Nits
- **file.ts:90** - Minor improvement suggestion

### Verdict
Exactly ONE of: **APPROVE** or **REQUEST_CHANGES** or **NEEDS_DISCUSSION**
One sentence explanation.

The verdict line must contain exactly one verdict keyword. Never include multiple verdict keywords in the same response — hooks parse the last occurrence to record evidence, and mixed verdicts cause false gate blocks.
```

## Example

```
## Code Review Report

### Summary
The changes improve error handling and logging. Need to fix a missing null check and clarify a validation approach.

### Must Fix
- **api.ts:34-45** - [SRP] Handler is doing validation + serialization + error formatting — split into focused functions
- **api.ts:80** - Missing null check on response.data before accessing properties

### Questions
- **auth.ts:78** - [DRY] Why duplicate validation here instead of reusing middleware?

### Nits
- **config.ts:5** - Import order (external packages first)

### Verdict
**REQUEST_CHANGES** - Must fix the null check and split the oversized handler.
```
