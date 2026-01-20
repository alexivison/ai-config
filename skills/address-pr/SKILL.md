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

```
### PR #<number>: <title>

#### Comment 1 of X
**Author:** @reviewer | **File:** `path/to/file.ts:42`

**Comment:**
> "The reviewer's comment text"

**Suggested Approach:** 🟢 Trivial / 🟡 Moderate / 🔴 Complex
- Concrete suggestion to address this
- Alternative approaches if applicable
- Related comments (e.g., "Related to #3")

---

### Summary
| # | File | Approach | Effort | Dependencies |
|---|------|----------|--------|--------------|
| 1 | file:line | Brief description | 🟢/🟡/🔴 | Blocks #X / After #Y |

### Recommended Order
1. **#X** → Reason (quick win, unblocks others, etc.)

---

**No changes made.** Which comments would you like me to address?
```

## Effort Levels

- 🟢 **Trivial** — One-line fix, rename, use existing helper
- 🟡 **Moderate** — New function, logic change, multiple lines
- 🔴 **Complex** — Multiple files, architectural change, needs tests

## Rules

1. **Read code first** — Never suggest without understanding context
2. **No changes** — Only present findings until user approves
3. **Never push** — Always confirm before git operations
