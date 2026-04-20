package cmd

import (
	"time"

	"github.com/anthropics/ai-party/tools/party-cli/internal/session"
	"github.com/anthropics/ai-party/tools/party-cli/internal/state"
	"github.com/anthropics/ai-party/tools/party-cli/internal/tmux"
	"github.com/spf13/cobra"
)

func newBackfillResumeCmd(store *state.Store, client *tmux.Client, repoRoot string) *cobra.Command {
	var (
		attempts int
		interval time.Duration
	)

	cmd := &cobra.Command{
		Use:    "backfill-resume <session-id>",
		Short:  "Backfill missing agent resume metadata for a live session",
		Args:   cobra.ExactArgs(1),
		Hidden: true,
		RunE: func(cmd *cobra.Command, args []string) error {
			svc := session.NewService(store, client, repoRoot)
			return svc.BackfillMissingResumeIDs(cmd.Context(), args[0], attempts, interval)
		},
	}

	cmd.Flags().IntVar(&attempts, "attempts", 0, "maximum sync attempts before exiting")
	cmd.Flags().DurationVar(&interval, "interval", 0, "poll interval between sync attempts")
	return cmd
}
