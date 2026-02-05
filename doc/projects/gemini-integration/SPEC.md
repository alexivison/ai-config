# Gemini Integration Specification

## Overview

Integrate Google Gemini into the autonomous workflow as a complementary model for tasks that benefit from its unique capabilities: massive context windows (2M tokens) and fast inference.

## Goals

1. **Leverage Gemini's 2M token context** for log analysis that exceeds other models' limits
2. **Add research capability** via web search synthesis using Gemini Flash

## Non-Goals

- Replacing existing agents (Codex, code-critic, etc.)
- Using Gemini for code review or implementation tasks
- Creating a general-purpose Gemini wrapper
- Multimodal UI debugging (deferred to future iteration)

## Agent

### gemini

**Purpose:** Single CLI-based agent that leverages Gemini for tasks requiring large context or fast synthesis.

**Modes:**

| Mode | Trigger | Model | Use Case |
|------|---------|-------|----------|
| log-analysis (small) | Log size < 500K tokens | gemini-2.0-flash | Fast analysis |
| log-analysis (large) | Log size >= 500K tokens | gemini-2.5-pro | Massive log files |
| web-search | Research queries (explicit external intent) | gemini-2.0-flash | Fast synthesis |

**Mode Override:** Explicit `mode:log` or `mode:web` in prompt overrides heuristics.

**Web Search Note:** Requires explicit external intent (e.g., "research online", "search the web"). Bare "research" alone does NOT trigger web search to avoid overlap with codebase research.

**Capabilities:**

1. **Log Analysis Mode:**
   - Ingest logs up to 2M tokens (~8MB of text)
   - All existing log-analyzer capabilities (format detection, aggregation, patterns)
   - Cross-reference logs from multiple sources simultaneously
   - Handles ALL log sizes (replaces log-analyzer agent)

2. **Web Search Mode:**
   - Perform web searches via WebSearch tool
   - Synthesize multiple search results into coherent answer
   - Cite sources with URLs
   - Identify when information is outdated or conflicting

**Output:**
- Log analysis: Same format as current log-analyzer (`~/.claude/logs/{identifier}.md`)
- Web search: Structured research findings with sources

## Technical Requirements

### Gemini CLI

Use the existing Gemini CLI (already installed and authenticated):
- Resolution: `GEMINI_PATH` env → `command -v gemini` → `$(npm root -g)/@google/gemini-cli/bin/gemini`
- OAuth credentials in `gemini/` directory (existing, gitignored)
- Configuration: `gemini/GEMINI.md` — Instructions for Gemini (auto-discovered from project directory)

### CLI Usage

```bash
# Non-interactive query
gemini -p "prompt"

# Model selection
gemini -m gemini-2.0-flash -p "prompt"   # Fast synthesis
gemini -m gemini-2.5-pro -p "prompt"     # Deep analysis

# Read-only mode
gemini --approval-mode plan -p "prompt"

# Large input via stdin
cat large.log | gemini -p "Analyze these logs..."
```

### Integration Points

| Integration | Purpose |
|-------------|---------|
| WebSearch tool | Web research for synthesis |
| skill-eval.sh | Auto-suggest for research queries |
| agent-trace.sh | Marker creation (if needed) |

## Acceptance Criteria

1. **Log Analysis:**
   - [x] Handles ALL log sizes (replaces log-analyzer)
   - [x] Uses gemini-2.0-flash for logs < 500K tokens
   - [x] Uses gemini-2.5-pro for logs >= 500K tokens
   - [x] Warns if logs exceed 1.6M tokens (context overflow)
   - [x] Produces same output format as current log-analyzer

2. **Web Search:**
   - [x] Auto-suggested by skill-eval.sh for research queries
   - [x] Requires explicit external intent (not bare "research")
   - [x] Synthesizes multiple search results
   - [x] Cites sources with URLs
   - [x] Returns structured findings

3. **Infrastructure:**
   - [x] Existing Gemini CLI verified working
   - [x] GEMINI.md auto-discovery verified (project directory)
   - [x] `gemini/GEMINI.md` created with instructions
   - [x] `.gitignore` excludes OAuth credentials
   - [x] Agent definition at `claude/agents/gemini.md`
   - [x] log-analyzer marked as deprecated

## Context Overflow Strategy (>1.6M tokens)

When logs exceed 1.6M tokens (~6.4MB):
- IF timestamps present → filter by time range (e.g., last 24h)
- ELSE → chunk into segments, analyze sequentially, merge findings

## Future Iterations

### gemini-ui-debugger (Deferred)

Multimodal UI debugging requires Gemini API (curl + base64) rather than CLI. Deferred to separate implementation when:
- Need arises for screenshot-to-Figma comparison
- Gemini CLI adds native image support via extensions
