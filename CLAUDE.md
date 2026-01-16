# General Guidelines
- Main agent handles all implementation (code, tests, fixes)
- Use sub-agents only for context preservation (investigation, verification)
- Use to the point language. Focus on essential information without unnecessary details.

## Sub-Agents

Sub-agents preserve context by offloading investigation/verification tasks. Located in `~/.claude/agents/`.

### debug-investigator
**Use when:** Complex bugs requiring systematic investigation that would bloat main context.

**Returns:** Root cause, location, fix approach, test cases. Does NOT implement.

**After:** Main agent implements the fix based on findings.

### code-reviewer
**Use when:** User asks to review a PR or code changes. Pre-commit/PR verification, or when a second opinion is needed.

**IMPORTANT:** Always use this agent (not the `/reviewing-code` skill directly) when asked to review PRs. The skill is a resource loaded BY the agent.

**Returns:** Structured review with [must]/[q]/[nit] items and verdict.

### change-minimizer
**Use when:** User requests a final review for bloat/over-engineering before wrapping up.

**Returns:** Detailed analysis of unnecessary additions, bloat, or code to remove.

### project-researcher
**Use when:** Starting work on a new project, need context on project status/team/decisions, or looking for design specs and documentation.

**Returns:** Structured project overview with status, team, key resources (Notion/Figma/Slack links), recent activity, and open questions.

**After:** Main agent uses findings to inform implementation decisions.

**Note:** Searches Notion as primary source. Figma/Slack searched only if MCP servers are configured.

### When to Use Sub-Agents

| Scenario | Use Sub-Agent? |
|----------|---------------|
| Write new feature | No - main agent |
| Write tests | No - main agent |
| Fix simple bug | No - main agent |
| Investigate complex/intermittent bug | Yes - debug-investigator |
| Explore codebase structure | Yes - built-in Explore agent |
| Starting work on new project | Yes - project-researcher |
| Need project context/docs/designs | Yes - project-researcher |
| Review a PR | Yes - code-reviewer |
| Review for bloat/over-engineering | Yes - change-minimizer (on request) |

### Workflows

Note: `[wait]` = show findings, use AskUserQuestion, wait for user before continuing.

**New Feature:**
```
project-researcher (if unfamiliar) → [wait] → implementation → code-reviewer (optional) → [wait] → change-minimizer (optional)
```

**Bug Fix:**
```
debug-investigator (if complex) → [wait] → implementation → change-minimizer (optional)
```

**PR Review:**
```
code-reviewer → [wait] → address feedback → change-minimizer (optional)
```

**Project Onboarding:**
```
project-researcher → [wait] → /planning-implementations (if substantial) → feature workflow
```

### Delegation Transparency

When a task could potentially involve a sub-agent, briefly state your reasoning:
- **If delegating:** "Delegating to debug-investigator because this race condition needs systematic investigation across threading code."
- **If not delegating:** "Handling directly - single-line off-by-one error."

Keep it short - one sentence is enough.

### Invocation Requirements

When delegating, include:
1. **Scope**: File paths, function names, boundaries
2. **Context**: Relevant errors, recent changes
3. **Success criteria**: What "done" looks like

### After Sub-Agent Returns

IMPORTANT: After any sub-agent completes, you MUST:

1. ALWAYS show the user the full detailed findings - NO EXCEPTIONS. Never summarize or omit findings.
2. Use AskUserQuestion to ask "Ready to proceed?" with options:
   - "Proceed with implementation"
   - "Modify approach"
   - "Cancel"
3. Wait for user selection before taking any action

Never silently act on sub-agent results.

### Referencing Findings

When discussing which findings to address, reference by `file:line` rather than number:
- Good: "fix the truncate issue at :68"
- Avoid: "fix #3"

## Skills

- **writing-tests** — ALWAYS invoke via `/writing-tests` when asked to write tests, add coverage, or create test files. Uses Testing Trophy methodology.
- **reviewing-code** — Internal resource for code-reviewer agent. Don't invoke directly.
- **addressing-pr-comments** — Triggered when asked to address PR feedback.
- **planning-implementations** — Triggered when asked to plan a feature. Creates SPEC.md, DESIGN.md, PLAN.md, TASK*.md.
- **autoskill** — Learns from session feedback to extract durable preferences and propose skill updates. Use when the user says "learn from this session", "remember this pattern", or invokes /autoskill.

### Autoskill Triggers

Track correction signals during sessions:
- "No, use X instead of Y"
- "We always do it this way"
- "Remember to..." (stated as general rule)
- Same feedback given 2+ times

When 2+ signals accumulate, ask at a natural breakpoint (task completion, session end): "I noticed some preferences — run /autoskill?"

# Development Guidelines
- Refer to `~/.claude/rules/development.md`
