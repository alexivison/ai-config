<!-- Core decision rules. Sub-agent details: ~/.claude/agents/README.md | Domain rules: ~/.claude/rules/* -->

# General Guidelines
- Main agent handles all implementation (code, tests, fixes)
- Sub-agents for context preservation only (investigation, verification)
- Use "we" instead of "I"

## Verification Rules

Evidence before claims. Never state success without fresh proof.

| Claim | Required Evidence |
|-------|-------------------|
| "Tests pass" | Run test suite, show zero failures |
| "Lint clean" | Run linter, show zero errors |
| "Build succeeds" | Run build, show exit 0 |
| "Bug fixed" | Reproduce original symptom, show it passes |
| "Ready for PR" | Run /pre-pr-verification, show all checks pass |

**Red flags:** Tentative language ("should work"), planning commit/PR without checks, relying on previous runs.
**Action:** STOP. Re-run checks immediately.

**3 Strikes Rule:** After 3 failed fix attempts, stop. Document what was tried, ask user before continuing.

## PR Creation Gate

**STOP. Before `gh pr create`, verify:**
- [ ] `/pre-pr-verification` invoked THIS session (hook suggestions don't count)
- [ ] All checks passed with evidence
- [ ] security-scanner shows no CRITICAL/HIGH issues (or user approved exceptions)
- [ ] Verification summary in PR description

## Sub-Agents

Details in `~/.claude/agents/README.md`. Key behavior rules:

| Scenario | Action |
|----------|--------|
| Run tests | test-runner |
| Run typecheck/lint | check-runner |
| Run tests + checks | test-runner + check-runner (parallel)* |
| Security scan before PR | security-scanner |
| Analyze logs | log-analyzer |
| Complex bug investigation | debug-investigator |
| New project context | project-researcher |
| Explore codebase | built-in Explore agent |
| After implementing plan task | code-critic (MANDATORY) |

*Parallel: invoke both in same message using multiple Task tool calls.

**After sub-agent returns:**
- **Investigation agents** (debug-investigator, project-researcher, log-analyzer): MUST show findings, use AskUserQuestion "Ready to proceed?", wait for user
- **Verification agents** (test-runner, check-runner, security-scanner): Show summary, address failures directly, no need to ask
- **Iterative agents** (code-critic): Loop autonomously until APPROVED (max 3 iterations). Only ask user if NEEDS_DISCUSSION or 3 failures.

**Invocation:** Include scope (files), context (errors), success criteria.

**Delegation transparency:** State reason in one sentence ("Delegating to debug-investigator because..." or "Handling directly — simple fix").

## Workflows

`[wait]` = show findings, AskUserQuestion, wait for user.

**New Feature:**
```
project-researcher (if unfamiliar) → [wait] → /brainstorm (if unclear) → [wait] → /plan-implementation (if substantial) → implement → test-runner + check-runner → fix → /pre-pr-verification → PR
```

**Bug Fix:**
```
debug-investigator (if complex) → [wait] → log-analyzer (if relevant) → [wait] → implement → test-runner + check-runner → /pre-pr-verification → PR
```

**Single Task (from plan/TASK*.md):**
```
Pick up task → /write-tests (if task requires tests) → implement → code-critic loop (autonomous, max 3) → test-runner + check-runner + security-scanner → /pre-pr-verification → PR → /address-pr (if comments) → merge
```
**Run autonomously through PR creation.** Don't stop after implementation - continue to verification and PR. Code-critic is MANDATORY. /write-tests is MANDATORY if the task involves writing tests. Only pause if NEEDS_DISCUSSION or 3 failed iterations.

**Plan/Task updates:** After completing task, update checkbox `- [ ]` → `- [x]`, commit with implementation, wait for user approval before next task.

## Skills

Details in `~/.claude/skills/*/SKILL.md`. Auto-invocation rules:

**MUST invoke:**
| Trigger | Skill |
|---------|-------|
| Writing any test | `/write-tests` |
| Creating PR | `/pre-pr-verification` |
| User says "review" | `/code-review` |

**MUST invoke (sub-agents):**
| Trigger | Agent |
|---------|-------|
| After implementing TASK*.md | code-critic |

**SHOULD invoke:**
| Trigger | Skill |
|---------|-------|
| Unclear requirements | `/brainstorm` |
| Substantial feature (3+ files) | `/plan-implementation` |
| PR has comments | `/address-pr` |
| Large PR (>200 LOC) | `/minimize` |
| User corrects 2+ times | `/autoskill` |

**Invoke via Skill tool.** Hook suggestions are reminders, not enforcement.

**Autoskill triggers:** "No, use X instead", "We always do it this way", same feedback 2+ times → ask about /autoskill at natural breakpoint.

# Development Guidelines
Refer to `~/.claude/rules/development.md`
