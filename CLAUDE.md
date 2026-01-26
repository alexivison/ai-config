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
- [ ] Verification summary in PR description

## Sub-Agents

Details in `~/.claude/agents/README.md`. Key behavior rules:

| Scenario | Action |
|----------|--------|
| Run tests | test-runner |
| Run typecheck/lint | check-runner |
| Run tests + checks | test-runner + check-runner (parallel)* |
| Analyze logs | log-analyzer |
| Complex bug investigation | debug-investigator |
| New project context | project-researcher |
| Explore codebase | built-in Explore agent |

*Parallel: invoke both in same message using multiple Task tool calls.

**After sub-agent returns:**
- **Investigation agents** (debug-investigator, project-researcher, log-analyzer): MUST show findings, use AskUserQuestion "Ready to proceed?", wait for user
- **Verification agents** (test-runner, check-runner): Show summary, address failures directly, no need to ask

**Invocation:** Include scope (files), context (errors), success criteria.

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

**Single Task:**
```
Pick up task → /write-tests → test-runner (RED) → implement → test-runner + check-runner (GREEN) → fix → /pre-pr-verification → PR → /address-pr (if comments) → merge
```

**Plan/Task updates:** After completing task, update checkbox `- [ ]` → `- [x]`, commit with implementation, wait for user approval before next task.

## Skills

Details in `~/.claude/skills/*/SKILL.md`. Auto-invocation rules:

**MUST invoke:**
| Trigger | Skill |
|---------|-------|
| Writing any test | `/write-tests` |
| Creating PR | `/pre-pr-verification` |
| User says "review" | `/code-review` |

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
