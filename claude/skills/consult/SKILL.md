---
name: consult
description: |
  Consult external CLI tools for deep reasoning (Codex) or research (Gemini).
  Routes automatically based on task type. Use for code review, architecture,
  design decisions, debugging, research, and multimodal analysis.
user_invocable: true
metadata:
  short-description: Claude Code ↔ External CLI collaboration (Codex/Gemini)
---

# Consult — External CLI Orchestration

**Route tasks to specialized external CLI tools via `cli-orchestrator` subagent.**

## Tool Routing

| Task Type | CLI Tool | Strengths |
|-----------|----------|-----------|
| Code review | Codex | Deep reasoning, strict analysis |
| Architecture | Codex | Structural patterns, complexity |
| Design decisions | Codex | Trade-off analysis |
| Debugging | Codex | Root cause analysis |
| Research | Gemini | 1M token context |
| Codebase analysis | Gemini | Repository-wide understanding |
| Multimodal (PDF/video) | Gemini | Native file processing |
| Library docs | Gemini | Documentation research |
| Web search | Gemini | Google Search grounding, latest info |

## Context Management (CRITICAL)

**Always run via subagent to preserve main context.**

```
┌────────────────────────────────────────────────────────────┐
│  Main Claude Code (You)                                    │
│  → Limited context - spawn subagent                        │
│                                                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  cli-orchestrator (Subagent)                         │  │
│  │  → Detects task type from prompt                     │  │
│  │  → Routes to Codex or Gemini                         │  │
│  │  → CLI output isolated in subagent context           │  │
│  │  → Returns CONCISE summary to you                    │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────┘
```

## Invocation

### Via Task Tool (Recommended)

```
Task tool:
  subagent_type: "cli-orchestrator"
  prompt: "{task description}"
```

The agent detects which CLI to use based on keywords in your prompt.

**Examples:**

```
# Code review → Codex
prompt: "Review the uncommitted changes for bugs and security issues"

# Architecture → Codex
prompt: "Architecture review of the changed files"

# Design decision → Codex
prompt: "Compare approach A vs B for implementing caching"

# Research → Gemini
prompt: "Research best practices for authentication in 2026"

# Codebase analysis → Gemini
prompt: "Analyze this repository's architecture and key modules"

# Library docs → Gemini
prompt: "Research the httpx library: features, constraints, patterns"

# Web search → Gemini
prompt: "Search for the latest React 19 features and breaking changes in 2026"
```

### Via Skill (User-invoked)

```
/consult review          # Code review via Codex
/consult arch            # Architecture review via Codex
/consult design {topic}  # Design decision via Codex
/consult debug {issue}   # Debugging via Codex
/consult research {topic} # Research via Gemini
/consult codebase        # Codebase analysis via Gemini
/consult lib {library}   # Library research via Gemini
/consult search {query}  # Web search via Gemini
```

## Integration with Workflow

`cli-orchestrator` integrates with the autonomous flow:

```
/write-tests → implement → checkboxes → cli-orchestrator (review) → cli-orchestrator (arch) → verification → commit → PR
```

- Routes to Codex for review/arch steps
- Same verdict patterns: APPROVE, REQUEST_CHANGES, NEEDS_DISCUSSION, SKIP
- Same marker system for PR gate

## CLI Requirements

| Tool | Installation | Check |
|------|--------------|-------|
| Codex | `brew install codex` | `which codex` |
| Gemini | `brew install gemini-cli` | `which gemini` |

## Output

The subagent returns concise summaries:
- **Codex tasks**: Verdict + file:line issues + recommendations
- **Gemini tasks**: Key findings + recommendations + sources

Raw CLI output stays isolated in subagent context.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| CLI not found | Install via Homebrew |
| Timeout | Use background execution |
| Wrong tool selected | Be explicit in prompt keywords |
