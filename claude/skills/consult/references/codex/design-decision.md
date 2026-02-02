# Design Decision (Codex)

**Trigger:** "design", "approach", "compare", "trade-off", "which"

## Command

```bash
codex exec -s read-only "{Question from prompt}. Analyze trade-offs: maintainability, testability, performance, extensibility. Recommend one."
```

## Trade-off Analysis Framework

When comparing approaches, evaluate:

| Dimension | Questions |
|-----------|-----------|
| Maintainability | How easy to understand? How easy to modify? |
| Testability | Can it be unit tested? Integration tested? |
| Performance | Time complexity? Memory usage? Scalability? |
| Extensibility | How easy to add features? How flexible? |

## Output Format

```markdown
## Design Analysis (Codex)

### Recommendation
{Clear choice}

### Rationale
- {Key reason 1}
- {Key reason 2}

### Risks
- {Potential issue}
```

## Example Prompts

```bash
# Comparing approaches
codex exec -s read-only "Compare REST vs GraphQL for our API.
Context: Mobile app with varying data needs, team familiar with REST.
Analyze trade-offs: maintainability, testability, performance, extensibility."

# Architecture decision
codex exec -s read-only "Should we use microservices or monolith for this project?
Context: Small team, MVP phase, expected growth in 6 months.
Analyze trade-offs: maintainability, testability, performance, extensibility."
```
