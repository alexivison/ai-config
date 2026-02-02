# Web Search Template

Use this template for web searches via Gemini with Google Search grounding.

## Prompt Template

```bash
gemini -p "Search for: {query}

Find the latest information (2025-2026) about:
- {specific aspect 1}
- {specific aspect 2}
- {specific aspect 3}

For each finding:
- Summarize the key point
- Include the source URL
- Note the date if available

Format as structured markdown with sources." 2>/dev/null
```

## Output Location

Save to: `~/.claude/research/{topic}-search-{date}.md`

## When to Use

- Finding latest documentation or release notes
- Checking current best practices
- Researching recent changes or announcements
- User says "search for", "find latest", "what's new in"

## Example Queries

```bash
# Latest framework features
gemini -p "Search for: React 19 new features 2026
Find: breaking changes, new hooks, migration guide" 2>/dev/null

# Current best practices
gemini -p "Search for: Python async best practices 2026
Find: recommended patterns, common pitfalls, performance tips" 2>/dev/null

# Recent announcements
gemini -p "Search for: Kubernetes 1.32 release notes
Find: new features, deprecations, upgrade considerations" 2>/dev/null
```

## Tips

- Be specific about the timeframe (2025-2026)
- Ask for sources/URLs explicitly
- Break complex queries into specific aspects
- Gemini has Google Search grounding for up-to-date info
