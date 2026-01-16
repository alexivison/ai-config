# Frontend Testing Reference

A comprehensive guide to testing practices in the frontend codebase.

## Testing Philosophy

### Core Principles

1. **Tests are mandatory** - Automated tests are expected for all production code
   - Enable confident future changes (supporting continuous software improvement)
   - Guarantee that changes meet specifications (more reliable than code review alone)
   - Exception: PoC code not intended for maintenance

2. **Testing Trophy approach** - Based on Kent C. Dodds' Testing Trophy
   - Prioritize integration tests over unit tests
   - Focus on testing user-visible behavior
   - Balance confidence vs. cost/speed

### Test Classifications

| Type | Description | Tools |
|------|-------------|-------|
| **Static Tests** | Type checking, linting | TypeScript, ESLint |
| **Unit Tests** | Isolated logic, minimal dependencies | Vitest |
| **Integration Tests** | Multiple modules working together | Vitest, MSW |
| **Component Tests** | React components and interactions | Vitest, React Testing Library |
| **Visual Regression** | Screenshot comparison | Chromatic (planned) |
| **E2E Tests** | Full user flows | Playwright |

### Component Tests vs Visual Regression Tests

**Component Tests** (preferred for most cases):
- Fast execution, low cost
- Vitest + testing-library
- Cannot test CSS-based behavior changes

**Visual Regression Tests** (use sparingly):
- Real browser rendering
- Higher cost (Chromatic subscription)
- Use for: representative UI states, CSS-dependent behavior (text overflow, dynamic sizing)

## What to Test

### Guidelines

1. **Pure business logic** → Unit tests (1:1 coverage)
   - Calculation logic, parsing, data transformations

2. **External layer integrations** → Integration tests
   - Network requests, LocalStorage, URL parameters
   - Test from the interface that React components/hooks consume (typically Repository layer)

3. **User-facing components** → Component tests
   - Test at appropriate granularity (form level, not individual inputs)
   - Focus on user interactions and outcomes

4. **Hooks extracted from components** → Component tests (not hook tests)
   - Testing via component is closer to user behavior
   - Exception: highly reusable utility hooks can have dedicated tests

### What NOT to Test

- Don't re-test lower-level logic at higher levels
- Don't test external module behavior (use test doubles)
- Don't exhaustively test input variations at page level (test at input component level)

## When to Write Tests

Write tests as early as possible:
1. Implement minimal functionality (return fixed values)
2. Write tests for that functionality
3. Evolve tests and implementation together (TDD style)

## PR Strategy

**Include tests in the same PR as implementation** - Avoid separate test PRs because:
- No safety guarantee without tests
- No guarantee tests will be added later
- Different reviewers may review implementation vs tests

**Managing PR size:**
- Build features incrementally (thin slices)
- Split behavior changes into smaller PRs
- Use `.todo()` to outline planned tests (create tickets for tracking)

---

## Technical Setup

### Frameworks & Libraries

| Package | Version | Purpose |
|---------|---------|---------|
| `vitest` | 2.1.9+ | Test runner |
| `@testing-library/react` | 16.3.1 | Component/hook testing |
| `@testing-library/user-event` | 14.6.1 | User interaction simulation |
| `@testing-library/jest-dom` | 6.9.1 | DOM matchers |
| `msw` | 2.12.4 | API mocking |
| `jsdom` | 25+ | Browser environment simulation |

**Why jsdom over happy-dom?**
- happy-dom has issues with certain interactions (e.g., `fireEvent.change` on text inputs)
- jsdom is slower but more reliable

### File Organization

```
src/
├── parts/                      # UI components
│   └── ComponentName/
│       ├── index.tsx
│       └── index.test.tsx      # Component test
├── repositories/               # API layer
│   ├── mock.ts                 # Centralized MSW handlers
│   └── feature/
│       ├── adapter/
│       │   ├── index.ts
│       │   └── index.test.ts   # Adapter test
│       ├── index.ts
│       └── mock.ts             # Feature-specific mocks
├── domains/
│   ├── models/
│   │   └── entityName/
│   │       ├── index.ts
│   │       └── utils.test.ts   # Utility tests
│   └── interactors/
│       └── feature/
│           └── index.test.ts   # Business logic tests
```

**Naming convention:** `*.test.ts` or `*.test.tsx`

### Configuration

**Vitest config** (in `vite.config.ts`):
```typescript
test: {
  globals: true,
  environment: 'jsdom',
  setupFiles: ['./test/setup.ts', './test/msw/setup.ts', './test/failOnConsole.ts'],
  exclude: ['node_modules/**/*'],
  coverage: {
    reporter: ['html', 'lcov'],
    reportsDirectory: 'coverage',
  },
}
```

### Setup Files

**`test/setup.ts`** - Browser API mocks and jest-dom:
```typescript
// Mock browser APIs not available in jsdom
import './mocks/intersectionObserver';
import './mocks/resizeObserver';
import '@testing-library/jest-dom';
```

**`test/failOnConsole.ts`** - Fail on console errors/warnings:
- Tests fail if `console.error` or `console.warn` are called
- Allowlist for known warnings (e.g., React Router deprecation notices)

### Custom Render Functions

**`test/customRender.ts`:**
```typescript
export const customRender = (
  ui: Parameters<typeof render>[0],
  options?: Omit<Parameters<typeof render>[1], 'wrapper'>,
): ReturnType<typeof render> => render(ui, { wrapper: TestProvider, ...options });

export const customRenderHook = <Result, Props>(
  render: (initialProps: Props) => Result,
  options?: Omit<Parameters<typeof renderHook>[1], 'wrapper'>,
): RenderHookResult<Result, Props> => renderHook(render, { wrapper: TestProvider, ...options });
```

**For async/Suspense components:**
```typescript
export const customAsyncRender = async (
  ui: Parameters<typeof customRender>[0],
  options?: Parameters<typeof customRender>[1],
): Promise<ReturnType<typeof render>> => {
  const rendered = customRender(ui, { ...options });
  await waitForSuspense();
  return rendered;
};
```

### Test Provider

Wraps components with all necessary context providers:
```typescript
export const TestProvider = ({ children }: { children: React.ReactNode }): JSX.Element => {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });

  return (
    <QueryClientProvider client={queryClient}>
      <RouterProvider router={createMemoryRouter([{ path: '*', element: children }])}>
        {children}
      </RouterProvider>
    </QueryClientProvider>
  );
};
```

---

## Mocking Strategies

### MSW (Mock Service Worker)

**Setup** (`test/msw/setup.ts`):
```typescript
beforeAll(() => {
  queryClient = createQueryClient({ defaultOptions: { queries: { retry: false } } });
  server.listen();
});

afterEach(() => {
  server.resetHandlers();
  queryClient?.clear();
});

afterAll(() => {
  server.close();
});
```

**Handler factory pattern**:
```typescript
import { http, HttpResponse } from 'msw';

// Mock data factory
export const mockUser = (override?: Partial<User>): User => ({
  id: '550e8400-e29b-41d4-a716-446655440000',
  name: 'Test User',
  email: 'test@example.com',
  ...override,
});

// Handler factory
export const createUserHandlers = (data = mockUser()) => [
  http.get('/api/users/:id', () => HttpResponse.json(data)),
  http.post('/api/users', async ({ request }) => {
    const body = await request.json();
    return HttpResponse.json({ ...data, ...body }, { status: 201 });
  }),
];
```

### Feature Flag Mocking

```typescript
// Mock feature flag provider or use vi.mock
vi.mock('@/hooks/useFeatureFlag', () => ({
  useFeatureFlag: (flag: string) => flag === 'new-feature',
}));

// Or use a test wrapper with flag context
const TestProviderWithFlags = ({ children, flags }) => (
  <FeatureFlagContext.Provider value={flags}>
    {children}
  </FeatureFlagContext.Provider>
);
// ... test code
```

### Vitest Spying

```typescript
const mockCallback = vi.fn();
vi.spyOn(module, 'functionName').mockReturnValue(value);
vi.spyOn(console, 'error').mockImplementationOnce(() => {});
```

---

## Test Patterns

### Unit Test Pattern

```typescript
describe('convertToRepositoryError', () => {
  it('normalizes non-ConnectError to Unknown and preserves cause', () => {
    const original = new Error('test');
    const result = convertToRepositoryError(original);

    expect(result).toBeInstanceOf(RepositoryError);
    expect(result.code).toBe('Unknown');
    expect(result.cause).toBe(original);
  });

  it.each(cases)('maps ConnectError code to RepositoryError code', ({ connectCode, expected }) => {
    const err = new ConnectError('test', connectCode);
    const result = convertToRepositoryError(err);

    expect(result.code).toBe(expected);
  });
});
```

### Component Test Pattern

```typescript
describe('ConversationActionMenu', () => {
  const mockOnClick = vi.fn();

  test('displays menu icon with accessible label', () => {
    customRender(<ConversationActionMenu {...props} />);
    expect(screen.getByLabelText('Menu')).toBeInTheDocument();
  });

  test('shows menu items when opened', async () => {
    customRender(<ConversationActionMenu {...props} />);
    await userEvent.click(screen.getByLabelText('Menu'));

    expect(screen.getByText('Edit')).toBeInTheDocument();
    expect(screen.getByText('Delete')).toBeInTheDocument();
  });

  test('opens dialog on edit click', async () => {
    customRender(<ConversationActionMenu {...props} />);
    await userEvent.click(screen.getByLabelText('Menu'));
    await userEvent.click(screen.getByText('Edit'));

    await waitFor(() => {
      expect(screen.getByRole('dialog', { name: 'Edit' })).toBeInTheDocument();
    });
  });
});
```

### Hook Test Pattern

```typescript
it('returns merged values from localStorage and defaults', async () => {
  vi.spyOn(localStorage, 'getLocalStorageValue').mockImplementation(() => ok(mockData));

  const { result } = customRenderHook(() => useGetTableRowTitles({ enabled: true }));

  await waitFor(() => expect(result.current.data).not.toBe(null));
  expect(result.current.data).toEqual(expectedData);
});
```

### Async Component Test Pattern

```typescript
test('renders data after loading', async () => {
  const rendered = await customAsyncRender(<AsyncComponent />);

  expect(rendered.getByText('Loaded Data')).toBeInTheDocument();
});
```

### XSS Prevention Test

```typescript
describe('XSS protection', () => {
  it('does not render XSS scripts', () => {
    const maliciousText = "<iframe srcdoc='<script>alert()</script>'></iframe>";
    customRender(<MarkdownText>{maliciousText}</MarkdownText>);

    expect(screen.queryByText('alert')).not.toBeInTheDocument();
  });
});
```

---

## Scripts

```bash
# Run tests
pnpm test

# Run with coverage
pnpm test:coverage

# Run Storybook tests
pnpm test:storybook
```

---

## Storybook Integration

Tests can be written within Storybook stories using `@storybook/experimental-addon-test`.

**Preview setup** (`.storybook/preview.tsx`):
```typescript
import { handlers } from '@repositories/mock';
import { initialize, mswLoader } from 'msw-storybook-addon';

initialize({ onUnhandledRequest: 'error' });

const preview: Preview = {
  parameters: { msw: { handlers } },
  decorators: [(Story) => <TestProvider><Story /></TestProvider>],
  loaders: [mswLoader],
};
```

---

## Best Practices Summary

1. **Use `customRender`/`customRenderHook`** - Always use custom wrappers, never raw render
2. **Query by role/label** - Use accessible queries (`getByRole`, `getByLabelText`)
3. **Avoid implementation details** - Test behavior, not internal state
4. **One assertion focus** - Each test should verify one concept
5. **Use `userEvent` over `fireEvent`** - More realistic user interactions
6. **Mock at boundaries** - Mock network, not internal functions
7. **Fresh QueryClient per test** - Prevent cross-test pollution
8. **Fail on console errors** - Treat warnings as failures
