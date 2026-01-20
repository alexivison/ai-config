# DESIGN.md Template

**Answers:** "How will it work?"

## Structure

```markdown
# <Feature Name> Design

> **Specification:** [SPEC.md](./SPEC.md)

## Architecture Overview

High-level description with Mermaid flowchart.

## File Structure

Where new code will live (agents use this for exact paths):

```
src/
├── features/<name>/
│   ├── components/
│   │   └── Component.tsx      # New
│   ├── hooks/
│   │   └── useFeature.ts      # New
│   └── types.ts               # New
└── api/
    └── feature.ts             # Modify
```

**Legend:** `New` = create, `Modify` = edit existing

## Naming Conventions

| Entity | Pattern | Example |
|--------|---------|---------|
| Components | PascalCase | `ResourceList.tsx` |
| Hooks | `use` prefix | `useResource.ts` |
| Types | PascalCase | `type ResourceState` |

## Data Flow

Mermaid sequence diagram showing request/response flow.

## API Contracts

Define request/response schemas:

```
Request: { field: type, ... }
Response: { field: type, ... }
```

**Errors:**
| Status | Code | Description |
|--------|------|-------------|
| 400 | `INVALID_INPUT` | ... |

## State Management

Mermaid state diagram if UI has complex states.

## Edge Cases & Error Handling

| Scenario | Handling |
|----------|----------|
| Network timeout | Retry with backoff |
| 401 | Redirect to login |

## External Dependencies

- **Backend API:** endpoint (link to docs)
- **Library:** `package@version` for X
```
