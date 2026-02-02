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

## Review Checklist

### 1. Simplicity
- Functions are short and single-responsibility
- Nesting is shallow (uses early return)
- No unnecessary complexity
- Names clearly express intent

### 2. Correct Library Usage
- Follows documented library constraints
- Uses library's recommended patterns
- No deprecated APIs
- Proper error handling

### 3. Type Safety
- All functions have type hints
- Optional/Union used appropriately
- No Any abuse

### 4. Security
- No hardcoded API keys/secrets
- User input validated
- No sensitive info in logs

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

For code review, support iteration loop:
- Include `iteration` count in prompt
- Include `previous_feedback` if iteration > 1
- **Max iterations:** 3 → then NEEDS_DISCUSSION
