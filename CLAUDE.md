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
**Use when:** As the final step after all code changes are complete.

**Returns:** Detailed analysis of unnecessary additions, bloat, or over-engineering. Identifies code to remove.

**IMPORTANT - Auto-trigger:** YOU MUST run this as the final step:
- After main agent completes a feature/fix implementation
- After code-reviewer feedback has been addressed (not immediately after review, but after fixes are applied)

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
| Final review before PR | Yes - code-reviewer |
| After any code changes complete | Yes - change-minimizer (auto) |

### Delegation Transparency

When a task could potentially involve a sub-agent, briefly state your reasoning:
- **If delegating:** "Delegating to [agent] because [reason]."
- **If not delegating:** "Handling directly because [reason]." (e.g., "simple fix", "obvious cause", "single-line change")

Keep it short - one sentence is enough.

### Invocation Requirements

When delegating, include:
1. **Scope**: File paths, function names, boundaries
2. **Context**: Relevant errors, recent changes
3. **Success criteria**: What "done" looks like

### After Sub-Agent Returns

IMPORTANT: After any sub-agent completes, you MUST:

1. Show the user the full detailed findings (not just a summary)
2. STOP and ask: **"Ready to proceed?"**
3. Wait for user confirmation before taking any action

```
**[agent-name] findings:**

[Full detailed findings from the agent]

---

Ready to proceed?
```

Never silently act on sub-agent results. Always wait for explicit user go-ahead.

### Referencing Findings

When discussing which findings to address, reference by `file:line` rather than number:
- Good: "fix the truncate issue at :68"
- Avoid: "fix #3"

This is more reliable since agent output format may vary.

### Automatic Agent Flow

```
Implementation → change-minimizer → Done
Implementation → code-reviewer → apply fixes → change-minimizer → Done
```

IMPORTANT: change-minimizer always runs LAST, after all fixes are applied.

## Skills

Auto-triggered based on context.

- **writing-tests** — Testing Trophy methodology, determines test type
- **reviewing-code** — Review guidelines (internal resource for code-reviewer agent, don't invoke directly)
- **addressing-pr-comments** — Fetches and addresses PR feedback
- **planning-implementations** — Creates SPEC.md, DESIGN.md, PLAN.md, TASK*.md

# Development Guidelines
- Refer to `~/.claude/rules/development.md`
