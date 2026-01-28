# Architecture Guidelines — Frontend (React/TypeScript)

React-specific patterns, smells, and thresholds.

---

## Metrics

| Metric | Threshold | Rationale |
|--------|-----------|-----------|
| useState count | >4 | More than 4 state variables suggests need for useReducer or state machine |
| useEffect count | >2 | Multiple effects often indicate mixed concerns or missing abstractions |
| Boolean state vars | >3 | Related booleans often form implicit state machines |
| useMemo/derived | >5 | Excessive memoization suggests computation should live elsewhere |
| Prop count | >8 | Too many props indicates component doing too much |
| useEffect deps | >5 items | Large dependency arrays suggest design issues |
| Nested conditionals | >2 levels | Deep nesting reduces readability and maintainability |

---

## Detection Patterns

**Boolean state detection:**
```typescript
// Direct boolean useState
useState<boolean>
useState(true)
useState(false)

// Naming conventions (common boolean patterns)
const [isLoading, setIsLoading] = useState
const [hasError, setHasError] = useState
const [should*, setShould*] = useState
const [can*, setCan*] = useState
```

**Prop drilling detection:**
```typescript
// Props received but only passed to children
function Parent({ userId, onUpdate, config }: Props) {
  return <Child userId={userId} onUpdate={onUpdate} config={config} />
  // userId, onUpdate, config not used in Parent — prop drilling
}
```

**Nested conditional detection:**
```tsx
// Level 1
{condition1 && (
  // Level 2
  {condition2 ? (
    // Level 3 — TRIGGERED
    {condition3 && <Deep />}
  ) : null}
)}
```

---

## Frontend Layer Model

```
┌─────────────────────────────────────┐
│           Components (View)         │  UI rendering, event handling
├─────────────────────────────────────┤
│           Hooks (Logic)             │  State management, side effects
├─────────────────────────────────────┤
│         Services (Data)             │  API calls, data transformation
├─────────────────────────────────────┤
│           Utils (Pure)              │  Pure functions, no side effects
└─────────────────────────────────────┘
```

**Violations to detect:**
- Components doing data fetching directly
- Hooks containing JSX or rendering logic
- Business rules scattered across components
- Utils with side effects or state

---

## React Smells

### State Management Sprawl

**Symptoms:**
- Multiple `useState` calls that change together
- Boolean flags that form implicit state machine
- State derivation chains (`isReady = !isLoading && !hasError && data`)
- Frequent "impossible states" bugs

**Example (bad):**
```typescript
const [isLoading, setIsLoading] = useState(false);
const [hasError, setHasError] = useState(false);
const [isSuccess, setIsSuccess] = useState(false);
const [data, setData] = useState(null);

// 2^4 = 16 possible states, most invalid
// e.g., isLoading && isSuccess should never happen
```

**Recommendation:**
```typescript
type State =
  | { status: 'idle' }
  | { status: 'loading' }
  | { status: 'error'; error: Error }
  | { status: 'success'; data: Data };

const [state, dispatch] = useReducer(reducer, { status: 'idle' });
// Only 4 valid states, transitions are explicit
```

### Single Responsibility Violations

**Symptoms:**
- Hook/component name doesn't describe what it does
- Multiple unrelated useEffect blocks
- Mixed data fetching, business logic, and UI concerns
- Difficult to test in isolation

**Example (bad):**
```typescript
function useConversation() {
  // Concern 1: Connection management
  const [socket, setSocket] = useState(null);
  useEffect(() => { /* connect */ }, []);

  // Concern 2: Message handling
  const [messages, setMessages] = useState([]);
  useEffect(() => { /* listen */ }, [socket]);

  // Concern 3: Polling fallback
  const [isPolling, setIsPolling] = useState(false);
  useEffect(() => { /* poll */ }, [isPolling]);

  // Concern 4: Error recovery
  const [retryCount, setRetryCount] = useState(0);
  useEffect(() => { /* retry */ }, [retryCount]);
}
```

**Recommendation:**
```typescript
function useConversation() {
  const connection = useConnection();
  const messages = useMessages(connection);
  const polling = usePollingFallback(connection);
  // Compose focused hooks
}
```

### Prop Drilling

**Symptoms:**
- Props passed through 3+ component levels
- Intermediate components don't use the props
- Adding new data requires touching many files

**Detection:**
- Component receives props only to pass them down
- Props type includes many optional fields
- Context would simplify the data flow

**Recommendation:**
- Use React Context for truly global state
- Compose components to reduce prop passing
- Consider state management library for complex cases

### God Components

**Symptoms:**
- >300 lines of code
- Handles multiple unrelated features
- Many useState calls
- Difficult to name accurately

**Recommendation:**
- Extract logical sub-components
- Move state to custom hooks
- Use composition over configuration

---

## React Anti-Patterns

### useEffect Overuse

**Bad patterns:**
```typescript
// Deriving state in useEffect (should be computed)
useEffect(() => {
  setFullName(firstName + ' ' + lastName);
}, [firstName, lastName]);

// Resetting state on prop change (should use key)
useEffect(() => {
  setCount(0);
}, [userId]);

// Fetching without cleanup
useEffect(() => {
  fetchData().then(setData);
}, [id]);
```

**Better:**
```typescript
// Derived value (no state needed)
const fullName = firstName + ' ' + lastName;

// Key-based reset
<Counter key={userId} />

// Fetch with cleanup
useEffect(() => {
  let cancelled = false;
  fetchData().then(d => !cancelled && setData(d));
  return () => { cancelled = true; };
}, [id]);
```

### Over-Memoization

**Symptoms:**
- useMemo/useCallback on every value
- No measured performance problem
- Premature optimization

**When to memoize:**
- Expensive calculations (measure first!)
- Referential equality for useEffect deps
- Passing callbacks to memoized children
- Rendering large lists

---

## Recommended Patterns

### Explicit State Machines

For complex state with many transitions:
```typescript
type State = 'idle' | 'loading' | 'success' | 'error';
type Action =
  | { type: 'FETCH' }
  | { type: 'SUCCESS'; data: Data }
  | { type: 'ERROR'; error: Error };

function reducer(state: State, action: Action): State {
  switch (state) {
    case 'idle':
      if (action.type === 'FETCH') return 'loading';
      break;
    case 'loading':
      if (action.type === 'SUCCESS') return 'success';
      if (action.type === 'ERROR') return 'error';
      break;
    // ...
  }
  return state;
}
```

### Composition Over Configuration

```typescript
// Bad: One component with many props
<DataTable
  data={data}
  sortable
  filterable
  paginated
  editable
  onSort={...}
  onFilter={...}
  onPageChange={...}
  onEdit={...}
/>

// Good: Composed behavior
<DataTable data={data}>
  <Sortable onSort={...} />
  <Filterable onFilter={...} />
  <Paginated onPageChange={...} />
</DataTable>
```

### Custom Hook Extraction

```typescript
// Extract when:
// - Logic is reusable
// - Hook has clear single purpose
// - Testing in isolation is valuable

function useDebounce<T>(value: T, delay: number): T {
  const [debouncedValue, setDebouncedValue] = useState(value);

  useEffect(() => {
    const timer = setTimeout(() => setDebouncedValue(value), delay);
    return () => clearTimeout(timer);
  }, [value, delay]);

  return debouncedValue;
}
```

---

## Sources

- [Modularizing React Apps - Martin Fowler](https://martinfowler.com/articles/modularizing-react-apps.html)
- [React Anti-Patterns - ITNEXT](https://itnext.io/6-common-react-anti-patterns-that-are-hurting-your-code-quality-904b9c32e933)
- [A Complete Guide to useEffect - Dan Abramov](https://overreacted.io/a-complete-guide-to-useeffect/)
