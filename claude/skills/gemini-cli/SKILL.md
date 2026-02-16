---
name: gemini-cli
description: Procedural CLI invocation details for the Gemini agent
user-invocable: false
---

# Gemini CLI Procedures

## Output Contract

| Mode | Output Location |
|------|-----------------|
| Log analysis | `~/.claude/logs/{identifier}.md` |
| Web search | `~/.claude/research/{identifier}.md` |

Gemini CLI returns via stdout. You (wrapper agent) capture and write to the appropriate location.

## Mode Selection

| Mode | Model | When |
|------|-------|------|
| Log analysis (small <400K tokens) | gemini-3-flash-preview | Small log files |
| Log analysis (large ≥400K tokens) | gemini-3-pro-preview | Large log files |
| Web search | gemini-3-flash-preview | Research queries |

**Detection:** `mode:log`/`mode:web` overrides. Otherwise: file paths with log extensions → log analysis; "research online"/"search the web" → web search. Bare "research" does NOT trigger web search.

## CLI Resolution

```bash
# Priority: $GEMINI_PATH → PATH → npm global
GEMINI_CMD=$(command -v gemini 2>/dev/null || echo "$(npm root -g 2>/dev/null)/@google/gemini-cli/bin/gemini")
```

## Error Handling

| Error | Recovery |
|-------|----------|
| CLI not found | Report install: `npm install -g @google/gemini-cli` |
| Auth expired | "Run `gemini` interactively to re-authenticate" |
| Rate limited | Wait 60s, retry once |
| Timeout (5min) | Report, suggest smaller input |
| Empty response | Report, check input format |

## Pre-Flight Warning (Log Analysis)

Before sending logs to Gemini, warn about secrets/PII. Always use `--approval-mode plan`.

## Log Analysis

### Size → Model

| Tokens | Model | Action |
|--------|-------|--------|
| <400K (~1.6MB) | flash | Fast analysis |
| 400K-1.5M | pro | Large context |
| >1.5M (~6MB) | pro | Warn truncation, use time filter or chunking |

### Invocation

```bash
# CORRECT: pipe via stdin
cat /path/to/logs.log | gemini --approval-mode plan -m gemini-3-pro-preview -p "Analyze: error patterns, time clusters, correlations, root causes"

# WRONG: never embed in argument (shell limit ~256KB)
```

### Overflow (>1.5M tokens)

Time-based filtering (if timestamps present) or sequential chunking (split -b 4MB, analyze each, merge findings).

### Output

Write to `~/.claude/logs/{basename}-{timestamp}.md` with: summary, error patterns table, timeline, recommendations.

## Web Search

1. WebSearch tool for results
2. Optional WebFetch for important sources
3. Synthesize with `gemini --approval-mode plan -m gemini-3-flash-preview`
4. Write to `~/.claude/research/{identifier}.md` with: answer, key points, sources

## Safety

- Always `--approval-mode plan` (read-only)
- Always display pre-flight warning before log analysis
- Never send logs with obvious secrets without user acknowledgment
