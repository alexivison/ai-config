---
name: writing-tests
description: Write tests following Testing Trophy methodology. Analyzes code to determine test type (unit/integration/component), applies appropriate granularity. Supports both frontend (Vitest, testing-library) and backend (Go testing, moq). Use when asked to write tests, add test coverage, or create test files.
---

# Overview

Write appropriate tests based on code characteristics and Testing Trophy principles.

## Reference Documentation

- **Frontend (TypeScript/React)**: `~/.claude/skills/writing-tests/reference/frontend/testing-reference.md`
- **Backend (Go)**: `~/.claude/skills/writing-tests/reference/backend/testing-reference.md`

## Workflow

1. **Read target code** and understand its responsibilities
2. **Check existing patterns** — find similar tests in the codebase for conventions
3. **Consult reference docs** for test type selection, patterns, and tooling
4. **Write tests** at the appropriate granularity

## Core Principles

- **Don't over-test**: Not every file/function needs a test
- **Don't duplicate coverage**: If lower-level tests cover it, don't re-test at higher levels
- **Don't test externals**: Use test doubles—verify calls, not external behavior
- **Test behavior, not implementation**
- **Keep tests in the same PR as implementation**
