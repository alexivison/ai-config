---
name: address-pr
description: Fetch PR comments, read surrounding code for context, analyze complexity, suggest concrete solutions, and map dependencies between comments. Use when the user mentions PR comments, review feedback, reviewer requests, checking pull request feedback, or addressing reviewer suggestions.
user-invocable: true
---

# Addressing PR Comments

Review PR feedback and suggest actionable solutions before making changes.

## Workflow

1. **Fetch comments** via `gh pr view <number> --comments` and `gh api repos/{owner}/{repo}/pulls/{number}/comments`
2. **Read code context** (±20 lines) around each comment
3. **Analyze** intent, complexity, and dependencies between comments
4. **Present findings** using the format below

## Output Format

```markdown
## PR #<number>: <title>

### Summary

| #  | File        | Action            | Effort |
|----|-------------|-------------------|--------|
| 1  | file.ts:42  | Brief description | EASY   |
| 2  | other.ts:10 | Another action    | MOD    |

**Recommended:** #1 → #2 (reason)

### Details

#### ▸ [1] file.ts:42 — @reviewer — `EASY`

> "The reviewer's comment text (truncated if long)..."

Concrete suggestion to address this comment.
Alternative approaches if applicable.

> |

#### ▸ [2] other.ts:10 — @reviewer — `MOD`

> "Another comment..."

Suggestion for this comment.
Related: See #1 for context.


**No changes made.** Which comments to address? [1-2 / all / none]
```

## Effort Levels

- **EASY** — One-line fix, rename, use existing helper
- **MOD** — New function, logic change, multiple lines
- **HARD** — Multiple files, architectural change, needs tests

## Triage Questions

Before fixing a comment, ask:

1. **Is this from our changes?** Check `git diff main` to verify
2. **Is it a bug or nit?** Bugs (🔴) should be fixed; nits can be skipped
3. **Does fixing create new issues?** Consider ripple effects

If a reviewer catches a bug we introduced, fix it. If it's pre-existing, ask user.

## Rules

1. **Read code first** — Never suggest without understanding context
2. **No changes** — Only present findings until user approves
3. **Never push** — Always confirm before git operations

## Replying to Comments

After fixing or answering a comment:

1. **Reply in the comment thread** — NEVER post to the main PR discussion
2. **Mention the commenter** — ALWAYS start reply with `@{username}` (e.g., `@claude[bot]`)
3. **Reference the fix** — Mention commit hash or describe change made

See `reference/reply-command.md` for the exact `gh api` command template.
