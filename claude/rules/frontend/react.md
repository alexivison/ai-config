---
paths: ["**/*.tsx", "**/*.jsx", "**/*.ts", "**/*.js"]
---

# React Rules

- Avoid `React.FC` — use explicit return types
- Avoid hardcoding texts — use i18n
- Extract complex inline JSX conditionals to named handlers
- Prefer dot notation for property access

## useEffect

Minimize usage — prefer derived state, event handlers, or external state management. Don't use for state derivation (compute inline) or resetting state on prop change (use `key`). Always cleanup subscriptions/timers.

## useState

Use callback form for state based on current value: `setCount(prev => prev + 1)`.

## Props

Prefer discriminated unions over boolean props to prevent invalid state combinations.

## Naming

Event handlers use `handle` prefix: `handleClick`, `handleSubmit`.
