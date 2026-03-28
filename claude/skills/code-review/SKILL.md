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

- **General**: `~/.claude/skills/code-review/reference/general.md` — Five core principles (LoB, SRP, YAGNI, DRY, KISS), quality standards, thresholds
- **Frontend**: `~/.claude/skills/code-review/reference/frontend.md` — React, TypeScript, CSS, testing patterns

Load relevant reference docs based on what's being reviewed.

## Core Principles

Every review evaluates changes against five architectural principles. **LoB is the primary principle** — when other principles conflict with it, LoB wins. See `reference/general.md` for detection patterns, feedback templates, and severity mappings.

1. **LoB** — Locality of Behavior: behavior should be obvious by looking at that unit of code alone *(primary)*
2. **SRP** — Single Responsibility: one reason to change per unit
3. **YAGNI** — You Ain't Gonna Need It: no code for hypothetical futures
4. **DRY** — Don't Repeat Yourself: single source of truth *(subordinate to LoB — prefer locality over cross-file extraction)*
5. **KISS** — Keep It Simple: readable beats clever

## Severity Levels

- **[must]** - Bugs, security issues, principle violations - must fix
- **[q]** - Questions needing clarification
- **[nit]** - Minor improvements, style suggestions

## Process

1. Use `git diff` to see staged/unstaged changes
2. **First check LoB**: does this change scatter behavior that should be local?
3. Then check SRP, YAGNI, DRY, KISS against the diff
4. Review against language-specific guidelines in reference documentation
5. Be specific with file:line references
6. Tag each finding with the violated principle (e.g., `[LoB]`, `[SRP]`, `[DRY]`)
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
The changes improve error handling and logging. File organization is clean. Need clarification on one utility function.

### Must Fix
- **api.ts:34-45** - [SRP] Missing null check on response.data before accessing properties
- **utils/format.ts:1-20** - [LoB] This formatter is only used in api.ts — inline it there instead of creating a separate file

### Questions
- **auth.ts:78** - [DRY] Why duplicate validation here instead of reusing middleware?

### Nits
- **config.ts:5** - Import order (external packages first)
- **logger.ts:20** - [KISS] Verbose error object serialization; consider structured format

### Verdict
**REQUEST_CHANGES** - Must fix the null check; inline the single-use formatter to preserve locality.
```
