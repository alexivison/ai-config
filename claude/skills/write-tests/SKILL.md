---
name: write-tests
description: >-
  Write tests following Testing Trophy methodology. Analyzes code to determine
  test type (unit/integration/component) and applies appropriate granularity. Use
  when asked to write tests, add test coverage, create test files, increase test
  coverage, do TDD, or when starting any testing task. Also invoked as the RED
  phase of task-workflow and bugfix-workflow for behavior-changing code.
user-invocable: false
---

# Overview

Write appropriate tests based on code characteristics and Testing Trophy principles.

## Reference Documentation

Load ONLY the relevant reference based on the files being tested:

- **Frontend (TypeScript/React)**: `~/.claude/skills/write-tests/reference/frontend/testing-reference.md`
- **Backend (Go)**: `~/.claude/skills/write-tests/reference/backend/testing-reference.md`

Do NOT load both. If testing `.ts`/`.tsx`/`.jsx` files → frontend. If testing `.go` files → backend. For mixed PRs, load each as needed when writing that language's tests.

## Workflow

1. **Read target code** and understand its responsibilities
2. **Check existing patterns** — find 2-3 similar test files in the codebase and note:
   - File location pattern (co-located `.test.ts` / `__tests__/` / `_test.go` in same package)
   - Test runner and assertion library (Vitest, Jest, testify, stdlib)
   - Mock strategy (MSW, `vi.mock`, interface mocks, test containers)
   - Shared helpers, custom render functions, or fixture factories already in use
   - Naming style (`describe`/`it` labels, table-driven naming)
3. **Consult reference docs** for test type selection, patterns, and tooling
4. **Write tests** at the appropriate granularity, matching discovered conventions

## Core Principles

- **Don't over-test**: Not every file/function needs a test
- **Don't duplicate coverage**: If lower-level tests cover it, don't re-test at higher levels
- **Don't test externals**: Use test doubles—verify calls, not external behavior
- **Test behavior, not implementation**
- **Keep tests in the same PR as implementation**
- **Feature flags need dual-path tests**: Verify flag ON behavior and flag OFF parity with pre-implementation behavior

## Test Scope Calibration

Cover the **happy path + each distinct error/rejection path + boundary cases for complex logic**. That means:

- **Pure function** — happy path, each error return, edge inputs (empty, zero, nil). Usually 3-8 cases in a table-driven test.
- **Service/use-case** — one test per meaningful orchestration path (success, each failure mode from dependencies). Skip paths already covered by unit tests on the domain model.
- **Component** — renders correctly, each user interaction that changes output, loading/error states. Skip re-testing logic that lives in a hook or utility already under unit test.
- **API handler** — valid request → 200, each validation failure → 4xx, auth failure → 401/403. Don't duplicate business logic tests from the service layer.

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
- Feature-flagged behavior changes → always (include ON and OFF gate-path tests)

**When RED phase is optional:**
- Adding a single test to an existing test file for coverage → optional but recommended

**After RED Phase:**
Once tests are written and RED phase confirms they fail for the right reason, **immediately proceed to implementation** — do not stop or wait for user input. The TDD cycle is: RED → GREEN → refactor, all in one flow.
