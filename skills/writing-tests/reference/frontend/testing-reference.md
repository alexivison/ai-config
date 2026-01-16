# Frontend Testing Reference

A methodology guide for testing frontend applications.

## Testing Philosophy

### Core Principles

1. **Tests are mandatory** - Automated tests enable confident changes and guarantee specifications
   - Exception: PoC code not intended for maintenance

2. **Testing Trophy approach** - Based on Kent C. Dodds' Testing Trophy
   - Prioritize integration tests over unit tests
   - Focus on testing user-visible behavior
   - Balance confidence vs. cost/speed

### Test Classifications

| Type | Description |
|------|-------------|
| **Static Tests** | Type checking, linting |
| **Unit Tests** | Isolated logic, minimal dependencies |
| **Integration Tests** | Multiple modules working together |
| **Component Tests** | UI components and interactions |
| **Visual Regression** | Screenshot comparison |
| **E2E Tests** | Full user flows |

### Component Tests vs Visual Regression

**Component Tests** (preferred for most cases):
- Fast execution, low cost
- Cannot test CSS-based behavior changes

**Visual Regression Tests** (use sparingly):
- Real browser rendering
- Higher cost
- Use for: representative UI states, CSS-dependent behavior

## What to Test

### Guidelines

1. **Pure business logic** → Unit tests (1:1 coverage)
   - Calculation logic, parsing, data transformations

2. **External layer integrations** → Integration tests
   - Network requests, LocalStorage, URL parameters
   - Test from the interface that components consume

3. **User-facing components** → Component tests
   - Test at appropriate granularity (form level, not individual inputs)
   - Focus on user interactions and outcomes

4. **Hooks extracted from components** → Component tests (not hook tests)
   - Testing via component is closer to user behavior
   - Exception: highly reusable utility hooks

### What NOT to Test

- Don't re-test lower-level logic at higher levels
- Don't test external module behavior (use test doubles)
- Don't exhaustively test input variations at page level

## When to Write Tests

Write tests as early as possible:
1. Implement minimal functionality
2. Write tests for that functionality
3. Evolve tests and implementation together (TDD style)

## PR Strategy

**Include tests in the same PR as implementation** because:
- No safety guarantee without tests
- No guarantee tests will be added later
- Different reviewers may review implementation vs tests

**Managing PR size:**
- Build features incrementally (thin slices)
- Split behavior changes into smaller PRs

---

## Setup Patterns

### Test Setup File

Create a setup file that:
- Mocks browser APIs not available in test environment (IntersectionObserver, ResizeObserver, etc.)
- Imports assertion matchers
- Configures global test behavior

### Custom Render Function

Wrap the default render with your app's providers:

```
customRender(ui, options)
  → render(ui, { wrapper: TestProvider, ...options })
```

### Test Provider

Wrap components with necessary context:
- Router context
- State management provider
- Auth context (mocked)
- Any other required providers

### Fail on Console Errors

Configure tests to fail on `console.error` or `console.warn` to catch silent failures.

---

## Mocking Strategies

### API Mocking

Mock at the network level (not module level) for realistic tests:
- Intercept HTTP requests
- Return mock responses
- Verify request payloads

### Mock Data Factories

Create factory functions for test data:

```
mockUser(override?) → { id, name, email, ...override }
```

Benefits:
- Consistent test data
- Easy to override specific fields
- Single source of truth for data shape

**Use unique, searchable values** in mock data for easier debugging:
- Bad: `{ name: "Test User" }`
- Good: `{ name: "user_alice_checkout_test" }`

### spyOn vs vi.mock

Prefer `spyOn` over `vi.mock` when possible:
- Better type safety
- Easier to restore original implementation
- More explicit about what's being mocked

### Feature Flag Mocking

Options:
- Mock the feature flag hook/function
- Provide a test wrapper with flag context
- Use environment variables

---

## Test Patterns

### Unit Test Pattern

```
describe('functionName', () => {
  it('describes expected behavior in plain English', () => {
    // Arrange
    // Act
    // Assert
  });

  it.each(cases)('handles multiple cases', (input, expected) => {
    // Parameterized test
  });
});
```

### Component Test Pattern

```
describe('ComponentName', () => {
  test('displays expected content', () => {
    render(<Component />);
    expect(screen.getByText('...')).toBeInTheDocument();
  });

  test('handles user interaction', async () => {
    render(<Component />);
    await user.click(screen.getByRole('button'));
    expect(screen.getByText('result')).toBeInTheDocument();
  });
});
```

### Async Component Pattern

For components with data fetching:
1. Render the component
2. Wait for loading state to resolve
3. Assert on loaded content

---

## Query Priority

Use queries in this priority order (most to least preferred):

1. `getByRole()` — buttons, headings, forms (most accessible)
2. `getByLabelText()` — form inputs with labels
3. `getByPlaceholderText()` — inputs without visible labels
4. `getByText()` — non-interactive content
5. `getByTestId()` — last resort only

---

## Assertions

### Visibility
- Use `toBeVisible()` for user-visible elements (respects CSS visibility)
- Use `toBeInTheDocument()` only when checking DOM presence regardless of visibility

### Specificity
- Avoid `.toBeDefined()` — assert actual expected values instead
- Bad: `expect(result).toBeDefined()`
- Good: `expect(result).toBe('expected value')`

### State Management
- Don't test Redux/state internals — verify rendered output only

---

## Async Patterns

### Prefer findBy over waitFor

For elements appearing asynchronously:
```
// Preferred
const element = await screen.findByText('Loaded');

// Avoid when findBy works
await waitFor(() => {
  expect(screen.getByText('Loaded')).toBeInTheDocument();
});
```

### Use Fake Timers

Don't wait in real time — mock time progression:
```
vi.useFakeTimers();
// trigger async operation
vi.advanceTimersByTime(1000);
vi.useRealTimers();
```

---

## User Interactions

Always use `userEvent` over `fireEvent`:
- `userEvent` simulates realistic browser behavior (focus, blur, typing sequence)
- `fireEvent` only dispatches DOM events

```
// Preferred
await user.click(button);
await user.type(input, 'text');

// Avoid
fireEvent.click(button);
fireEvent.change(input, { target: { value: 'text' } });
```

---

## Anti-Patterns

| Pattern | Problem | Solution |
|---------|---------|----------|
| Conditionals in tests | Hide failures, unclear intent | Write separate tests for each case |
| Large snapshots | Brittle, hard to review | Use targeted assertions |
| Class name assertions | Tests implementation, not behavior | Query by role/text, assert visible state |
| Flaky tests | Erode trust in test suite | Fix immediately or delete |
| Real timers | Slow tests, race conditions | Use fake timers |

---

## Best Practices Summary

1. **Use custom render** - Always wrap with app providers
2. **Query by role/label** - Use accessible queries (`getByRole`, `getByLabelText`)
3. **Avoid implementation details** - Test behavior, not internal state
4. **One assertion focus** - Each test should verify one concept
5. **Simulate real user interactions** - Click, type, not programmatic state changes
6. **Mock at boundaries** - Mock network, not internal functions
7. **Isolate tests** - Fresh state per test, no cross-test dependencies
8. **Fail on console errors** - Treat warnings as failures
