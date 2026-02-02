# Code Review (Codex)

**Trigger:** "review", "code review", "check code"

## Command

**Path handling:** If prompt includes a path (e.g., "in /path/to/worktree"), cd there first:

```bash
cd /path/to/worktree && codex review --uncommitted
```

If no path specified, run in current directory:

```bash
codex review --uncommitted
```

## Severity Labels

From guidelines:
- **[must]** - Bugs, security, maintainability violations — blocks
- **[q]** - Needs clarification — blocks until answered
- **[nit]** - Style, minor suggestions — does not block

## Output Format (VERDICT FIRST for marker detection)

```markdown
## Code Review (Codex)

**Verdict**: **APPROVE** | **REQUEST_CHANGES** | **NEEDS_DISCUSSION**
**Context**: {from prompt}

### Summary
{1-2 sentences}

### Must Fix
- **file:line** - Issue description

### Nits
- **file:line** - Minor suggestion
```

## Iteration Support

- Include `iteration` count in prompt
- Include `previous_feedback` if iteration > 1
- **Max iterations:** 3 → then NEEDS_DISCUSSION
