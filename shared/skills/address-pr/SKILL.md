---
name: address-pr
description: Fetch PR comments, analyze them, and automatically fix all actionable feedback. Use when the user mentions PR comments, review feedback, reviewer requests, checking pull request feedback, or addressing reviewer suggestions.
user-invocable: true
---

# Addressing PR Comments

Fetch PR review comments, analyze them, and automatically implement fixes.

## Workflow

1. **Fetch comments** via `gh pr view <number> --comments` and `gh api repos/{owner}/{repo}/pulls/{number}/comments`
2. **Read code context** (±20 lines) around each comment
3. **Triage** each comment:
   - **Actionable** — bug fix, code change, rename, refactor requested by reviewer
   - **Question/Discussion** — reviewer asking a question or raising a design concern
   - **Pre-existing** — comment about code we didn't change (check `git diff main`)
4. **Fix all actionable comments** automatically — implement the changes directly
5. **Reply to each comment thread** after fixing (see Replying section)
6. **Present summary** of what was fixed and what needs user input

## Triage Rules

- **Actionable comments** — Fix immediately. No need to ask permission.
- **Questions** — Answer in the thread with a reply. If the answer requires a code change, make it.
- **Pre-existing issues** — Skip. Note in summary for user awareness.
- **Conflicting comments** — If two reviewers disagree, present both positions and ask user.

## Output Format (after fixes applied)

```markdown
## PR #<number>: <title> — Comments Addressed

### Fixed

| #  | File        | Action            | Reviewer |
|----|-------------|-------------------|----------|
| 1  | file.ts:42  | Brief description | @name    |
| 2  | other.ts:10 | Another action    | @name    |

### Needs Discussion

| #  | File        | Reason                    | Reviewer |
|----|-------------|---------------------------|----------|
| 3  | api.ts:5    | Conflicting reviewer asks | @name    |

### Skipped (pre-existing)

| #  | File        | Why skipped        | Reviewer |
|----|-------------|-------------------|----------|
| 4  | old.ts:99   | Not in our diff    | @name    |
```

## Effort Levels

- **EASY** — One-line fix, rename, use existing helper
- **MOD** — New function, logic change, multiple lines
- **HARD** — Multiple files, architectural change, needs tests

## Rules

1. **Read code first** — Never fix without understanding context
2. **Fix automatically** — Implement all actionable changes without asking
3. **Never push** — Always confirm before git operations
4. **Respect scope** — Only fix what reviewers asked for, don't gold-plate

## Replying to Comments

After fixing or answering a comment:

1. **Reply in the comment thread** — NEVER post to the main PR discussion
2. **Mention the commenter** — ALWAYS start reply with `@{username}` (e.g., `@claude[bot]`)
3. **Reference the fix** — Mention commit hash or describe change made

See `reference/reply-command.md` for the exact `gh api` command template.
