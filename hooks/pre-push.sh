#!/bin/bash

# Claude Code pre-push hook
# This hook runs before pushing code to ensure quality checks pass
# Supports: Frontend (pnpm), Go (make), Java (gradle), Python (make)
# Compatible with Bash 3.2+ (macOS default)
#
# Optimizations:
# - Only checks the current project (based on working directory)
# - Runs lint and typecheck in parallel

# Read hook input from stdin
INPUT=$(cat)
if ! COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null); then
    exit 0  # Don't block on parse errors
fi

# Only run for git push commands
if [ -z "$COMMAND" ] || ! echo "$COMMAND" | grep -qE 'git\s+push'; then
    exit 0
fi

# Get working directory from hook input, fall back to cwd
WORKING_DIR=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
if [ -z "$WORKING_DIR" ]; then
    WORKING_DIR=$(pwd)
fi

set -e

echo "Running pre-push checks..." >&2

# Get the repository root
REPO_ROOT=$(git rev-parse --show-toplevel)

# Detect current project from working directory
detect_current_project() {
    local dir="$1"
    local rel_path

    # Get path relative to repo root
    rel_path="${dir#$REPO_ROOT/}"

    # Match services/<project>
    if echo "$rel_path" | grep -qE '^services/[^/]+'; then
        echo "$rel_path" | sed -E 's|^(services/[^/]+).*|\1|'
        return 0
    fi

    # Match libraries/<category>/<project>
    if echo "$rel_path" | grep -qE '^libraries/[^/]+/[^/]+'; then
        echo "$rel_path" | sed -E 's|^(libraries/[^/]+/[^/]+).*|\1|'
        return 0
    fi

    return 1
}

CURRENT_PROJECT=$(detect_current_project "$WORKING_DIR") || true

if [ -z "$CURRENT_PROJECT" ]; then
    echo "Not in a services/ or libraries/ directory, skipping checks" >&2
    exit 0
fi

# Validate project path exists
FULL_PROJECT_PATH="$REPO_ROOT/$CURRENT_PROJECT"
if [ ! -d "$FULL_PROJECT_PATH" ]; then
    echo "Project directory not found: $CURRENT_PROJECT" >&2
    exit 0
fi

echo "Current project: $CURRENT_PROJECT" >&2
echo "" >&2

# Create temp files for parallel command outputs
LINT_OUTPUT=$(mktemp)
TYPECHECK_OUTPUT=$(mktemp)
trap "rm -f '$LINT_OUTPUT' '$TYPECHECK_OUTPUT'" EXIT

# Run a command and capture output
run_cmd_capture() {
    local output_file="$1"
    shift
    "$@" > "$output_file" 2>&1
    return $?
}

# Show output on failure
show_failure() {
    local label="$1"
    local output_file="$2"
    echo "  $label FAILED" >&2
    echo "  ----------------------------------------" >&2
    tail -80 "$output_file" >&2
    echo "  ----------------------------------------" >&2
}

# Function to run checks for a project
run_checks() {
    local project_path="$1"
    local full_path="$REPO_ROOT/$project_path"
    local failed=0

    echo "Checking $project_path..." >&2
    cd "$full_path"

    # Frontend/Node.js project (package.json)
    if [ -f "package.json" ]; then
        echo "  [Frontend] Running checks..." >&2

        local has_lint=false
        local has_typecheck=false
        local has_test=false

        grep -q '"lint"' package.json && has_lint=true
        grep -q '"typecheck"' package.json && has_typecheck=true
        grep -q '"test"' package.json && has_test=true

        # Run lint and typecheck in parallel
        local lint_pid=""
        local typecheck_pid=""

        if $has_lint; then
            echo "  Lint (parallel)..." >&2
            run_cmd_capture "$LINT_OUTPUT" pnpm lint &
            lint_pid=$!
        fi

        if $has_typecheck; then
            echo "  Typecheck (parallel)..." >&2
            run_cmd_capture "$TYPECHECK_OUTPUT" pnpm typecheck &
            typecheck_pid=$!
        fi

        # Wait for parallel tasks and check results
        if [ -n "$lint_pid" ]; then
            if ! wait $lint_pid; then
                show_failure "Lint" "$LINT_OUTPUT"
                failed=1
            fi
        fi

        if [ -n "$typecheck_pid" ]; then
            if ! wait $typecheck_pid; then
                show_failure "Typecheck" "$TYPECHECK_OUTPUT"
                failed=1
            fi
        fi

        # Exit early if lint or typecheck failed
        if [ $failed -eq 1 ]; then
            return 1
        fi

        echo "  Lint & Typecheck passed!" >&2

        # Run tests sequentially (they may depend on build output)
        if $has_test; then
            echo "  Test..." >&2
            local test_output
            if ! test_output=$(pnpm test --run 2>&1); then
                if ! test_output=$(pnpm test 2>&1); then
                    echo "  Test FAILED" >&2
                    echo "  ----------------------------------------" >&2
                    echo "$test_output" | tail -80 >&2
                    echo "  ----------------------------------------" >&2
                    return 1
                fi
            fi
        fi

    # Go project (go.mod + Makefile)
    elif [ -f "go.mod" ] && [ -f "Makefile" ]; then
        echo "  [Go] Running make checks..." >&2

        # Go: lint and test can run in parallel
        local lint_pid=""
        local has_lint=false
        local has_test=false

        grep -q '^lint:' Makefile && has_lint=true
        grep -q '^test:' Makefile && has_test=true

        if $has_lint; then
            echo "  Lint (parallel)..." >&2
            run_cmd_capture "$LINT_OUTPUT" make lint &
            lint_pid=$!
        fi

        if $has_test; then
            echo "  Test (parallel)..." >&2
            run_cmd_capture "$TYPECHECK_OUTPUT" make test &
            test_pid=$!
        fi

        if [ -n "$lint_pid" ]; then
            if ! wait $lint_pid; then
                show_failure "Lint" "$LINT_OUTPUT"
                failed=1
            fi
        fi

        if [ -n "$test_pid" ]; then
            if ! wait $test_pid; then
                show_failure "Test" "$TYPECHECK_OUTPUT"
                failed=1
            fi
        fi

        if [ $failed -eq 1 ]; then
            return 1
        fi

    # Java/Gradle project (build.gradle)
    elif [ -f "build.gradle" ] || [ -f "settings.gradle" ]; then
        echo "  [Java] Running gradle checks..." >&2

        if [ -f "gradlew" ]; then
            local output
            echo "  Gradle check..." >&2
            if ! output=$(./gradlew check 2>&1); then
                echo "  Gradle check FAILED" >&2
                echo "  ----------------------------------------" >&2
                echo "$output" | tail -80 >&2
                echo "  ----------------------------------------" >&2
                return 1
            fi
        else
            echo "  No gradlew found, skipping" >&2
            return 0
        fi

    # Python project (pyproject.toml + Makefile)
    elif [ -f "pyproject.toml" ] && [ -f "Makefile" ]; then
        echo "  [Python] Running make checks..." >&2

        local lint_pid=""
        local has_lint=false
        local has_test=false

        grep -q '^lint:' Makefile && has_lint=true
        grep -q '^test:' Makefile && has_test=true

        if $has_lint; then
            echo "  Lint (parallel)..." >&2
            run_cmd_capture "$LINT_OUTPUT" make lint &
            lint_pid=$!
        fi

        if $has_test; then
            echo "  Test (parallel)..." >&2
            run_cmd_capture "$TYPECHECK_OUTPUT" make test &
            test_pid=$!
        fi

        if [ -n "$lint_pid" ]; then
            if ! wait $lint_pid; then
                show_failure "Lint" "$LINT_OUTPUT"
                failed=1
            fi
        fi

        if [ -n "$test_pid" ]; then
            if ! wait $test_pid; then
                show_failure "Test" "$TYPECHECK_OUTPUT"
                failed=1
            fi
        fi

        if [ $failed -eq 1 ]; then
            return 1
        fi

    else
        echo "  Unknown project type, skipping" >&2
        return 0
    fi

    echo "  Checks passed!" >&2
    return 0
}

# Run checks for current project only
if ! run_checks "$CURRENT_PROJECT"; then
    echo "" >&2
    echo "Pre-push checks failed. Fix errors before pushing." >&2
    exit 2  # Exit 2 blocks the action in Claude Code
fi

cd "$REPO_ROOT"

echo "" >&2
echo "All pre-push checks passed!" >&2
exit 0
