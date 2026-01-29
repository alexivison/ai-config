---
paths: ["**/*.tsx", "**/*.jsx"]
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
