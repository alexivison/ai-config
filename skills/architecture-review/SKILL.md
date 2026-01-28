---
name: architecture-review
description: Architecture guidelines for reviewing structural patterns, complexity metrics, and design decisions
user-invocable: true
---

# Architecture Review Guidelines

Reference documentation for architectural code review. Used by the `architecture-critic` agent.

## Reference Files

- [Common Patterns](reference/architecture-guidelines-common.md) — Universal principles (SRP, coupling, layers)
- [Frontend Architecture](reference/architecture-guidelines-frontend.md) — React/TypeScript patterns and smells
- [Backend Architecture](reference/architecture-guidelines-backend.md) — Go/Python/Node.js patterns and smells

## When to Load

| File Type | Load |
|-----------|------|
| `.tsx`, `.jsx`, React hooks | Common + Frontend |
| `.go`, `.py`, backend `.ts` | Common + Backend |
| Mixed PR | All three |
