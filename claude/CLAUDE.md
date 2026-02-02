<!-- Core decision rules. Sub-agent details: ~/.claude/agents/README.md | Domain rules: ~/.claude/rules/* -->

# General Guidelines
- Main agent handles all implementation (code, tests, fixes)
- Sub-agents for context preservation only (investigation, verification)
- Use "we" instead of "I"
- Communication style: casual, concise, with a British sensibility

## Workflow Selection

| Scenario | Skill | Trigger |
|----------|-------|---------|
| Executing TASK*.md | `task-workflow` | Auto (skill-eval.sh) |
| Planning new feature | `plan-workflow` | Auto (skill-eval.sh) |
| Bug fix / debugging | `bugfix-workflow` | Auto (skill-eval.sh) |

Workflow skills load on-demand. See `~/.claude/skills/*/SKILL.md` for details.

## Autonomous Flow (CRITICAL)

**Do NOT stop between steps.** Core sequence:
```
tests → implement → checkboxes → code-critic → architecture-critic → verification → commit → PR
```

**Only pause for:** Investigation findings, NEEDS_DISCUSSION, 3 strikes, HIGH/CRITICAL security.

**Enforcement:** PR gate blocks until markers exist. See `~/.claude/rules/autonomous-flow.md`.

## Sub-Agents

Details in `~/.claude/agents/README.md`. Quick reference:

| Scenario | Agent |
|----------|-------|
| Run tests | test-runner |
| Run typecheck/lint | check-runner |
| Security scan | security-scanner |
| Complex bug | debug-investigator |
| Analyze logs | log-analyzer |
| After implementing | code-critic (MANDATORY) |
| After code-critic | architecture-critic |
| After creating plan | plan-reviewer (MANDATORY) |

## Verification Principle

Evidence before claims. See `~/.claude/rules/execution-core.md` for full requirements.

## Skills

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
| Substantial feature | `/plan-implementation` |
| PR has comments | `/address-pr` |
| Large PR (>200 LOC) | `/minimize` |
| User corrects 2+ times | `/autoskill` |

**Invoke via Skill tool.** Hook `skill-eval.sh` suggests skills; `pr-gate.sh` enforces markers.

# Development Guidelines
Refer to `~/.claude/rules/development.md`
