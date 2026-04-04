//go:build linux || darwin

package transport

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/anthropics/ai-config/tools/party-cli/internal/state"
	"github.com/anthropics/ai-config/tools/party-cli/internal/tmux"
)

// Service provides the Claude ↔ Codex transport layer.
type Service struct {
	store    *state.Store
	client   *tmux.Client
	repoRoot string // root of the ai-config repo (for template resolution)
}

// NewService creates a transport service.
func NewService(store *state.Store, client *tmux.Client, repoRoot string) *Service {
	return &Service{store: store, client: client, repoRoot: repoRoot}
}

// ReviewOpts configures a --review dispatch.
type ReviewOpts struct {
	WorkDir       string
	Base          string // default: "main"
	Title         string // default: "Code review"
	Scope         string // optional: restrict review to this scope
	DisputeFile   string // optional: path to dismissed findings
	PriorFindings string // optional: path to prior findings for re-review
}

// ReviewResult contains the output of a review dispatch.
type ReviewResult struct {
	Dispatched   bool   // true if message was sent to Codex
	FindingsFile string // path where Codex will write findings
}

// Review dispatches a code review to the Wizard (Codex).
func (s *Service) Review(ctx context.Context, opts ReviewOpts) (ReviewResult, error) {
	_, runtimeDir, codexPane, err := s.resolveCodexContext(ctx)
	if err != nil {
		return ReviewResult{}, err
	}

	if opts.Base == "" {
		opts.Base = "main"
	}
	if opts.Title == "" {
		opts.Title = "Code review"
	}

	findingsFile := filepath.Join(runtimeDir, fmt.Sprintf("codex-findings-%d.toon", time.Now().UnixNano()))
	notifyScript := s.notifyScriptPath()
	notifyCmd := fmt.Sprintf("%s \"Review complete. Findings at: %s\"", notifyScript, findingsFile)

	vars := map[string]string{
		"WORK_DIR":      opts.WorkDir,
		"BASE":          opts.Base,
		"TITLE":         opts.Title,
		"FINDINGS_FILE": findingsFile,
		"NOTIFY_CMD":    notifyCmd,
	}

	// Build conditional sections.
	if opts.Scope != "" {
		vars["SCOPE_SECTION"] = fmt.Sprintf("## Scope\n\nOnly review changes within this scope: %s\nFindings outside this scope should be classified as out-of-scope and omitted.", opts.Scope)
	} else {
		vars["SCOPE_SECTION"] = ""
	}
	if opts.DisputeFile != "" && fileExists(opts.DisputeFile) {
		vars["DISPUTE_SECTION"] = fmt.Sprintf("## Dispute Context\n\nRead dismissed findings and rationales from: %s\nFor each dismissed finding: accept if the rationale is valid (drop from findings), or challenge with a specific file:line reference if invalid. Do NOT re-raise accepted dismissals.", opts.DisputeFile)
	} else {
		vars["DISPUTE_SECTION"] = ""
	}
	if opts.PriorFindings != "" && fileExists(opts.PriorFindings) {
		vars["REREVEW_SECTION"] = fmt.Sprintf("## Re-review\n\nThis is a re-review. Prior findings at: %s\nFocus on whether blocking issues were addressed. Do NOT re-raise findings that were already fixed. Flag only genuinely NEW issues.", opts.PriorFindings)
	} else {
		vars["REREVEW_SECTION"] = ""
	}

	templatePath := s.templatePath("review.md")
	msg, err := RenderTemplate(templatePath, vars)
	if err != nil {
		return ReviewResult{FindingsFile: findingsFile}, fmt.Errorf("render review template: %w", err)
	}

	if err := s.sendWithStatusUpdate(ctx, codexPane, msg, runtimeDir, "review", opts.Base); err != nil {
		return ReviewResult{FindingsFile: findingsFile}, err
	}
	return ReviewResult{Dispatched: true, FindingsFile: findingsFile}, nil
}

// PlanReviewOpts configures a --plan-review dispatch.
type PlanReviewOpts struct {
	PlanPath string
	WorkDir  string
}

// PlanReviewResult contains the output of a plan review dispatch.
type PlanReviewResult struct {
	Dispatched   bool
	FindingsFile string
}

// PlanReview dispatches a plan review to the Wizard.
func (s *Service) PlanReview(ctx context.Context, opts PlanReviewOpts) (PlanReviewResult, error) {
	_, runtimeDir, codexPane, err := s.resolveCodexContext(ctx)
	if err != nil {
		return PlanReviewResult{}, err
	}

	findingsFile := filepath.Join(runtimeDir, fmt.Sprintf("codex-plan-findings-%d.toon", time.Now().UnixNano()))
	notifyScript := s.notifyScriptPath()
	notifyCmd := fmt.Sprintf("%s \"Plan review complete. Findings at: %s\"", notifyScript, findingsFile)

	templatePath := s.templatePath("plan-review.md")
	msg, err := RenderTemplate(templatePath, map[string]string{
		"WORK_DIR":      opts.WorkDir,
		"PLAN_PATH":     opts.PlanPath,
		"FINDINGS_FILE": findingsFile,
		"NOTIFY_CMD":    notifyCmd,
	})
	if err != nil {
		return PlanReviewResult{FindingsFile: findingsFile}, fmt.Errorf("render plan-review template: %w", err)
	}

	if err := s.sendWithStatusUpdate(ctx, codexPane, msg, runtimeDir, "plan-review", opts.PlanPath); err != nil {
		return PlanReviewResult{FindingsFile: findingsFile}, err
	}
	return PlanReviewResult{Dispatched: true, FindingsFile: findingsFile}, nil
}

// PromptOpts configures a --prompt dispatch.
type PromptOpts struct {
	Text    string
	WorkDir string
}

// PromptResult contains the output of a prompt dispatch.
type PromptResult struct {
	Dispatched   bool
	ResponseFile string
}

// Prompt dispatches a freeform task to the Wizard.
func (s *Service) Prompt(ctx context.Context, opts PromptOpts) (PromptResult, error) {
	_, runtimeDir, codexPane, err := s.resolveCodexContext(ctx)
	if err != nil {
		return PromptResult{}, err
	}

	responseFile := filepath.Join(runtimeDir, fmt.Sprintf("codex-response-%d.toon", time.Now().UnixNano()))
	notifyScript := s.notifyScriptPath()

	msg := fmt.Sprintf("[CLAUDE] cd '%s' && %s — Write response to: %s — When done, run: %s \"Task complete. Response at: %s\"",
		opts.WorkDir, opts.Text, responseFile, notifyScript, responseFile)

	if err := s.sendWithStatusUpdate(ctx, codexPane, msg, runtimeDir, "prompt", opts.Text); err != nil {
		return PromptResult{ResponseFile: responseFile}, err
	}
	return PromptResult{Dispatched: true, ResponseFile: responseFile}, nil
}

// ReviewCompleteResult contains the parsed verdict from a findings file.
type ReviewCompleteResult struct {
	ReviewRan bool
	Verdict   string // "APPROVED", "REQUEST_CHANGES", or "" if missing
}

// ReviewComplete reads a findings file and parses the verdict. Does not require a party session.
func ReviewComplete(findingsFile string) (ReviewCompleteResult, error) {
	if _, err := os.Stat(findingsFile); err != nil {
		return ReviewCompleteResult{}, fmt.Errorf("findings file not accessible: %w", err)
	}

	verdict := parseVerdict(findingsFile)
	return ReviewCompleteResult{ReviewRan: true, Verdict: verdict}, nil
}

// NeedsDiscussion returns the sentinel string for discussion escalation.
func NeedsDiscussion(reason string) string {
	if reason == "" {
		reason = "Multiple valid approaches or unresolvable findings"
	}
	return fmt.Sprintf("CODEX NEEDS_DISCUSSION — %s", reason)
}

// TriageOverride returns the sentinel string for triage overrides.
func TriageOverride(overrideType, rationale string) string {
	return fmt.Sprintf("TRIAGE_OVERRIDE %s | %s", overrideType, rationale)
}

// NotifyOpts configures a Codex → Claude notification.
type NotifyOpts struct {
	Message string
}

// NotifyResult contains the outcome of a notification.
type NotifyResult struct {
	Delivered bool
	Status    string // "CLAUDE_MESSAGE_SENT" or "CLAUDE_MESSAGE_DROPPED"
}

// Notify sends a message from Codex to Claude's pane.
// Also persists Codex's thread ID on first call.
func (s *Service) Notify(ctx context.Context, opts NotifyOpts) (NotifyResult, error) {
	session, err := s.discoverSession(ctx)
	if err != nil {
		return NotifyResult{}, err
	}

	runtimeDir := runtimeDirForSession(session)

	// Register Codex's thread ID with the party session (write-once).
	s.registerCodexThreadID(ctx, session, runtimeDir)

	claudePane, err := s.client.ResolveRole(ctx, session, "claude", tmux.WindowWorkspace)
	if err != nil {
		return NotifyResult{}, fmt.Errorf("resolve claude pane in %q: %w", session, err)
	}

	// Detect completion messages by prefix.
	isCompletion := isCompletionMessage(opts.Message)

	result := s.client.Send(ctx, claudePane, "[CODEX] "+opts.Message)
	if result.Err != nil {
		if isCompletion {
			_ = WriteCodexStatus(runtimeDir, CodexStatus{
				State: "error",
				Error: "completion delivery failed: Claude pane busy",
			})
		}
		return NotifyResult{Status: "CLAUDE_MESSAGE_DROPPED"}, nil
	}

	if isCompletion {
		verdict := ""
		findingsFile := extractFilePath(opts.Message)
		if findingsFile != "" && fileExists(findingsFile) {
			verdict = parseVerdict(findingsFile)
		}
		_ = WriteCodexStatus(runtimeDir, CodexStatus{
			State:   "idle",
			Verdict: verdict,
		})
	}

	return NotifyResult{Delivered: true, Status: "CLAUDE_MESSAGE_SENT"}, nil
}

// resolveCodexContext discovers the session, validates it's not a master,
// and resolves the Codex pane target.
func (s *Service) resolveCodexContext(ctx context.Context) (session, runtimeDir, codexPane string, err error) {
	session, err = s.discoverSession(ctx)
	if err != nil {
		return "", "", "", err
	}

	// Master sessions have no Codex pane.
	m, err := s.store.Read(session)
	if err != nil {
		return "", "", "", fmt.Errorf("read manifest for %q: %w", session, err)
	}
	if m.SessionType == "master" {
		return "", "", "", fmt.Errorf("CODEX_NOT_AVAILABLE: Master sessions have no Wizard pane. Route review work through a worker session")
	}

	runtimeDir = runtimeDirForSession(session)

	// Resolve Codex pane: sidebar mode → window 0, classic → role-based.
	// Check process env first (inherited from tmux), then tmux session env as fallback.
	layout := os.Getenv("PARTY_LAYOUT")
	if layout == "" {
		layout, _, _ = s.client.ShowEnvironment(ctx, session, "PARTY_LAYOUT")
	}
	if layout == "sidebar" {
		codexPane = fmt.Sprintf("%s:0.0", session)
	} else {
		codexPane, err = s.client.ResolveRole(ctx, session, "codex", -1)
		if err != nil {
			return "", "", "", fmt.Errorf("resolve codex pane in %q: %w", session, err)
		}
	}

	return session, runtimeDir, codexPane, nil
}

// sendWithStatusUpdate sends a message to the Codex pane and updates status accordingly.
func (s *Service) sendWithStatusUpdate(ctx context.Context, codexPane, msg, runtimeDir, mode, target string) error {
	result := s.client.Send(ctx, codexPane, msg)
	if result.Err != nil {
		_ = WriteCodexStatus(runtimeDir, CodexStatus{
			State: "error",
			Error: fmt.Sprintf("%s dispatch failed: pane busy", mode),
		})
		return fmt.Errorf("CODEX_%s_DROPPED: Codex pane is busy. Message dropped", strings.ToUpper(strings.ReplaceAll(mode, "-", "_")))
	}

	_ = WriteCodexStatus(runtimeDir, CodexStatus{
		State:  "working",
		Target: target,
		Mode:   mode,
	})
	return nil
}

// discoverSession resolves the current party session.
func (s *Service) discoverSession(ctx context.Context) (string, error) {
	name := os.Getenv("PARTY_SESSION")
	if name == "" {
		var err error
		name, err = s.client.SessionName(ctx)
		if err != nil {
			return "", fmt.Errorf("discover session: %w", err)
		}
	}
	if !strings.HasPrefix(name, "party-") {
		return "", fmt.Errorf("current session %q is not a party session", name)
	}
	return name, nil
}

// registerCodexThreadID persists the Codex thread ID to the session (write-once).
func (s *Service) registerCodexThreadID(ctx context.Context, session, runtimeDir string) {
	threadID := os.Getenv("CODEX_THREAD_ID")
	if threadID == "" {
		return
	}

	idFile := filepath.Join(runtimeDir, "codex-thread-id")
	if data, err := os.ReadFile(idFile); err == nil && strings.TrimSpace(string(data)) != "" {
		return // already registered
	}

	_ = os.MkdirAll(runtimeDir, 0o755)
	_ = os.WriteFile(idFile, []byte(threadID+"\n"), 0o644)
	_ = s.client.SetEnvironment(ctx, session, "CODEX_THREAD_ID", threadID)

	// Persist to manifest for resume path.
	_ = s.store.Update(session, func(m *state.Manifest) {
		m.SetExtra("codex_thread_id", threadID)
	})
}

// templatePath resolves a template file path relative to the repo root.
func (s *Service) templatePath(name string) string {
	return filepath.Join(s.repoRoot, "claude", "skills", "codex-transport", "templates", name)
}

// notifyScriptPath returns the path to the notify command.
// Returns the party-cli notify command for embedding in dispatch messages.
func (s *Service) notifyScriptPath() string {
	return "party-cli notify"
}

// runtimeDirForSession returns the runtime directory for a session.
func runtimeDirForSession(session string) string {
	return filepath.Join(os.TempDir(), session)
}

// parseVerdict reads a findings/response file and extracts the verdict line.
func parseVerdict(path string) string {
	f, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		switch {
		case line == "VERDICT: APPROVED":
			return "APPROVED"
		case line == "VERDICT: REQUEST_CHANGES":
			return "REQUEST_CHANGES"
		case line == "VERDICT: NEEDS_DISCUSSION":
			return "NEEDS_DISCUSSION"
		}
	}
	return ""
}

// isCompletionMessage checks if a message matches known completion prefixes.
func isCompletionMessage(msg string) bool {
	return strings.HasPrefix(msg, "Review complete. Findings at: ") ||
		strings.HasPrefix(msg, "Plan review complete. Findings at: ") ||
		strings.HasPrefix(msg, "Task complete. Response at: ")
}

// extractFilePath pulls the file path from a completion message.
func extractFilePath(msg string) string {
	for _, prefix := range []string{
		"Review complete. Findings at: ",
		"Plan review complete. Findings at: ",
		"Task complete. Response at: ",
	} {
		if strings.HasPrefix(msg, prefix) {
			path := strings.TrimPrefix(msg, prefix)
			// Trim any trailing whitespace.
			return strings.TrimSpace(path)
		}
	}
	return ""
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}
