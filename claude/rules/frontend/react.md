---
paths: ["**/*.tsx", "**/*.jsx", "**/*.ts", "**/*.js"]
---

# React Rules

- Avoid `React.FC` - use explicit return types (e.g., `const Foo = ({ bar }: Props): JSX.Element => ...`)
- Avoid hardcoding texts - use i18n libraries or other localization methods
- Extract complex inline conditionals in JSX props to named handlers for readability
- Prefer dot notation (`obj.prop`) over bracket notation (`obj['prop']`) for property access

## useEffect Guidelines

- Minimize useEffect usage - prefer derived state, event handlers, or external state management
- Don't use useEffect for state derivation (compute inline instead)
- Don't use useEffect for resetting state on prop change (use `key` prop instead)
- Keep dependency arrays minimal and precise
- Always include cleanup for subscriptions, timers, and async operations
- Multiple related boolean states often indicate need for `useReducer` or state machine

## useState Guidelines

- Use callback form when updating state based on current value:
  ```tsx
  // Good - guaranteed latest value
  setCount(prev => prev + 1);

  // Bad - may use stale value
  setCount(count + 1);
  ```

## Props Design

- Prefer discriminated unions over multiple boolean props:
  ```tsx
  // Good - explicit states, no invalid combinations
  type Props =
    | { status: 'idle' }
    | { status: 'loading' }
    | { status: 'error'; message: string };

  // Bad - combinatorial explosion, invalid states possible
  type Props = {
    isLoading?: boolean;
    isError?: boolean;
    errorMessage?: string;
  };
  ```

## Naming Conventions

- Event handlers use `handle` prefix:
  ```tsx
  // Good
  const handleClick = () => {};
  const handleSubmit = () => {};

  // Bad
  const onClick = () => {};  // Looks like a prop
  const submitForm = () => {};  // Unclear it's a handler
  ```
