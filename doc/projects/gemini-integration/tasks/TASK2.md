# TASK2: skill-eval.sh Integration

**Issue:** gemini-integration-skill-eval
**Depends on:** TASK1

## Objective

Update skill-eval.sh to auto-suggest the gemini agent for research queries.

## Required Context

Read these files first:
- `claude/hooks/skill-eval.sh` — Current skill evaluation hook
- `claude/agents/gemini.md` — Gemini agent (from TASK1)

## Files to Modify

| File | Action |
|------|--------|
| `claude/hooks/skill-eval.sh` | Modify |

## Implementation Details

### Add Web Search Pattern

Add a new pattern block in the SHOULD section (after existing patterns, before the closing `fi`):

```bash
# Web search / research triggers (use gemini agent)
elif echo "$PROMPT_LOWER" | grep -qE '\bresearch\b|\blook up\b|\bfind (out|info|information)\b|\bwhat.*(latest|current|best practice)\b|\bhow (do|does|to).*currently\b|\bsearch (for|the web)\b|\bwhat do.*say about\b'; then
  SUGGESTION="RECOMMENDED: Use gemini agent for research queries requiring external information."
  PRIORITY="should"
```

### Pattern Rationale

| Pattern | Trigger Example |
|---------|-----------------|
| `\bresearch\b` | "Research best practices for X" |
| `\blook up\b` | "Look up how to configure Y" |
| `\bfind (out\|info)\b` | "Find out what the latest version is" |
| `\bwhat.*(latest\|current)\b` | "What's the latest React version?" |
| `\bhow.*currently\b` | "How do people currently handle X?" |
| `\bsearch (for\|the web)\b` | "Search for documentation on Z" |
| `\bwhat do.*say about\b` | "What do the docs say about this?" |

### Placement

Insert AFTER these existing SHOULD patterns:
- Security pattern
- PR comments pattern
- Bloat/minimize pattern
- Unclear/brainstorm pattern
- Autoskill pattern

Insert BEFORE the final `fi`.

### Avoid Conflicts

Ensure patterns don't overlap with:
- `plan-workflow` triggers (create, build, implement)
- `bugfix-workflow` triggers (fix, error, bug)

The research patterns are distinct — they ask for external information, not internal codebase changes.

## Verification

```bash
# Syntax check
bash -n claude/hooks/skill-eval.sh && echo "Syntax OK"

# Test pattern matching
echo '{"prompt": "research best practices for caching"}' | claude/hooks/skill-eval.sh | grep -q "gemini" && echo "Pattern matches"

# Ensure no false positives
echo '{"prompt": "fix the caching bug"}' | claude/hooks/skill-eval.sh | grep -v "gemini" && echo "No false positive"
```

## Acceptance Criteria

- [ ] skill-eval.sh updated with web search pattern
- [ ] Pattern triggers for research-related queries
- [ ] Uses SHOULD priority (not MUST)
- [ ] No conflicts with existing patterns
- [ ] Shell syntax is valid
- [ ] Suggests gemini agent specifically
