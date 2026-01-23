# General Guidelines
- Main agent handles all implementation (code, tests, fixes)
- Use sub-agents only for context preservation (investigation, verification)
- Use to the point language. Focus on essential information without unnecessary details.
- Use "we" instead of "I" — reflects the collaborative human-AI nature of our work

## Verification Rules

Evidence before claims. Never state success without fresh proof.

| Claim | Required Evidence |
|-------|-------------------|
| "Tests pass" | Run test suite, show zero failures |
| "Lint clean" | Run linter, show zero errors |
| "Build succeeds" | Run build, show exit 0 |
| "Bug fixed" | Reproduce original symptom, show it passes |
| "Ready for PR" | Run /pre-pr-verification, show all checks pass |

**Red flags requiring re-verification:**
- Tentative language ("should work", "probably fixed")
- Planning commit/PR without running checks
- Relying on previous runs as proof

**3 Strikes Rule:** After 3 failed fix attempts for the same issue, stop patching. Document what was tried, question the approach, and ask user before continuing.

## Sub-Agents

Sub-agents preserve context by offloading investigation/verification tasks. Located in `~/.claude/agents/`.

### debug-investigator
**Use when:** Complex bugs requiring systematic investigation that would bloat main context.

**Methodology:** 4-phase systematic debugging (Root Cause Investigation → Pattern Analysis → Hypothesis Testing → Specify Fix). Tracks hypotheses tested and enforces scientific method.

**Writes to:** `~/.claude/investigations/{issue-id}.md` — Full findings preserved outside main context.

**Returns:** Brief summary with file path, verdict, hypotheses tested count, and one-line summary.

**After:** Main agent reads findings file and implements the fix.

### project-researcher
**Use when:** Starting work on a new project, need context on project status/team/decisions, or looking for design specs and documentation.

**Returns:** Structured project overview with status, team, key resources (Notion/Figma/Slack links), recent activity, and open questions.

**After:** Main agent uses findings to inform implementation decisions.

**Note:** Searches Notion as primary source. Figma/Slack searched only if MCP servers are configured.

### test-runner
**Use when:** Running test suites that produce verbose output.

**Returns:** Brief summary with pass/fail count and failure details only.

**After:** Main agent addresses failures or continues with implementation.

**Note:** Uses Haiku for cost efficiency. Isolates hundreds of lines of test output from main context.

### check-runner
**Use when:** Running typechecks or linting. Always use alongside test-runner for parallel execution.

**Returns:** Brief summary with error/warning counts and issue details only.

**After:** Main agent addresses issues or continues with implementation.

**Note:** Uses Haiku for cost efficiency. Auto-detects project stack and package manager.

### log-analyzer
**Use when:** Analyzing application/server logs that would bloat main context.

**Writes to:** `~/.claude/logs/{identifier}.md` — Full analysis preserved outside main context.

**Returns:** Brief summary with file path, error/warning counts, and timeline.

**After:** Main agent reads findings file and addresses issues.

**Note:** Uses Haiku for cost efficiency. Handles JSON, syslog, Apache/Nginx, and plain text formats.

### When to Use Sub-Agents

| Scenario | Use Sub-Agent? |
|----------|---------------|
| Write new feature | No - main agent |
| Write tests | No - main agent |
| Fix simple bug | No - main agent |
| Run test suite | Yes - test-runner |
| Run typecheck/lint | Yes - check-runner |
| Run tests + checks | Yes - test-runner + check-runner (parallel) |
| Analyze logs | Yes - log-analyzer |
| Investigate complex/intermittent bug | Yes - debug-investigator |
| Explore codebase structure | Yes - built-in Explore agent |
| Starting work on new project | Yes - project-researcher |
| Need project context/docs/designs | Yes - project-researcher |
| Review a PR | No - use `/code-review` skill |
| Review for bloat/over-engineering | No - use `/minimize` skill |

### Workflows

Note: `[wait]` = show findings, use AskUserQuestion, wait for user before continuing.

**New Feature:**
```
project-researcher (if unfamiliar) → [wait] → /brainstorm (if unclear requirements) → [wait] → /plan-implementation (if substantial) → implementation → test-runner + check-runner (parallel) → /code-review → fix issues → /pre-pr-verification → PR → /minimize (if PR large)
```

**Bug Fix:**
```
debug-investigator (if complex) → [wait] → log-analyzer (if relevant) → [wait] → implementation → test-runner + check-runner (parallel) → /pre-pr-verification → PR
```

**PR Review:**
```
/code-review → address feedback → /minimize (optional)
```

**Project Onboarding:**
```
project-researcher → [wait] → /plan-implementation (if substantial) → feature workflow
```

**Single Task (most common):**
```
Pick up task → read requirements → /write-tests (if tests needed) → implement → test-runner + check-runner → fix issues → /pre-pr-verification → PR → wait for review → /address-pr (if comments) → merge → next task
```

### Delegation Transparency

It's fine to skip delegation for small/simple tasks, but always state your reasoning:
- **If delegating:** "Delegating to debug-investigator because this race condition needs systematic investigation across threading code."
- **If not delegating:** "Handling directly - simple two-file comparison."

Keep it short - one sentence is enough.

### Invocation Requirements

When delegating to sub-agents, include:
1. **Scope**: File paths, function names, boundaries
2. **Context**: Relevant errors, recent changes
3. **Success criteria**: What "done" looks like

### After Sub-Agent Returns

IMPORTANT: After any sub-agent completes, you MUST:

1. **For file-based agents** (debug-investigator, log-analyzer):
   - Read the findings file (e.g., `~/.claude/investigations/{issue-id}.md` or `~/.claude/logs/{identifier}.md`)
   - Show the user the full detailed findings - NO EXCEPTIONS
2. **For inline agents** (project-researcher, test-runner, check-runner):
   - Show the user the full detailed findings directly
3. Use AskUserQuestion to ask "Ready to proceed?" with options:
   - "Proceed with implementation"
   - "Modify approach"
   - "Cancel"
4. Wait for user selection before taking any action

Never silently act on sub-agent results.

### Referencing Findings

When discussing which findings to address, reference by `file:line` rather than number:
- Good: "fix the truncate issue at :68"
- Avoid: "fix #3"

## Skills

- **brainstorm** — Structured context capture before planning. Use before `/plan-implementation` for new features, when requirements are unclear, or when multiple approaches exist.
- **plan-implementation** — Plan features for agentic implementation. Creates SPEC.md, DESIGN.md, PLAN.md, TASK*.md.
- **write-tests** — Testing Trophy methodology with RED phase. Use before writing any tests.
- **code-review** — Review code for quality, bugs, and guideline compliance.
- **pre-pr-verification** — Run all checks (typecheck, lint, test) before PR creation.
- **minimize** — Review changes for bloat and unnecessary complexity.
- **address-pr** — Fetch PR comments and suggest solutions.
- **autoskill** — Learns from sessions to extract preferences and update skills.

### Skill Auto-Invocation Rules

**MUST invoke** (non-negotiable):

| Trigger | Skill | Why |
|---------|-------|-----|
| About to write any test | `/write-tests` | Ensures Testing Trophy methodology, RED phase |
| About to create PR | `/pre-pr-verification` | Evidence-based completion |
| User says "review" or shows code for feedback | `/code-review` | Consistent quality checks |

**SHOULD invoke** (unless clearly inappropriate):

| Trigger | Skill | Why |
|---------|-------|-----|
| New feature with unclear requirements | `/brainstorm` | Capture context before planning |
| Substantial new feature (3+ files) | `/plan-implementation` | Structured approach |
| PR has reviewer comments | `/address-pr` | Systematic response |
| PR is large (>200 LOC) | `/minimize` | Catch bloat |
| User corrects me 2+ times | `/autoskill` | Learn preferences |

**How to invoke:** Use the Skill tool with the skill name. Do not just "follow the skill's guidance" — actually invoke it.

**Note:** The `skill-eval.sh` hook suggests skills based on trigger patterns, but it's a reminder system — not enforcement. Use judgment to determine if the suggestion is appropriate for the current context.

### Autoskill Triggers

Track correction signals during sessions:
- "No, use X instead of Y"
- "We always do it this way"
- "Remember to..." (stated as general rule)
- Same feedback given 2+ times

When 2+ signals accumulate, ask at a natural breakpoint (task completion, session end): "I noticed some preferences — run /autoskill?"

# Development Guidelines
- Refer to `~/.claude/rules/development.md`
