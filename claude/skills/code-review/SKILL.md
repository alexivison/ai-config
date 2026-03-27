---
name: code-review
description: >-
  Review code for quality, bugs, and guideline compliance. Produces a structured
  report with severity-labeled findings ([must]/[q]/[nit]) and a verdict. Use when
  reviewing diffs, checking staged changes, doing pre-commit review, validating PR
  quality, or when any sub-agent needs to evaluate code changes against project
  standards. Covers both general and frontend-specific (React, TypeScript, CSS) patterns.
user-invocable: false
allowed-tools: Read, Grep, Glob, Bash(git:*)
---

# Code Review

Review the current changes for quality, bugs, and best practices. Identify issues only — don't implement fixes.

## Reference Documentation

- **General**: `~/.claude/skills/code-review/reference/general.md` — Six core principles (SRP, DI, YAGNI, SoC, DRY, KISS), quality standards, thresholds
- **Frontend**: `~/.claude/skills/code-review/reference/frontend.md` — React, TypeScript, CSS, testing patterns

Load relevant reference docs based on what's being reviewed.

## Core Principles

Every review evaluates changes against six architectural principles. See `reference/general.md` for detection patterns, feedback templates, and severity mappings.

1. **SRP** — Single Responsibility: one reason to change per unit
2. **DI** — Dependency Inversion: depend on abstractions, inject dependencies
3. **YAGNI** — You Ain't Gonna Need It: no code for hypothetical futures
4. **SoC** — Separation of Concerns: distinct layers for logic, data, UI, infrastructure
5. **DRY** — Don't Repeat Yourself: single source of truth for every piece of knowledge
6. **KISS** — Keep It Simple: readable beats clever

## Severity Levels

- **[must]** - Bugs, security issues, principle violations - must fix
- **[q]** - Questions needing clarification
- **[nit]** - Minor improvements, style suggestions

## Process

1. Use `git diff` to see staged/unstaged changes
2. Systematically check each of the six principles against the diff
3. Review against language-specific guidelines in reference documentation
4. Be specific with file:line references
5. Tag each finding with the violated principle (e.g., `[SRP]`, `[DRY]`)
6. Explain WHY something is an issue (not just what's wrong)

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
The changes improve error handling and logging. File organization is clean. Need clarification on one utility function.

### Must Fix
- **api.ts:34-45** - [SRP] Missing null check on response.data before accessing properties
- **logger.ts:12** - [DI] Hardcoded log level should be injected via config interface

### Questions
- **auth.ts:78** - [DRY] Why duplicate validation here instead of reusing middleware?

### Nits
- **config.ts:5** - Import order (external packages first)
- **logger.ts:20** - [KISS] Verbose error object serialization; consider structured format

### Verdict
**REQUEST_CHANGES** - Must fix the null check and log level; clarify auth validation approach.
```
