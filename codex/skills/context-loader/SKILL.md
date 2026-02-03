---
name: context-loader
description: ALWAYS activate at task start. Load project context from .claude/ or current directory if already in config.
---

# Context Loader Skill

## Purpose

Load shared project context to ensure Codex CLI has the same knowledge as Claude Code.

## When to Activate

**ALWAYS** - This skill runs at the beginning of every task.

## Path Detection

First, determine where config files are:

```bash
# Check if we're already in ~/.claude or similar config directory
if [ -f "CLAUDE.md" ] && [ -d "rules" ] && [ -d "agents" ]; then
  # Already in config directory - use current paths
  CONFIG_ROOT="."
elif [ -d ".claude" ]; then
  # Project with .claude subdirectory
  CONFIG_ROOT=".claude"
elif [ -d "$HOME/.claude" ]; then
  # Fall back to global config
  CONFIG_ROOT="$HOME/.claude"
else
  # No config found
  CONFIG_ROOT=""
fi
```

## Workflow

### Step 1: Load Development Rules

Read key files from `${CONFIG_ROOT}/rules/`:

```
rules/
├── development.md       # Git, PRs, task management
├── execution-core.md    # Workflow sequence, verdicts
├── autonomous-flow.md   # Continuous execution rules
```

### Step 2: Load Agent Definition

For review tasks, read cli-orchestrator which handles all review types:

```
agents/
├── cli-orchestrator.md  # Unified: code review, arch, debug, plan review
```

### Step 2b: Load Review Guidelines (for review tasks)

Detect task type from prompt and load appropriate skill guidelines.

**For code review** (prompt contains "review", "code review"):
```
skills/code-review/reference/general.md
```

**For architecture review** (prompt contains "architecture", "arch"):
```
skills/architecture-review/reference/*.md
```

**For plan review** (prompt contains "plan review"):
```
skills/plan-review/reference/*.md
```

**Skill Loading Log (ALWAYS output at start):**
```
[context-loader] Config: ${CONFIG_ROOT}
[context-loader] Skills loaded:
  ✓ code-review/reference/general.md (if loaded)
  ✓ architecture-review/reference/... (if loaded)
  - plan-review (not needed for this task)
```

This helps verify Codex is using the correct guidelines.

### Step 3: Load CLAUDE.md

Read the main instructions file:
```
CLAUDE.md                # Core guidelines and workflow selection
```

### Step 4: Execute Task

With loaded context, execute the requested task following:
- Development rules from rules/
- Workflow patterns from CLAUDE.md
- Standard verdict format

## Key Rules to Remember

After loading, follow these principles:

1. **Standard verdicts** - APPROVE, REQUEST_CHANGES, NEEDS_DISCUSSION, SKIP
2. **Verdict FIRST** - Always put verdict at the top of output (within first 500 chars)
3. **File:line references** - Always be specific
4. **Structured output** - Use headers like "## Code Review (Codex)" for detection
5. **Read-only by default** - Don't modify files unless explicitly requested

## Iteration Protocol

**Parse iteration parameters from prompt:**
- Look for `Iteration: N` in prompt
- Look for `Previous feedback:` section

**Behavior by iteration:**

| Iteration | Scope |
|-----------|-------|
| 1 | Full review, report all [must]/[q]/[nit] |
| 2 | Verify fixes from iteration 1, check for regressions |
| 3 | Final pass, no new [nit], [must] still blocks |
| >3 | Return NEEDS_DISCUSSION |

On iteration 2+:
1. Check each item from previous feedback
2. Mark as fixed or still present
3. Note any regressions introduced by fixes
4. Only report NEW [must] issues found

## Output Format

Return structured output with verdict at top:

```markdown
## {Task Type} (Codex)

**Verdict**: **APPROVE** | **REQUEST_CHANGES** | **NEEDS_DISCUSSION**
**Iteration**: {N}

### Summary
{1-2 sentences}

### {Details section}
...
```
