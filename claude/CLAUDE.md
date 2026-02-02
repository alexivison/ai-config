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
tests → implement → GREEN → checkboxes → /pre-pr-verification → commit → PR
```

Code review and arch review are part of `/pre-pr-verification` (runs once at the end).

**Only pause for:** Investigation findings, NEEDS_DISCUSSION, 3 strikes, HIGH/CRITICAL security.

**Enforcement:** PR gate blocks until markers exist. See `~/.claude/rules/autonomous-flow.md`.

## Sub-Agents

Details in `~/.claude/agents/README.md`. Quick reference:

| Scenario | Agent |
|----------|-------|
| Run tests | test-runner |
| Run typecheck/lint | check-runner |
| Security scan | security-scanner |
| **Code review (pre-PR)** | **cli-orchestrator** |
| **Architecture review (pre-PR)** | **cli-orchestrator** |
| Complex bug investigation | cli-orchestrator (investigate) |
| Analyze logs | log-analyzer |
| After creating plan | cli-orchestrator (plan review) (MANDATORY) |

**Note:** Pre-PR code/arch reviews use cli-orchestrator agent (routes to Codex), NOT `/code-review` skill.

## Verification Principle

Evidence before claims. See `~/.claude/rules/execution-core.md` for full requirements.

## Skills

**MUST invoke:**
| Trigger | Skill |
|---------|-------|
| Writing any test | `/write-tests` |
| Creating PR | `/pre-pr-verification` |
| User explicitly asks "review this" | `/code-review` |

**SHOULD invoke:**
| Trigger | Skill |
|---------|-------|
| Substantial feature | `/plan-implementation` |
| PR has comments | `/address-pr` |
| Large PR (>200 LOC) | `/minimize` |
| User corrects 2+ times | `/autoskill` |

**Invoke via Skill tool.** Hook `skill-eval.sh` suggests skills; `pr-gate.sh` enforces markers.

**Do NOT invoke `/code-review` or `/architecture-review` during autonomous flow** — pre-pr-verification uses cli-orchestrator agent instead.

# Development Guidelines
Refer to `~/.claude/rules/development.md`
