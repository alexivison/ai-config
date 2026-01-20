---
name: code-review
description: Review code for quality, bugs, and guideline compliance. Use for pre-commit/PR verification.
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash(git:*)
---

# Code Review

Review the current changes for quality, bugs, and best practices. Identify issues only — don't implement fixes.

## Reference Documentation

For detailed coding standards and frontend-specific rules, see `~/.claude/skills/code-review/reference/review-guidelines.md`. Load when reviewing unfamiliar patterns.

## Severity Levels

- **[must]** - Bugs, security issues, violations - must fix
- **[q]** - Questions needing clarification
- **[nit]** - Minor improvements, style suggestions

## Process

1. Use `git diff` to see staged/unstaged changes
2. Review against guidelines in reference documentation
3. Be specific with file:line references
4. Explain WHY something is an issue (not just what's wrong)

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
**APPROVE** or **REQUEST_CHANGES** or **NEEDS_DISCUSSION**
One sentence explanation.
```

## Example

```
## Code Review Report

### Summary
The changes improve error handling and logging. File organization is clean. Need clarification on one utility function.

### Must Fix
- **api.ts:34-45** - Missing null check on response.data before accessing properties
- **logger.ts:12** - Hardcoded log level should be configurable

### Questions
- **auth.ts:78** - Why duplicate validation here instead of in middleware?

### Nits
- **config.ts:5** - Import order (external packages first)
- **logger.ts:20** - Verbose error object serialization; consider structured format

### Verdict
**REQUEST_CHANGES** - Must fix the null check and log level; clarify auth validation approach.
```
