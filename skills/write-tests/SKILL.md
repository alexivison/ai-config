---
name: write-tests
description: Write tests following Testing Trophy methodology. Analyzes code to determine test type (unit/integration/component), applies appropriate granularity. Use when asked to write tests, add test coverage, create test files, increase test coverage, or when starting any testing task.
user-invocable: true
---

# Overview

Write appropriate tests based on code characteristics and Testing Trophy principles.

## Reference Documentation

- **Frontend (TypeScript/React)**: `~/.claude/skills/write-tests/reference/frontend/testing-reference.md`
- **Backend (Go)**: `~/.claude/skills/write-tests/reference/backend/testing-reference.md`

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

## Running Tests

**Always use test-runner agent** for running tests (both RED and GREEN phases).

Why:
- Preserves main context (isolates verbose test output)
- Returns concise summary
- Consistent approach across all test runs

If you need detailed failure output (e.g., to verify RED fails for the right reason), check the test-runner summary first. Only re-run specific tests directly via Bash if the summary is insufficient.

## RED Phase

When writing tests for new functionality:

1. **Write the test first** — before implementation
2. **Run via test-runner agent** and watch it FAIL
3. **Verify it fails for the RIGHT reason:**
   - Good: "Expected X but received undefined" (feature missing)
   - Bad: "Cannot find module" (syntax/import error)

**Why this matters:** A test that passes immediately proves nothing. Only a test you've seen fail can you trust to catch regressions.

**When RED phase is required:**
- Creating a new test file → always
- Adding tests for new functionality → always

**When RED phase is optional:**
- Adding a single test to an existing test file for coverage → optional but recommended

**After RED Phase:**
Once tests are written and RED phase confirms they fail for the right reason, **immediately proceed to implementation** — do not stop or wait for user input. The TDD cycle is: RED → GREEN → refactor, all in one flow.
