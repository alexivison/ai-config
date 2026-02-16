# DESIGN.md Template

**Answers:** "How will it work?"

## Structure

```markdown
# <Feature Name> Design

> **Specification:** [SPEC.md](./SPEC.md)

## Architecture Overview

High-level description with Mermaid flowchart.

## Existing Standards (REQUIRED)

**Purpose:** Make standards explicit to avoid shallow exploration ("low-context化").

List existing patterns that this feature MUST follow. **Locations must include file:line references** (not just file names).

| Pattern | Location | How It Applies |
|---------|----------|----------------|
| DataSource pattern | `domain/datasource.go:45-89` | New data types extend this |
| Permission checking | `middleware/auth.go:123` (`checkPermission()`) | Use for new endpoints |
| Proto → Domain conversion | `http/v1/translator.go:78-95` | Add new field converters here |

**Why these standards:** Brief rationale for each pattern choice.

> **Enforcement:** Generic patterns without file:line references will be rejected during plan review.

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

## Data Transformation Points (REQUIRED)

**Purpose:** Map every point where data changes shape. Bugs often hide in conversions.

List ALL functions/methods that transform data. **Must include file:line references.**

**CRITICAL:** List converters for **each code path/variant** separately.

- Use "Shared" only for converters that are truly shared across all paths
- Do NOT collapse path-specific converters into a single row

Examples of variants to list separately:
- Streaming vs non-streaming endpoints
- Sync vs async handlers
- Create vs update operations
- Different API versions (v1, v2)

| Layer Boundary | Code Path | Function | Input → Output | Location |
|----------------|-----------|----------|----------------|----------|
| Proto → Domain | Shared | `domainModelFromProto()` | `pb.Request` → `domain.Model` | `translator.go:45-67` |
| Params conversion | Path A | `convertToPathAParams()` | `RequestA` → `Params` | `usecase.go:234-256` |
| Params conversion | Path B | `convertToPathBParams()` | `RequestB` → `Params` | `usecase.go:178-195` |
| Params adapter | A→B | `convertParams()` | `ParamsA` → `ParamsB` | `usecase.go:260-280` |
| Domain → Response | Shared | `toProtoResponse()` | `domain.Result` → `pb.Response` | `translator.go:89-105` |

**New fields must flow through ALL transformations for ALL code paths.**

> **Silent drop check:** For each converter, verify: "If I add field X to input, will it appear in output?" If not, BUG.

## Integration Points (REQUIRED)

**Purpose:** Identify where new code touches existing code.

| Point | Existing Code | New Code Interaction |
|-------|---------------|----------------------|
| Handler entry | `handler.go:CreateTurn()` | Extract new field from request |
| Usecase boundary | `usecase.go:Execute()` | Pass new field in params |
| Params adapter | `usecase.go:convertToParams()` | **CRITICAL: Must include new field** |

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

## Design Decisions

**Purpose:** Document WHY, not just WHAT.

| Decision | Rationale | Alternatives Considered |
|----------|-----------|-------------------------|
| Use existing DataSource | Consistency with existing pattern | New separate field (rejected: fragmentation) |
| Permission check in handler | Fail fast before business logic | Check in usecase (rejected: wasted computation) |

## External Dependencies

- **Backend API:** endpoint (link to docs)
- **Library:** `package@version` for X
```
