# Codebase Analysis Template

Use this template for repository-wide analysis via Gemini.

## Prompt Template

```bash
gemini -p "Analyze this repository:

1. **Architecture Overview**
   - High-level structure
   - Key design patterns
   - Technology stack

2. **Key Modules**
   | Module | Responsibility |
   |--------|----------------|

3. **Data Flow**
   - Entry points
   - Request/response flow
   - State management

4. **Extension Points**
   - Where to add new features
   - Plugin/hook mechanisms

5. **Patterns to Follow**
   - Coding conventions
   - File organization
   - Naming conventions

6. **Areas of Concern**
   - Technical debt
   - Complex areas
   - Potential improvements
" --include-directories . 2>/dev/null
```

## Key Flag

`--include-directories .` — Gives Gemini full codebase context (uses 1M token window)

## Output Location

Save to: `~/.claude/research/{repo-name}-codebase-{date}.md`

## When to Use

- Onboarding to a new codebase
- Before major refactoring
- Understanding unfamiliar areas
- User says "analyze this repo"
