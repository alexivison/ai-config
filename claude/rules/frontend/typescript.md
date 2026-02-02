---
paths: ["**/*.ts", "**/*.tsx", "**/*.js", "**/*.jsx"]
---

# TypeScript Rules

- Prefer `type` over `interface` for type definitions
- Avoid `any` and `unknown` - if necessary, add comments explaining why

## Type Safety

- Use `readonly` for props to prevent accidental mutation:
  ```tsx
  type Props = {
    readonly items: readonly Item[];
    readonly onSelect: (id: string) => void;
  };
  ```

- Prefer discriminated unions over optional properties:
  ```tsx
  // Good - states are explicit
  type Result =
    | { kind: 'success'; data: Data }
    | { kind: 'error'; error: Error };

  // Bad - unclear which combinations are valid
  type Result = {
    data?: Data;
    error?: Error;
  };
  ```

- Avoid `default` in switch for union types (hides exhaustiveness):
  ```tsx
  // Good - compiler catches missing cases
  switch (status.kind) {
    case 'success': return status.data;
    case 'error': throw status.error;
  }

  // Bad - new cases silently fall through
  switch (status.kind) {
    case 'success': return status.data;
    default: throw new Error('Unknown');
  }
  ```

## Naming

- Names reflect purpose, not implementation:
  ```tsx
  // Good - describes intent
  const isFeatureEnabled = threshold > 0;
  const visibleItems = items.filter(x => x.visible);

  // Bad - describes implementation
  const thresholdCheck = threshold > 0;
  const filteredArray = items.filter(x => x.visible);
  ```
