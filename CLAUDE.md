<!-- Core decision rules. Sub-agent details: ~/.claude/agents/README.md | Domain rules: ~/.claude/rules/* -->

# General Guidelines
- Main agent handles all implementation (code, tests, fixes)
- Sub-agents for context preservation only (investigation, verification)
- Use "we" instead of "I"

## Autonomous Flow (CRITICAL)

When executing TASK*.md, **do NOT stop between these steps**:

```
/write-tests → implement → checkboxes → code-critic → architecture-critic → verification → commit → PR
```

**DO NOT:**
- Stop after RED phase — implement immediately in the same response
- Stop after "Verification complete" — create commit and PR in the same response
- Output "Ready to..." or "Now I'll..." then end your turn — just do it
- Ask "Should I continue?" or "Should I create the PR?" mid-workflow

**ONLY pause for:**
- Investigation agent findings (debug-investigator, log-analyzer)
- NEEDS_DISCUSSION verdict from code-critic or architecture-critic
- 3 failed code-critic iterations
- Explicit blocker requiring user decision

**Examples of violations:**
```
❌ "RED phase verified. Tests fail for the right reason."  [ends turn]
✓  "RED phase verified. Tests fail for the right reason. Implementing now..." [continues]

❌ "All checks pass. Ready to create PR."  [ends turn]
✓  "All checks pass. Creating PR..." [continues with git add, commit, push, gh pr create]
```

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
| Explore codebase | built-in Explore agent |
| After implementing plan task | code-critic (MANDATORY) |
| After code-critic passes | architecture-critic |

*Parallel: invoke both in same message using multiple Task tool calls.

**After sub-agent returns:**
- **Investigation agents** (debug-investigator, log-analyzer): MUST show findings, use AskUserQuestion "Ready to proceed?", wait for user
- **Verification agents** (test-runner, check-runner, security-scanner): Show summary, address failures directly, no need to ask
- **Iterative agents** (code-critic): Loop autonomously until APPROVED (max 3 iterations). Only ask user if NEEDS_DISCUSSION or 3 failures.
- **Advisory agents** (architecture-critic): Show key findings (triggered metrics, main concerns) in conversation, then ask user if they want a follow-up refactor task. If yes, check existing TASK*.md files and use next available number (don't overwrite existing tasks). PR is not blocked. Only pause for NEEDS_DISCUSSION.

**Invocation:** Include scope (files), context (errors), success criteria.

**Delegation transparency:** State reason in one sentence ("Delegating to debug-investigator because..." or "Handling directly — simple fix").

## Workflows

`[wait]` = show findings, AskUserQuestion, wait for user.

**New Feature:**
```
/brainstorm (if unclear) → [wait] → /plan-implementation (if substantial) → create worktree → /write-tests (if needed) → implement → code-critic → architecture-critic → test-runner + check-runner + security-scanner → /pre-pr-verification → PR
```

**Bug Fix:**
```
debug-investigator (if complex) → [wait] → log-analyzer (if relevant) → [wait] → create worktree → /write-tests (regression test) → implement fix → code-critic → architecture-critic → test-runner + check-runner + security-scanner → /pre-pr-verification → PR
```

**Single Task (from plan/TASK*.md):**
```
Pick up task → STOP: PRE-IMPLEMENTATION GATE → create worktree → /write-tests (if needed) → implement → update checkboxes (TASK*.md + PLAN.md) → code-critic → architecture-critic → test-runner + check-runner + security-scanner → /pre-pr-verification → commit → PR
```

## Pre-Implementation Gate

**STOP. Before writing ANY code for a TASK*.md:**

1. **Create worktree first** — `git worktree add ../repo-branch-name -b branch-name`
2. **Does task require tests?** → invoke `/write-tests` FIRST
3. **Requirements unclear?** → `/brainstorm` or ask user
4. **Will this bloat into a large PR?** → If task scope seems too broad (many unrelated changes, multiple features), split into smaller tasks before proceeding

Skip this gate = workflow violation. State which items were checked before proceeding.

After passing this gate, follow **Autonomous Flow** rules above — no stopping until PR is created.

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
| After code-critic APPROVE | architecture-critic |

**SHOULD invoke:**
| Trigger | Skill |
|---------|-------|
| Unclear requirements | `/brainstorm` |
| Substantial feature (3+ files) | `/plan-implementation` |
| PR has comments | `/address-pr` |
| Large PR (>200 LOC) | `/minimize` |
| User corrects 2+ times | `/autoskill` |

**Invoke via Skill tool.**

**Hook enforcement:**
- `skill-eval.sh` (UserPromptSubmit) detects triggers and suggests MUST/SHOULD skills — these are reminders
- `skill-marker.sh` (PostToolUse) creates `/tmp/claude-skill-{name}-{session}` markers when skills complete
- `pr-gate.sh` (PreToolUse) blocks `gh pr create` unless `/pre-pr-verification` marker exists — this is hard enforcement

**Autoskill triggers:** "No, use X instead", "We always do it this way", same feedback 2+ times → ask about /autoskill at natural breakpoint.

# Development Guidelines
Refer to `~/.claude/rules/development.md`
