# TASK.md Template

**Answers:** "What exactly do I do for this step?"

File naming: `TASK1.md`, `TASK2.md`, `TASK3.md`, ...

## Structure

```markdown
# Task N — <Short Description>

**Estimated LOC:** ~<number> | **Dependencies:** <Task X, Task Y>

---

## Goal

One paragraph: what this accomplishes and why.

## Required Context

Files agent MUST read before starting:

- `src/path/to/related.ts` — Existing pattern
- `src/path/to/types.ts` — Type definitions
- `src/path/to/similar.ts:50-120` — Reference implementation

## Files to Modify

| File | Action | Description |
|------|--------|-------------|
| `src/api/users.ts` | Modify | Add endpoint |
| `src/types/user.ts` | Modify | Add types |
| `src/api/__tests__/users.test.ts` | Create | Tests |

## Development Plan

### Step 1: <Description>

**File:** `src/path/to/file.ts`

Before:
```typescript
export const existing = () => oldValue;
```

After:
```typescript
export const existing = () => newValue;
export const newFunc = () => { /* ... */ };
```

### Step 2: <Description>

**File:** `src/path/to/other.ts`

```typescript
// Code to add
```

### Step 3: Write Tests

**File:** `src/__tests__/file.test.ts`

```typescript
describe('newFunc', () => {
  it('handles happy path', () => { /* ... */ });
  it('handles error', () => { /* ... */ });
});
```

## Verification Commands

```bash
pnpm tsc --noEmit
pnpm test src/__tests__/file.test.ts
pnpm lint
```

## Acceptance Criteria

- [ ] All files updated
- [ ] Types pass
- [ ] Tests pass
- [ ] Lint passes

## Rollback

```bash
git checkout -- <files>
```
```
