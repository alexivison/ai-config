# TASK0: Gemini CLI Configuration

**Issue:** gemini-integration-config

## Objective

Configure the Gemini CLI with instructions via GEMINI.md, following the same pattern as Claude's CLAUDE.md.

## Required Context

Read these files first:
- `gemini/settings.json` — Existing auth settings
- `gemini/.gitignore` — Credential exclusions
- Run `gemini --help` to understand CLI flags

## Files to Create

| File | Purpose |
|------|---------|
| `gemini/GEMINI.md` | Instructions for Gemini when invoked by agents |

**Note:** The `gemini/` folder is symlinked from `~/.gemini`, so adding files here makes them available to the Gemini CLI. OAuth credentials are excluded from the repo via `.gitignore`.

## Implementation Details

### Directory Structure

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

**GEMINI.md Loading (Verified):** Gemini CLI automatically discovers and loads `GEMINI.md` from the project directory, similar to Claude's `CLAUDE.md`. No explicit configuration required.

**Note on Skills:** Unlike GEMINI.md which is auto-discovered, Gemini skills require explicit installation via `gemini skills install`. For this integration, all instructions are included in GEMINI.md rather than using a separate skill.

### gemini/GEMINI.md

```markdown
# Gemini CLI — Research & Analysis Agent

**You are called by Claude Code for research and large-scale analysis.**

## Your Position

Claude Code (Orchestrator) calls you for:
- Large-scale log analysis (2M token context)
- Web research and synthesis
- Documentation search

You are part of a multi-agent system. Claude Code handles orchestration and execution.
You provide **research and analysis** that benefits from your 2M token context.

## Your Strengths (Use These)

- **2M token context**: Analyze massive log files at once
- **Google Search**: Latest docs, best practices, solutions
- **Fast synthesis**: Quick understanding of search results

## NOT Your Job (Others Do These)

| Task | Who Does It |
|------|-------------|
| Design decisions | Codex |
| Code review | code-critic, Codex |
| Code implementation | Claude Code |
| File editing | Claude Code |

## Output Format

Structure your response for Claude Code to use:

### For Log Analysis:
```markdown
## Log Analysis Report

**Source:** {log_path}
**Lines analyzed:** {count}
**Time range:** {start} to {end}

### Summary
{Key findings in 3-5 bullet points}

### Error Patterns
| Pattern | Count | Severity |
|---------|-------|----------|
...

### Recommendations
{Actionable suggestions}
```

### For Web Research:
```markdown
## Research Findings

**Query:** {question}

### Summary
{Key findings in 3-5 bullet points}

### Details
{Comprehensive analysis}

### Sources
1. [{title}]({url}) - {brief description}
2. ...
```

## Key Principles

1. **Be thorough** — Use your large context to find comprehensive answers
2. **Cite sources** — Include URLs and references for web research
3. **Be actionable** — Focus on what Claude Code can use
4. **Stay in lane** — Analysis only, no code changes
```

### Verify CLI Installation

```bash
# Check CLI is available (3-tier resolution)
# 1. GEMINI_PATH env var
echo "GEMINI_PATH: ${GEMINI_PATH:-not set}"

# 2. System PATH
command -v gemini

# 3. npm global fallback
echo "npm fallback: $(npm root -g)/@google/gemini-cli/bin/gemini"

# Verify working CLI
gemini --version

# Verify authentication
gemini -p "Hello, respond with 'OK'" 2>&1 | head -5
```

### CLI Usage Patterns

| Pattern | Command |
|---------|---------|
| Simple query | `gemini -p "prompt"` |
| Large input via stdin | `cat file.log \| gemini -p "Analyze..."` |
| Read-only mode | `gemini --approval-mode plan -p "..."` |
| Model selection | `gemini -m gemini-2.0-flash -p "..."` |

### Comparison with Codex

| Feature | Codex | Gemini |
|---------|-------|--------|
| Instructions file | `codex/AGENTS.md` | `gemini/GEMINI.md` |
| Prompt flag | Inline string | `-p "prompt"` |
| Read-only mode | `-s read-only` | `--approval-mode plan` |
| Auto-discovery | Yes (AGENTS.md) | Yes (GEMINI.md) |

## Verification

```bash
# Check GEMINI.md exists
test -f gemini/GEMINI.md && echo "GEMINI.md exists"

# Test CLI invocation
gemini -p "Respond with only: GEMINI_OK" 2>&1 | grep -q "GEMINI_OK" && echo "CLI works"

# Test stdin input
echo "test content" | gemini -p "Echo the input content" 2>&1 | head -3

# Test model selection
gemini -m gemini-2.0-flash -p "Say 'Flash OK'" 2>&1 | head -3

# Test read-only mode
gemini --approval-mode plan -p "Say 'Plan mode OK'" 2>&1 | head -3
```

## Acceptance Criteria

- [ ] `gemini/GEMINI.md` created with agent instructions
- [ ] CLI responds to `-p` flag queries
- [ ] Stdin input works (pipe content to gemini)
- [ ] Model selection works (`-m` flag)
- [ ] `--approval-mode plan` works for read-only
- [ ] Existing `gemini/` OAuth credentials NOT modified
- [ ] `.gitignore` excludes sensitive files (verified)
