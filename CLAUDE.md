# General Guidelines
- Main agent handles all implementation (code, tests, fixes)
- Use sub-agents only for context preservation (investigation, verification)
- Use to the point language. Focus on essential information without unnecessary details.

## Sub-Agents

Sub-agents preserve context by offloading investigation/verification tasks. Located in `~/.claude/agents/`.

### debug-investigator
**Use when:** Complex bugs requiring systematic investigation that would bloat main context.

**Writes to:** `~/.claude/investigations/{issue-id}.md` — Full findings preserved outside main context.

**Returns:** Brief summary with file path, verdict, and one-line summary.

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
project-researcher (if unfamiliar) → [wait] → implementation → test-runner + check-runner (parallel) → /code-review (optional) → /minimize (optional)
```

**Bug Fix:**
```
debug-investigator (if complex) → [wait] → log-analyzer (if relevant) → [wait] → implementation → test-runner + check-runner (parallel) → /minimize (optional)
```

**PR Review:**
```
/code-review → address feedback → /minimize (optional)
```

**Project Onboarding:**
```
project-researcher → [wait] → /plan-implementation (if substantial) → feature workflow
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

- **write-tests** — ALWAYS invoke via `/write-tests` before writing any tests, whether explicitly requested or as part of implementation. Uses Testing Trophy methodology.
- **code-review** — Review code for quality, bugs, and guideline compliance. Invoke via `/code-review`.
- **minimize** — Review changes for bloat and unnecessary complexity. Invoke via `/minimize`.
- **address-pr** — Fetch PR comments and suggest solutions. Invoke via `/address-pr`.
- **plan-implementation** — Plan features for agentic implementation. Creates SPEC.md, DESIGN.md, PLAN.md, TASK*.md. Invoke via `/plan-implementation`.
- **autoskill** — Learns from session feedback to extract durable preferences and propose skill updates. Use when the user says "learn from this session", "remember this pattern", or invokes `/autoskill`.

### Autoskill Triggers

Track correction signals during sessions:
- "No, use X instead of Y"
- "We always do it this way"
- "Remember to..." (stated as general rule)
- Same feedback given 2+ times

When 2+ signals accumulate, ask at a natural breakpoint (task completion, session end): "I noticed some preferences — run /autoskill?"

# Development Guidelines
- Refer to `~/.claude/rules/development.md`
