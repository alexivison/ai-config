# Code Review Reference — Frontend

Rules for reviewing frontend code (React, TypeScript, CSS).

---

## CSS Rules

### Required `[must]`

| Rule | Detection |
|------|-----------|
| Use `gap` for spacing | `margin-top` / `margin-left` between flex/grid children |
| Parent controls child sizing | Child component sets its own margins |
| No CSS nesting | `&` selector used |

### Preferred `[q]`

| Rule | Instead of |
|------|------------|
| Logical properties | `margin-left` → `margin-inline-start` |
| `flex`/`grid` for layout | Floats, absolute positioning for layout |
| `data-*` for dynamic styles | Inline `style` prop for state-based styling |

### Naming `[nit]`

- camelCase for class names
- Root element named `root`
- Name by concern (`userProfile`, not `div1`)

---

## React Rules

### useState `[must]`

| Rule | Detection |
|------|-----------|
| Callback form for current-value updates | `setCount(count + 1)` instead of `setCount(c => c + 1)` |

### Props `[q]`

| Rule | Detection |
|------|-----------|
| Discriminated unions over booleans | `isLoading?: boolean; isError?: boolean` |
| Props should be readonly | `items: Item[]` instead of `readonly items: readonly Item[]` |

### Naming `[q]`

| Rule | Detection |
|------|-----------|
| `handle*` prefix for event handlers | `onClick` as handler name (looks like prop) |
| Purpose-based names | `filteredArray` instead of `visibleItems` |

---

## TypeScript Rules

| Rule | Severity | Detection |
|------|----------|-----------|
| Discriminated unions for state | `[q]` | Optional properties modeling exclusive states |
| No `default` in union switch | `[q]` | `default:` clause hides missing cases |

---

## Testing Rules

### Required `[must]`

| Rule | Detection |
|------|-----------|
| Clear test intent | Test name is code translation (`"0 === false"`) |
| Test spec not implementation | Test breaks when refactoring internals |
| No test dependencies | Tests fail when run in different order |
| Release test doubles | Mocks/spies not cleaned up |

### Test Type Mapping

| Code Type | Test Type |
|-----------|-----------|
| Pure business logic | Unit tests |
| External integrations | Integration tests |
| User-facing components | Component tests |
| Hooks | Component tests (not hook tests) |

---

## Red Flags Checklist

| Flag | Severity |
|------|----------|
| 3+ boolean props | `[q]` |
| useEffect for derived state | `[q]` |
| useState without callback form | `[must]` |
| Props not readonly | `[q]` |
| Comments don't match code | `[must]` |
| `default` in union switch | `[q]` |
| useMemo/useCallback on simple values | `[nit]` |
| Mix of `on*` and `handle*` prefixes | `[nit]` |
| Hardcoded values in comments | `[nit]` |
