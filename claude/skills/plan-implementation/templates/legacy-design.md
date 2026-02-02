# LEGACY_DESIGN.md Template

**Answers:** "What exists today?"

Use for migration projects only. Pairs with DESIGN.md (the new system).

## Structure

```markdown
# <System Name> Legacy Design

> **Purpose:** Document current implementation before migration to [DESIGN.md](./DESIGN.md).

## Current Architecture

Mermaid flowchart of existing system.

## Data Flow

Mermaid sequence diagram of current request/response flow.

## Key Components

### Component A
**Location:** `src/legacy/componentA.ts`

**Responsibilities:**
- Responsibility 1
- Responsibility 2

**Key functions:**
- `functionName()` — Description

## Current Data Model

```typescript
type LegacyResource = {
  id: number;
  name: string;
  // ...
};
```

## Current Limitations

| Limitation | Impact | Priority |
|------------|--------|----------|
| No pagination | Performance issues | High |
| Sync processing | Blocks UI | Medium |

## Pain Points

- Pain point 1: Description and impact
- Pain point 2: Description and impact

## Key Files Affected

| File | Purpose | Migration Impact |
|------|---------|------------------|
| `src/legacy/api.ts` | API client | Replace |
| `src/legacy/types.ts` | Types | Migrate |

## Known Issues & Tech Debt

- Issue 1: Description
- Tech debt: Areas never properly implemented
```
