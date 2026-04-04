//go:build linux || darwin

// Package transport provides the Claude ↔ Codex communication layer.
package transport

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

// CodexStatus represents the codex-status.json file written to the runtime directory.
type CodexStatus struct {
	State      string `json:"state"`
	Target     string `json:"target,omitempty"`
	Mode       string `json:"mode,omitempty"`
	Verdict    string `json:"verdict,omitempty"`
	Error      string `json:"error,omitempty"`
	StartedAt  string `json:"started_at,omitempty"`
	FinishedAt string `json:"finished_at,omitempty"`
}

// WriteCodexStatus atomically writes codex-status.json to the runtime directory.
// Builds JSON, writes to .tmp, then renames for atomicity.
func WriteCodexStatus(runtimeDir string, status CodexStatus) error {
	now := time.Now().UTC().Format("2006-01-02T15:04:05Z")
	if status.State == "working" {
		status.StartedAt = now
		status.FinishedAt = ""
	} else {
		status.StartedAt = ""
		status.FinishedAt = now
	}

	if err := os.MkdirAll(runtimeDir, 0o755); err != nil {
		return fmt.Errorf("create runtime dir: %w", err)
	}

	data, err := json.MarshalIndent(status, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal codex status: %w", err)
	}
	data = append(data, '\n')

	tmp := filepath.Join(runtimeDir, "codex-status.json.tmp")
	final := filepath.Join(runtimeDir, "codex-status.json")

	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return fmt.Errorf("write temp status: %w", err)
	}
	if err := os.Rename(tmp, final); err != nil {
		os.Remove(tmp)
		return fmt.Errorf("rename status: %w", err)
	}
	return nil
}
