# Library Research Template

Use this template when researching a library via Gemini.

## Prompt Template

```bash
gemini -p "Research the library '{library_name}' comprehensively.

Find:
- Official documentation
- GitHub README, Issues, Discussions
- Latest blog posts, tutorials (2025-2026)

Provide:

## Basic Information
- Name, version, license
- Official docs URL
- Installation command
- Runtime requirements

## Core Features
- Main use cases
- Basic usage with code examples
- Key APIs

## Constraints & Gotchas
- Known limitations
- Breaking changes in recent versions
- Performance characteristics
- Async/sync requirements
- Thread-safety

## Common Patterns
- Initialization patterns
- Error handling
- Configuration best practices
- Testing approaches

## Troubleshooting
- Common errors and solutions
- Where to find help

Output in markdown format.
" 2>/dev/null
```

## Output Location

Save to: `~/.claude/research/{library_name}-research-{date}.md`

## When to Use

- Introducing a new library
- Checking specs before implementation
- Investigating library conflicts
- User says "research this library"
