#!/usr/bin/env python3
"""
UserPromptSubmit hook: Route to appropriate CLI agent based on user intent.

Analyzes user prompts and suggests cli-orchestrator with appropriate mode
(Codex for design/debug/review, Gemini for research/multimodal).
"""

import json
import sys
import re

# Triggers for Codex (design, debugging, deep reasoning, code review)
CODEX_TRIGGERS = [
    # Design
    r"\bdesign\b", r"\barchitect", r"\bstructur", r"\bpattern\b",
    # Debugging
    r"\bdebug\b", r"\berror\b", r"\bbug\b", r"\bnot working\b", r"\bfails?\b", r"\bbroken\b",
    r"\bwhy\b.*\b(not|isn't|doesn't|won't)\b", r"\broot cause\b",
    # Comparison/Trade-offs
    r"\bcompare\b", r"\btrade-?off\b", r"\bwhich (is |should |would )?(better|best)\b",
    r"\bvs\.?\b", r"\bversus\b", r"\bor\b.*\?\s*$",
    # Implementation decisions
    r"\bhow (to|should|would) (implement|build|create|do)\b",
    # Refactoring
    r"\brefactor\b", r"\bsimplif(y|ied)\b", r"\bclean(er|up)\b",
    # Review
    r"\breview\b", r"\bcheck (this|my|the) code\b", r"\bcode quality\b",
    # Deep thinking
    r"\bthink (about|through|deeply)\b", r"\banalyze\b", r"\bevaluate\b",
]

# Triggers for Gemini (research, multimodal, large context)
GEMINI_TRIGGERS = [
    # Research
    r"\bresearch\b", r"\binvestigat", r"\blook up\b", r"\bfind out\b",
    r"\bbest practices?\b", r"\bhow do (people|others|teams)\b",
    # Documentation
    r"\bdoc(s|umentation)\b", r"\blatest\b.*\b(api|version|release)\b",
    # Multimodal
    r"\bpdf\b", r"\bvideo\b", r"\baudio\b", r"\bimage\b", r"\bscreenshot\b",
    # Large context
    r"\b(entire|whole|full) (codebase|repository|repo)\b",
    r"\bunderstand (the |this )?(codebase|repo|project)\b",
    r"\boverview\b", r"\barchitecture of\b.*\b(codebase|repo|project)\b",
    # Library research
    r"\blibrary\b", r"\bpackage\b", r"\bframework\b", r"\bdependenc",
    r"\bwhat (library|package|tool)\b",
]

# Skip patterns (don't suggest for these)
SKIP_PATTERNS = [
    r"^(yes|no|ok|sure|thanks|thank you|y|n)[\s\.\!]*$",
    r"^(commit|push|pr|merge)\b",
    r"^/",  # Slash commands
]


def matches_any(text: str, patterns: list[str]) -> tuple[bool, str]:
    """Check if text matches any pattern, return (matched, trigger)."""
    for pattern in patterns:
        if re.search(pattern, text, re.IGNORECASE):
            return True, pattern
    return False, ""


def detect_agent(prompt: str) -> tuple[str | None, str]:
    """Detect which CLI should handle this prompt."""
    prompt_lower = prompt.lower().strip()
    
    # Skip short prompts or commands
    if len(prompt_lower) < 15:
        return None, ""
    
    # Skip certain patterns
    for pattern in SKIP_PATTERNS:
        if re.match(pattern, prompt_lower, re.IGNORECASE):
            return None, ""
    
    # Check Codex triggers first (more specific)
    matched, trigger = matches_any(prompt_lower, CODEX_TRIGGERS)
    if matched:
        return "codex", trigger
    
    # Check Gemini triggers
    matched, trigger = matches_any(prompt_lower, GEMINI_TRIGGERS)
    if matched:
        return "gemini", trigger
    
    return None, ""


def main():
    try:
        data = json.load(sys.stdin)
        prompt = data.get("prompt", "")
        
        agent, trigger = detect_agent(prompt)
        
        if agent == "codex":
            suggestion = (
                f"<agent-suggestion tool=\"codex\">\n"
                f"This looks like a task for deep reasoning. Consider using cli-orchestrator:\n"
                f"```\n"
                f"Task tool:\n"
                f"  subagent_type: \"cli-orchestrator\"\n"
                f"  prompt: \"{prompt[:100]}{'...' if len(prompt) > 100 else ''}\"\n"
                f"```\n"
                f"Codex excels at: design decisions, debugging, code review, trade-off analysis.\n"
                f"</agent-suggestion>"
            )
            print(json.dumps({"additionalContext": suggestion}))
        
        elif agent == "gemini":
            suggestion = (
                f"<agent-suggestion tool=\"gemini\">\n"
                f"This looks like a research task. Consider using cli-orchestrator:\n"
                f"```\n"
                f"Task tool:\n"
                f"  subagent_type: \"cli-orchestrator\"\n"
                f"  prompt: \"{prompt[:100]}{'...' if len(prompt) > 100 else ''}\"\n"
                f"```\n"
                f"Gemini excels at: research, codebase analysis, multimodal (PDF/video), library docs.\n"
                f"</agent-suggestion>"
            )
            print(json.dumps({"additionalContext": suggestion}))
        
        else:
            # No suggestion
            print(json.dumps({}))
    
    except Exception:
        # Fail silently
        print(json.dumps({}))


if __name__ == "__main__":
    main()
