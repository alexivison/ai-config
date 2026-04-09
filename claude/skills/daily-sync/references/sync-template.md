# Daily Sync Template

## Slack Message Format

```
*Daily Sync — <Month Day> (<Weekday>)*

*What I wrought:*
• <ticket-link>: <description>

*What I pursue today:*
• <ticket-link>: <description>

*Blockers:*
• <description or "None">
```

## Ticket Link Format

Every NEXT-* ticket ID must be a clickable Slack link:
```
<https://linear.app/legalontech/issue/NEXT-XXX|NEXT-XXX>
```

Example:
```
<https://linear.app/legalontech/issue/NEXT-525|NEXT-525>: V0.5 reusable UI components — done
```

When two tickets share the same line (e.g., worked on together in one PR):
```
<https://linear.app/legalontech/issue/NEXT-8|NEXT-8> / <https://linear.app/legalontech/issue/NEXT-41|NEXT-41>: Description
```

## Tone Guide

Lightly playful — a colleague should smile, not squint.

| Standard | Playful alternative |
|----------|-------------------|
| What I did | What I wrought |
| What I'm doing | What I pursue today |
| Blockers | Blockers (keep as-is) |
| completed | vanquished, sealed, done |
| working on | forging, wiring, pursuing |
| waiting for | awaiting |
| started | began the craft |
| depends on | once X is sealed / lands |

Don't force it — use plain language when the playful version sounds awkward.

## Section Guidelines

**What I wrought:**
- Only include work that's actually done (merged, completed, delivered)
- Group related tickets on the same line when they were part of one effort
- Lead with the ticket link, then a colon, then a concise description

**What I pursue today:**
- What you plan to work on today
- Include context on readiness (e.g., "deps in place", "awaiting review")

**Blockers:**
- Concrete blockers only — not "nice to haves"
- Include who/what you're waiting on
- "None" is a valid answer

## Channel

Post to: `#lo-reinvent-internal` (C0AR1RFDVT6)
