# TASK1: gemini Agent

**Issue:** gemini-integration-agent
**Depends on:** TASK0

## Objective

Create a single CLI-based Gemini agent that handles both large-scale log analysis and web search synthesis.

## Required Context

Read these files first:
- `claude/agents/log-analyzer.md` — Current log analyzer (inherit patterns)
- `claude/agents/codex.md` — Agent definition pattern
- `gemini/AGENTS.md` — Gemini instructions (from TASK0)
- Run `gemini --help` to understand CLI options

## Files to Create

| File | Action |
|------|--------|
| `claude/agents/gemini.md` | Create |

## Implementation Details

### claude/agents/gemini.md

**Frontmatter:**
```yaml
---
name: gemini
description: "Gemini-powered analysis agent. Uses 2M token context for large logs (gemini-2.5-pro), Flash model for web search synthesis (gemini-2.0-flash)."
model: haiku
tools: Bash, Glob, Grep, Read, Write, WebSearch, WebFetch
color: green
---
```

**Mode Detection Logic:**

```
1. Parse task to determine mode:
   - Keywords: "log", "analyze logs", "production logs" → LOG ANALYSIS
   - Keywords: "research", "search", "look up", "find out" → WEB SEARCH

2. LOG ANALYSIS MODE:
   a. Estimate log size:
      - Count lines: wc -l
      - Sample first 100 lines to estimate avg line length
      - Estimate tokens: (lines × avg_chars) / 4
   b. Routing:
      - IF estimated_tokens < 100K → delegate to standard log-analyzer
      - IF estimated_tokens > 100K → use Gemini
   c. Gemini invocation (stdin for large content):
      cat /path/to/logs.log | gemini --approval-mode plan -m gemini-2.5-pro -p "Analyze..."

3. WEB SEARCH MODE:
   a. Formulate search queries from user question
   b. Execute WebSearch tool for results
   c. Optionally WebFetch for full page content
   d. Synthesize with Gemini Flash:
      gemini --approval-mode plan -m gemini-2.0-flash -p "Synthesize these search results..."
```

**Log Analysis Invocation:**
```bash
# CORRECT: Pipe logs via stdin
cat /path/to/logs.log | gemini --approval-mode plan -m gemini-2.5-pro -p "Analyze these logs. Identify:
- Error patterns and frequencies
- Time-based clusters/spikes
- Correlations between error types
- Root cause hypotheses"

# WRONG: Never embed large content in argument (shell limit ~256KB)
# gemini -p "$(cat large.log)" ← DO NOT DO THIS
```

**Web Search Synthesis:**
```bash
# After gathering search results, synthesize with Flash
gemini --approval-mode plan -m gemini-2.0-flash -p "Based on these search results, provide a comprehensive answer to: {question}

Search Results:
{formatted_results}

Include:
- Direct answer to the question
- Key findings from multiple sources
- Source citations with URLs
- Any conflicting information noted"
```

**Output Formats:**

For log analysis (same as log-analyzer.md):
```markdown
## Log Analysis Report

**Source:** {log_path}
**Lines analyzed:** {count}
**Time range:** {start} to {end}

### Summary
{key findings}

### Error Patterns
| Pattern | Count | Severity |
|---------|-------|----------|
...

### Recommendations
- {actionable items}
```

For web search:
```markdown
## Research Findings

**Query:** {original_question}

### Answer
{synthesized answer}

### Key Points
- {bullet points}

### Sources
1. [{title}]({url}) - {brief description}
2. ...
```

## Verification

```bash
# Agent file exists and has correct frontmatter
grep -q "name: gemini" claude/agents/gemini.md

# Check for mode detection logic
grep -qE "LOG ANALYSIS|WEB SEARCH|log-analysis|web-search" claude/agents/gemini.md

# Check for correct CLI invocation pattern (stdin piping)
grep -qE "cat.*\| gemini" claude/agents/gemini.md

# Check for model selection
grep -q "gemini-2.5-pro" claude/agents/gemini.md
grep -q "gemini-2.0-flash" claude/agents/gemini.md
```

## Acceptance Criteria

- [ ] Agent definition created at `claude/agents/gemini.md`
- [ ] Mode detection logic for log analysis vs web search
- [ ] Log analysis mode:
  - [ ] Size estimation logic (100K token threshold)
  - [ ] Falls back to standard log-analyzer for small logs
  - [ ] Uses `cat logs | gemini -p` pattern (stdin piping)
  - [ ] Uses gemini-2.5-pro model
  - [ ] Uses `--approval-mode plan` for read-only
  - [ ] Output format matches existing log-analyzer
- [ ] Web search mode:
  - [ ] Uses WebSearch/WebFetch tools
  - [ ] Uses gemini-2.0-flash model
  - [ ] Includes source citations
- [ ] Tested with both log analysis and web search queries
