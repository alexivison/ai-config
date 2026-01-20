# Development Rules

## Git & PRs
- Use `gh` for GitHub operations
- Look for PR templates when creating PRs
- Create draft PRs unless instructed otherwise
- Create branches from `main`
- Branch naming: `<ISSUE-ID>-<kebab-case-description>` (e.g., `ENG-123-add-user-auth`)
- Include issue ID in PR description (e.g., `Closes ENG-123`)

## Worktrees (Multi-Agent)
When starting work that requires a new branch:
1. Create a worktree instead of switching branches: `git worktree add ../{repo}-{branch} -b {branch}`
2. cd into the worktree directory and work there
3. Never use `git checkout` or `git switch` in shared repos
4. After PR merge, clean up: `git worktree remove ../{repo}-{branch}`

Example:
```bash
git worktree add ../myapp-ENG-123-add-auth -b ENG-123-add-auth
cd ../myapp-ENG-123-add-auth
```

## Task Workflow
- Wait for user approval before moving to next task in multi-task implementations
- Update checkboxes in plan files (PLAN.md, TASK*.md) after completing tasks

## Code Comments
- Keep comments short and to the point
- Only add remarks to logically difficult code
