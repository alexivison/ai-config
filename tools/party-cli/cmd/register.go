package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/anthropics/ai-config/tools/party-cli/internal/state"
	"github.com/anthropics/ai-config/tools/party-cli/internal/tmux"
	"github.com/spf13/cobra"
)

func newRegisterCmd(store *state.Store, client *tmux.Client) *cobra.Command {
	var claudeSessionID string

	cmd := &cobra.Command{
		Use:   "register",
		Short: "Register agent IDs with the party session",
		Long: `Register Claude's session ID with the current party session.

Writes the session ID to the runtime directory and tmux environment,
and persists it to the manifest for the resume path.`,
		RunE: func(cmd *cobra.Command, _ []string) error {
			ctx := cmd.Context()

			if claudeSessionID == "" {
				return nil // nothing to register
			}

			// Discover session.
			name := os.Getenv("PARTY_SESSION")
			if name == "" {
				var err error
				name, err = client.SessionName(ctx)
				if err != nil {
					return nil // not in tmux — silently skip
				}
			}
			if !strings.HasPrefix(name, "party-") {
				return nil // not a party session — silently skip
			}

			runtimeDir := filepath.Join(os.TempDir(), name)
			if err := os.MkdirAll(runtimeDir, 0o755); err != nil {
				return nil // best-effort
			}

			// Write-once: skip if already registered with this ID.
			idFile := filepath.Join(runtimeDir, "claude-session-id")
			if data, err := os.ReadFile(idFile); err == nil && strings.TrimSpace(string(data)) == claudeSessionID {
				return nil
			}

			_ = os.WriteFile(idFile, []byte(claudeSessionID+"\n"), 0o644)
			_ = client.SetEnvironment(ctx, name, "CLAUDE_SESSION_ID", claudeSessionID)

			// Persist to manifest for resume path.
			_ = store.Update(name, func(m *state.Manifest) {
				m.SetExtra("claude_session_id", claudeSessionID)
			})

			fmt.Fprintf(cmd.OutOrStdout(), "{}\n")
			return nil
		},
	}

	cmd.Flags().StringVar(&claudeSessionID, "claude-session-id", "", "Claude session ID to register")

	return cmd
}
