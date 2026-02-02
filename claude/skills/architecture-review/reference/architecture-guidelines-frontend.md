# Architecture Review Reference — Frontend (React/TypeScript)

React-specific patterns, smells, and thresholds.

---

## Metrics

| Metric | Warn `[q]` | Block `[must]` |
|--------|------------|----------------|
| useState count | >4 | >6 |
| useEffect count | >2 | >4 |
| Boolean state vars | >3 | >5 |
| useMemo/useCallback count | >5 | >8 |
| Prop count | >8 | >12 |
| useEffect deps array | >5 items | >8 items |
| Nested JSX conditionals | >2 levels | >3 levels |
| Component lines | >200 | >300 |

---

## Layer Violations `[must]`

| Detection | Issue |
|-----------|-------|
| Component contains `fetch()` or API call | Components should use hooks/services |
| Hook returns JSX | Hooks shouldn't render |
| Business logic in component body | Extract to hook or service |
| Utils importing React or using state | Utils must be pure |

---

## React Smells

### Blocking `[must]`

| Smell | Detection |
|-------|-----------|
| State Management Sprawl | Multiple useState that always change together |
| Impossible States | Boolean flags that can be true simultaneously but shouldn't |
| God Component | >300 lines, multiple unrelated features |
| Prop Drilling | Props passed through 3+ levels unused |

### Warning `[q]`

| Smell | Detection |
|-------|-----------|
| useEffect for derived state | `setX(computed from y)` inside useEffect |
| Missing cleanup | useEffect with subscription/timer but no return |
| Over-memoization | useMemo/useCallback on primitives or simple objects |
| Boolean prop explosion | 3+ boolean props on same component |

---

## Anti-Patterns

### useEffect Overuse `[q]`

| Pattern | Detection | Should Be |
|---------|-----------|-----------|
| Derived state | `useEffect(() => setFullName(...), [first, last])` | `const fullName = ...` |
| Reset on prop change | `useEffect(() => setCount(0), [id])` | `<Component key={id} />` |
| Fetch without cleanup | `useEffect(() => fetch().then(setData), [])` | Add cancellation |

### State Modeling `[q]`

| Pattern | Detection |
|---------|-----------|
| Implicit state machine | `isLoading`, `hasError`, `isSuccess` as separate booleans |
| Optional prop sprawl | `isX?: boolean; isY?: boolean; isZ?: boolean` |

---

## Detection Patterns

**Boolean state detection:**
```typescript
useState<boolean>
useState(true)
useState(false)
const [is*, setIs*] = useState
const [has*, setHas*] = useState
```

**Prop drilling detection:**
```typescript
// Props received but only passed to children, not used
function Parent({ userId, config }: Props) {
  return <Child userId={userId} config={config} />
}
```

**Nested conditional detection:**
```tsx
{condition1 && (
  {condition2 ? (
    {condition3 && <Deep />}  // Level 3 — TRIGGERED
  ) : null}
)}
```

---

## Verdicts

| Verdict | Condition |
|---------|-----------|
| **SKIP** | All metrics below warn thresholds |
| **APPROVE** | Deep review passed, no `[must]` |
| **REQUEST_CHANGES** | Has `[must]` or unresolved `[q]` |
| **NEEDS_DISCUSSION** | Major refactoring needed |
