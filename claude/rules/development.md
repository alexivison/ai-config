# Development Rules

## Git & PRs
- Use `gh` for GitHub operations
- PR descriptions: follow `rules/pr-descriptions.md`
- Create draft PRs unless instructed otherwise
- Create branches from `main`
- Branch naming: `<ISSUE-ID>-<kebab-case-description>` (e.g., `ENG-123-add-user-auth`)
- Include issue ID in PR description (e.g., `Closes ENG-123`)
- Create separate PRs for changes in different services (e.g., FE and BE fixes should be separate PRs with cross-references)

## Worktrees (Multi-Agent)
When starting work that requires a new branch:
1. Create a worktree: use `gwta {branch}` if available, otherwise `git worktree add ../{repo}-{branch} -b {branch}`
2. Never use `git checkout` or `git switch` in shared repos
3. After PR merge, clean up: `git worktree remove ../{repo}-{branch}`

Example:
```bash
gwta ENG-123-add-auth
# Or manually: git worktree add ../myapp-ENG-123-add-auth -b ENG-123-add-auth && cd ../myapp-ENG-123-add-auth
```

## Task Management
- Update checkboxes in PLAN.md and TASK*.md after completing tasks: `- [ ]` → `- [x]`
- Commit checkbox updates with implementation (not as separate commits)
- Wait for user approval before moving to next task in multi-task work

## Code Style
- Prefer early guard returns over nested if clauses

## Code Comments
- Keep comments short and to the point
- Only add remarks to logically difficult code
