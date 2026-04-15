//go:build linux || darwin

package cmd

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/anthropics/ai-party/tools/party-cli/internal/tui"
)

func TestAgentQuery_DefaultConfig(t *testing.T) {
	cwd := t.TempDir()

	if got := runAgentQuery(t, cwd, "agent", "query", "roles"); got != "primary\ncompanion\n" {
		t.Fatalf("roles = %q, want %q", got, "primary\ncompanion\n")
	}
	if got := runAgentQuery(t, cwd, "agent", "query", "names"); got != "claude\ncodex\n" {
		t.Fatalf("names = %q, want %q", got, "claude\ncodex\n")
	}
	if got := runAgentQuery(t, cwd, "agent", "query", "primary-name"); got != "claude\n" {
		t.Fatalf("primary-name = %q, want %q", got, "claude\n")
	}
	if got := runAgentQuery(t, cwd, "agent", "query", "evidence-required"); got != "pr-verified\ncode-critic\nminimizer\ncodex\ntest-runner\ncheck-runner\n" {
		t.Fatalf("evidence-required = %q", got)
	}
}

func TestAgentQuery_NoCompanion(t *testing.T) {
	cwd := t.TempDir()
	if err := os.Mkdir(filepath.Join(cwd, ".git"), 0o755); err != nil {
		t.Fatalf("mkdir .git: %v", err)
	}
	if err := os.WriteFile(filepath.Join(cwd, ".party.toml"), []byte("[roles.primary]\nagent = \"claude\"\n"), 0o644); err != nil {
		t.Fatalf("write .party.toml: %v", err)
	}

	if got := runAgentQuery(t, cwd, "agent", "query", "companion-name"); got != "" {
		t.Fatalf("companion-name = %q, want empty", got)
	}
	if got := runAgentQuery(t, cwd, "agent", "query", "evidence-required"); strings.Contains(got, "codex\n") {
		t.Fatalf("evidence-required should omit companion evidence, got %q", got)
	}
}

func runAgentQuery(t *testing.T, cwd string, args ...string) string {
	t.Helper()

	previous, err := os.Getwd()
	if err != nil {
		t.Fatalf("Getwd: %v", err)
	}
	if err := os.Chdir(cwd); err != nil {
		t.Fatalf("Chdir(%s): %v", cwd, err)
	}
	defer func() {
		if chdirErr := os.Chdir(previous); chdirErr != nil {
			t.Fatalf("restore cwd: %v", chdirErr)
		}
	}()

	root := NewRootCmd(WithTUILauncher(func(...tui.Option) error { return nil }))
	var out bytes.Buffer
	root.SetOut(&out)
	root.SetErr(&bytes.Buffer{})
	root.SetArgs(args)
	if err := root.Execute(); err != nil {
		t.Fatalf("Execute(%v): %v", args, err)
	}
	return out.String()
}
