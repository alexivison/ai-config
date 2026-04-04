package cmd

import (
	"fmt"

	"github.com/anthropics/ai-config/tools/party-cli/internal/state"
	"github.com/anthropics/ai-config/tools/party-cli/internal/tmux"
	"github.com/anthropics/ai-config/tools/party-cli/internal/transport"
	"github.com/spf13/cobra"
)

func newNotifyCmd(store *state.Store, client *tmux.Client, repoRoot string) *cobra.Command {
	return &cobra.Command{
		Use:   "notify <message>",
		Short: "Send a message from Codex to Claude's pane",
		Long: `Send a notification from the Wizard (Codex) to Claude (The Paladin).

Automatically detects completion messages and updates Codex status.`,
		Args: cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			svc := transport.NewService(store, client, repoRoot)
			result, err := svc.Notify(cmd.Context(), transport.NotifyOpts{
				Message: args[0],
			})
			if err != nil {
				return err
			}

			w := cmd.OutOrStdout()
			fmt.Fprintln(w, result.Status)
			if !result.Delivered {
				fmt.Fprintln(cmd.ErrOrStderr(), "tmux_send: delivery failed — Claude pane busy or unreachable")
			}
			return nil
		},
	}
}
