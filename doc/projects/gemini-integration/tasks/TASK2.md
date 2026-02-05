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
# NOTE: Patterns narrowed to avoid overlap with plan-workflow coding questions
elif echo "$PROMPT_LOWER" | grep -qE '\bresearch (online|the web|externally)\b|\blook up (online|externally)\b|\bsearch the web\b|\bwhat is the (latest|current) version\b|\bwhat do (experts|others|people) say\b|\bfind external (info|documentation)\b'; then
  SUGGESTION="RECOMMENDED: Use gemini agent for research queries requiring external information."
  PRIORITY="should"
```

### Pattern Rationale

| Pattern | Trigger Example | Why Included |
|---------|-----------------|--------------|
| `\bresearch (online\|the web)\b` | "Research online best practices" | Explicit external intent |
| `\blook up (online\|externally)\b` | "Look up externally how to configure Y" | Explicit external intent |
| `\bsearch the web\b` | "Search the web for documentation" | Unambiguous web search |
| `\bwhat is the (latest\|current) version\b` | "What's the latest React version?" | Version info = external |
| `\bwhat do (experts\|others) say\b` | "What do experts say about this?" | External opinions |
| `\bfind external (info\|documentation)\b` | "Find external documentation on Z" | Explicit external intent |

### Patterns Intentionally Excluded

| Excluded Pattern | Reason |
|------------------|--------|
| `\bhow (do\|does\|to).*currently\b` | Overlaps with coding questions ("how do I use this API currently") |
| `\bresearch\b` (alone) | Too broad, matches "research the codebase" |
| `\bfind out\b` | Too broad, matches internal investigation |

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

# Test pattern matching (requires explicit external qualifier)
echo '{"prompt": "research online best practices for caching"}' | claude/hooks/skill-eval.sh | grep -q "gemini" && echo "Pattern matches"

# Ensure no false positives (bare "research" should NOT trigger)
echo '{"prompt": "research best practices for caching"}' | claude/hooks/skill-eval.sh | grep -v "gemini" && echo "Bare research: no match (correct)"

# Another false positive check
echo '{"prompt": "fix the caching bug"}' | claude/hooks/skill-eval.sh | grep -v "gemini" && echo "Bug fix: no match (correct)"
```

## Acceptance Criteria

- [ ] skill-eval.sh updated with web search pattern
- [ ] Pattern triggers for research-related queries
- [ ] Uses SHOULD priority (not MUST)
- [ ] No conflicts with existing patterns
- [ ] Shell syntax is valid
- [ ] Suggests gemini agent specifically
