---
name: design-check
description: >-
  Verify implemented UI components against Figma designs using Chrome DevTools and
  Figma MCP. Compares layout, spacing, colors, typography, component hierarchy, and
  design tokens. Use when implementing UI from Figma specs, checking design fidelity,
  verifying visual implementation, or whenever someone asks if a component matches
  the design. Requires running Storybook and Chrome DevTools MCP connection.
user-invocable: true
allowed-tools: Bash, Glob, Grep, Read, Agent
---

# Design Check

Verify that implemented UI components match their Figma design by comparing structural data and visual output.

## Inputs

| Input | Source | Example |
|-------|--------|---------|
| Figma URL | Args or TASK file | `https://www.figma.com/design/ABC123/Name?node-id=1234-5678` |
| Storybook URL | Args or TASK file | `http://localhost:6006/?path=/story/parts-banner--default` |

### Parsing

1. **Figma URL** — Extract `fileKey` from path (`/design/<fileKey>/`), `nodeId` from `node-id` query parameter. Convert nodeId separator: `-` → `:` (URLs use `1234-5678`, API uses `1234:5678`).
2. **Storybook URL** — Accept full URL as-is. If only a component path is given (e.g., `Parts/Banner`), convert to story ID: lowercase, `/` → `-`, append `--default`.
3. **Fallback** — If neither is in args, search TASK*.md files in the working directory for lines containing `figma.com` and `localhost:6006`.

## Prerequisites

Before launching the comparison subagent, verify:

1. **Storybook running** — `curl -s -o /dev/null -w "%{http_code}" http://localhost:6006` returns `200`. If not, instruct the user to start Storybook for their project.
2. **Figma URL valid** — `fileKey` matches `^[a-zA-Z0-9]+$`.
3. **Chrome DevTools MCP connected** — Call `mcp__chrome-devtools__list_pages` to verify the connection. If it fails, instruct the user to open Chrome.

## Process

Launch a single `general-purpose` subagent (via Agent tool) with the following prompt template. Replace `{placeholders}` with parsed values.

### Subagent Prompt

````
Compare the Figma design against the Storybook implementation and produce a Design Check Report.

## Figma Reference
- File key: {fileKey}
- Node ID: {nodeId}

## Storybook Reference
- URL: {storybookUrl}

## Error Handling
If any MCP tool call fails (Figma unreachable, Chrome DevTools disconnected, Storybook down), report the failure clearly in the verdict and stop. Do not attempt workarounds.

## Steps

### 1. Fetch Figma Design Data (cached)
Check if `/tmp/design-check/figma/{nodeId}.yaml` exists. If it does, read it instead of calling the API. If not:

Call `mcp__figma__get_figma_data` with fileKey="{fileKey}" and nodeId="{nodeId}".
Save the response to `/tmp/design-check/figma/{nodeId}.yaml` for reuse.

Record: layout mode, justifyContent, alignItems, gap, padding, sizing, dimensions, fills (colors), borderRadius, textStyle (font size/weight/line-height), effects, and child hierarchy.

### 2. Download Figma Reference Image (cached)
Check if `/tmp/design-check/figma/reference.png` exists. If it does, read it. If not:

Call `mcp__figma__download_figma_images` with:
- fileKey: "{fileKey}"
- nodes: [{{ nodeId: "{nodeId}", fileName: "reference.png" }}]
- localPath: "/tmp/design-check/figma"
- pngScale: 2

Read the downloaded image to establish a visual baseline.

### 3. Capture Storybook Render
1. `mcp__chrome-devtools__navigate_page` to "{storybookUrl}"
2. `mcp__chrome-devtools__wait_for` with expected text or element from the component
3. `mcp__chrome-devtools__take_screenshot` — save to "/tmp/design-check/storybook/capture.png"
4. `mcp__chrome-devtools__take_snapshot` — record the a11y tree structure

Read the screenshot to see the rendered output.

### 4. Read Component Source
Use Glob to find the component's `.tsx` and `.module.css` files.
Read them. Note which design system tokens (CSS custom properties) are used and their CSS property assignments.

### 5. Token Audit (deterministic)
This step is mechanical — enumerate every CSS custom property in the component's `.module.css` files and verify each resolves to a non-empty value in the running Storybook.

1. Extract all `var(--*)` token references from the `.module.css` files using Grep:
   ```
   pattern: var\(--[a-zA-Z0-9_-]+
   ```
   Deduplicate the token names.

2. For each unique token, call `mcp__chrome-devtools__evaluate_script` with:
   ```js
   () => {
     const tokens = [{tokenList}];
     const root = document.getElementById('storybook-root')
       || document.querySelector('[data-testid="storybook-root"]')
       || document.body;
     const style = getComputedStyle(root.firstElementChild || root);
     return tokens.map(t => ({
       token: t,
       value: style.getPropertyValue(t).trim() || '** EMPTY — TOKEN DOES NOT EXIST **'
     }));
   }
   ```
   Replace `{tokenList}` with the extracted token names as quoted strings.

3. Any token that returns `** EMPTY **` is a `[must]` finding — the property silently fails and falls back to inherited/default values. Report the exact token name, the CSS file:line where it's used, and the CSS property it's assigned to.

This step catches non-existent tokens deterministically regardless of visual comparison. Do NOT skip it.

### 6. Compare
Read `~/.claude/skills/design-check/reference/comparison-guide.md` for the six comparison dimensions, Figma-to-CSS mapping, and severity classification (`[must]`/`[q]`/`[nit]`). Compare accordingly.

### 7. Produce Report
Output the report in this exact format:

```
## Design Check Report

### Figma Reference
- **File**: {fileKey}
- **Node**: {nodeId} ({node name})
- **Dimensions**: {width}x{height}

### Storybook Reference
- **Story**: {storybook URL}
- **Viewport**: {captured dimensions}

### Token Audit
| Token | Resolves | Used in |
|-------|----------|---------|
| `--token-name` | `#value` or **EMPTY** | `file.module.css:line` (property) |

{List every token. Tokens resolving to EMPTY are auto-classified as `[must]`.}

### Summary
One paragraph: overall alignment quality.

### Must Fix
- **{dimension}** — {discrepancy description}
  Figma: {expected}
  Implementation: {actual}
  File: {file:line}

### Questions
- **{dimension}** — {ambiguity description}

### Nits
- **{dimension}** — {minor note}

### Verdict
**APPROVE** or **REQUEST_CHANGES** or **NEEDS_DISCUSSION**
One sentence explanation.
```

Omit empty sections. APPROVE if no `[must]` findings.
````

### After Subagent Returns

If the verdict is REQUEST_CHANGES, fix `[must]` items and optionally re-run `/design-check` to verify. Surface `[q]` items to the user for decision.
