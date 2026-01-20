#!/bin/bash

# Forced skill evaluation hook
# Injects skill evaluation instructions into prompts to improve activation rates
# Based on: https://scottspence.com/posts/how-to-make-claude-code-skills-activate-reliably

# Read hook input from stdin
INPUT=$(cat)

# Output the forced evaluation instruction
cat << 'EOF'
{
  "hookEventName": "UserPromptSubmit",
  "additionalContext": "<skill-evaluation>\nBefore responding, evaluate if any skill matches this request:\n\n| Skill | Triggers | Match? |\n|-------|----------|--------|\n| write-tests | write tests, add coverage, create test files | YES/NO |\n| code-review | review code, review PR, pre-commit check | YES/NO |\n| minimize | check for bloat, minimize changes, over-engineering | YES/NO |\n| plan-implementation | plan feature, create spec, break down task | YES/NO |\n| address-pr | PR comments, review feedback, reviewer requests | YES/NO |\n| autoskill | learn from session, remember pattern, /autoskill | YES/NO |\n\nIf ANY skill matches YES: Use the Skill tool to invoke it IMMEDIATELY before other work.\nIf ALL skills are NO: Proceed normally.\n</skill-evaluation>"
}
EOF
