# Gemini Integration Design

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     Claude Code (Orchestrator)                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  skill-eval.sh ──auto-suggest──┐                                │
│                                │                                │
│  User request ─────────────────┼──► gemini agent                │
│                                │         │                      │
│                                │         ├──► Log analysis mode │
│                                │         │    (gemini-2.5-pro)  │
│                                │         │                      │
│                                └─────────┼──► Web search mode   │
│                                          │    (gemini-2.0-flash)│
│                                          ▼                      │
│                                    Gemini CLI                   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Component Design

### 1. Gemini CLI Configuration (`gemini/`)

Use the existing Gemini CLI (already installed at `$(npm root -g)/@google/gemini-cli/bin/gemini`).

**GEMINI.md Loading (Verified):** Gemini CLI automatically loads `GEMINI.md` from the project directory, similar to how Claude Code loads `CLAUDE.md`. This provides project-specific instructions without requiring manual configuration.

**Directory Structure:**
```
gemini/                           # Symlinked from ~/.gemini
├── .gitignore                    # Excludes credentials from repo
├── oauth_creds.json              # EXISTING - OAuth credentials (gitignored)
├── settings.json                 # EXISTING - Auth settings
├── google_accounts.json          # EXISTING - Account info (gitignored)
├── installation_id               # EXISTING - Local state (gitignored)
├── state.json                    # EXISTING - Local state (gitignored)
└── GEMINI.md                     # NEW - Instructions for Gemini
```

**Credential Separation:** OAuth credentials (`oauth_creds.json`, `google_accounts.json`) are excluded from version control via `.gitignore`. The symlink pattern (`~/.gemini` → `gemini/`) allows credentials to persist locally while config files are versioned.

**Note:** The `gemini/` folder is symlinked from `~/.gemini`, following the same pattern as `claude/` → `~/.claude` and `codex/` → `~/.codex`.

**CLI Interface (existing commands):**
```bash
# Non-interactive query
gemini -p "Analyze these logs for error patterns..."

# Large input via stdin (pipe content before -p flag)
cat large.log | gemini -p "Analyze these logs..."

# Model selection
gemini -m gemini-2.0-flash -p "Quick synthesis..."
gemini -m gemini-2.5-pro -p "Deep analysis..."

# Read-only mode (no file modifications by Gemini)
gemini --approval-mode plan -p "Review this code..."
```

**Key Differences from Codex:**
| Codex CLI | Gemini CLI |
|-----------|------------|
| `codex exec -s read-only "..."` | `gemini --approval-mode plan -p "..."` |
| Inline prompt | `-p` flag for prompt |
| N/A | Native stdin support (pipe before command) |

### 2. Agent Definition (`claude/agents/gemini.md`)

```yaml
---
name: gemini
description: "Gemini-powered analysis agent. Uses 2M token context for large logs, Flash model for web search synthesis."
model: haiku
tools: Bash, Glob, Grep, Read, Write, WebSearch, WebFetch
color: green
---
```

**Mode Selection Logic:**

```
1. Check for explicit mode override (case-insensitive):
   - "mode:log" or "mode:logs" → LOG ANALYSIS
   - "mode:web" or "mode:search" → WEB SEARCH

2. Keyword heuristics (if no explicit mode):

   LOG ANALYSIS triggers:
   - File path with log extension: *.log, *.jsonl, /var/log/*
   - Keywords: "analyze logs", "production logs", "error logs", "log file"
   - Pattern: path + "analyze" or "investigate"
   - Regex: /\b(analyze|investigate|check)\s+(the\s+)?(logs?|\.log)\b/i

   WEB SEARCH triggers (require explicit external qualifier):
   - "research online", "research the web", "research externally"
   - "look up online", "look up externally"
   - "search the web", "web search"
   - "what is the latest/current version of"
   - "what do experts/others say about"
   - "find external info/documentation"

   NOTE: Bare "research" alone does NOT trigger web search (avoids overlap
   with codebase research). Must include explicit external qualifier.

3. Log size routing (after mode determined):
   - Token estimation: bytes=$(wc -c < "$LOG_FILE"); tokens=$((bytes / 4))
   - < 500K tokens (~2MB) → use gemini-2.0-flash (faster for small logs)
   - 500K - 1.6M tokens → use gemini-2.5-pro via stdin
   - > 1.6M tokens (~6.4MB) → warn about potential truncation

   NOTE: gemini agent handles ALL log analysis. log-analyzer agent is deprecated.

4. Context overflow strategy (>1.6M tokens):
   - IF timestamps present → filter by time range (e.g., last 24h)
   - ELSE → chunk into segments, analyze sequentially, merge findings
```

**CLI Path Resolution:**
```bash
GEMINI_CMD="${GEMINI_PATH:-$(command -v gemini 2>/dev/null || echo '$(npm root -g)/@google/gemini-cli/bin/gemini')}"
```

### 3. skill-eval.sh Updates

Add auto-suggest pattern for web search (narrowed to avoid overlap with coding questions):

```bash
# Web search triggers (explicit external intent only)
elif echo "$PROMPT_LOWER" | grep -qE '\bresearch (online|the web|externally)\b|\blook up (online|externally)\b|\bsearch the web\b|\bwhat is the (latest|current) version\b|\bwhat do (experts|others|people) say\b|\bfind external (info|documentation)\b'; then
  SUGGESTION="RECOMMENDED: Use gemini agent for research queries."
  PRIORITY="should"
```

## Data Flow

### Log Analysis Flow

```
User: "Analyze these production logs"
         │
         ▼
┌─────────────────────┐
│ Main Agent          │
│ - Estimate log size │
│ - > 500K tokens?    │
└─────────┬───────────┘
          │ Yes
          ▼
┌─────────────────────┐
│ gemini agent        │
│ - Read log files    │
│ - gemini -m pro -p  │
│ - Write findings    │
└─────────┬───────────┘
          │
          ▼
   Findings file + summary
```

### Web Search Flow

```
User: "What's the best practice for X in 2026?"
         │
         ▼
┌─────────────────────────┐
│ skill-eval.sh           │
│ "RECOMMENDED: gemini"   │
└─────────┬───────────────┘
          │
          ▼
┌─────────────────────────┐
│ gemini agent            │
│ - WebSearch queries     │
│ - Optional WebFetch     │
│ - gemini -m flash -p    │
│ - Synthesize + cite     │
└─────────┬───────────────┘
          │
          ▼
   Research findings + sources
```

## Configuration

### gemini/GEMINI.md

Gemini CLI automatically loads `GEMINI.md` from the project directory (verified behavior). This file defines:
- Gemini's role in the multi-agent system
- Output format expectations (log analysis vs web search)
- Boundaries (what Gemini should/shouldn't do)
- Shared context from `claude/` (rules, agent instructions)

**Note on Skills:** Gemini skills require explicit installation via `gemini skills install`. For this integration, we use GEMINI.md for instructions rather than a separate context-loader skill, as GEMINI.md is automatically discovered while skills are not.

### Model Selection

| Use Case | Model | Flag |
|----------|-------|------|
| Log analysis | gemini-2.5-pro | `-m gemini-2.5-pro` |
| Web search synthesis | gemini-2.0-flash | `-m gemini-2.0-flash` |

## Error Handling

### CLI Resolution Errors

| Error | Detection | Recovery |
|-------|-----------|----------|
| CLI not found | `command -v gemini` fails | 1. Check `GEMINI_PATH` env 2. Try `$(npm root -g)/@google/gemini-cli/bin/gemini` 3. Report "Install via: npm install -g @google/gemini-cli" |
| CLI not executable | `-x "$GEMINI_CMD"` fails | Same as above |

### Authentication Errors

| Error | Detection | Recovery |
|-------|-----------|----------|
| Auth expired | Exit code or "authentication" in stderr | Report "Run `gemini` interactively to re-authenticate" |
| No credentials | Missing oauth_creds.json | Same as above |

### Runtime Errors

| Error | Detection | Recovery |
|-------|-----------|----------|
| Rate limit (429) | "rate limit" in output | CLI handles retry internally; if persists, report and suggest waiting |
| Context overflow | >1.6M estimated tokens | Apply time-range filter OR chunk sequentially (see mode selection logic) |
| Empty response | Zero-length stdout | Report "No response generated", suggest: 1. Check input format 2. Adjust prompt 3. Verify CLI auth |
| Timeout | Exit after 5min with no output | Report timeout, suggest smaller input or chunking |

### Mode Ambiguity

| Situation | Resolution |
|-----------|------------|
| No explicit mode, no keywords match | Examine input: if file paths → log analysis; else → ask user |
| Both log and web keywords present | Prefer explicit `mode:` override; else prioritize log analysis |
| File not found | Report file path error, do not proceed |

## Security Considerations

- OAuth credentials stored in `gemini/` directory (existing)
- No sensitive data in prompts (sanitize if needed)
- **Gemini is read-only:** Uses `--approval-mode plan` for CLI
- **Agent can write reports:** The wrapper agent (Haiku) writes findings to disk; Gemini does analysis only

## Runtime Requirements

- `gemini` CLI available via one of:
  - `GEMINI_PATH` environment variable
  - System PATH (`command -v gemini`)
  - Absolute path: `$(npm root -g)/@google/gemini-cli/bin/gemini`
- OAuth authenticated (existing)
