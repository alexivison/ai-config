package cmd

import (
	"fmt"

	"github.com/anthropics/ai-config/tools/party-cli/internal/state"
	"github.com/anthropics/ai-config/tools/party-cli/internal/tmux"
	"github.com/anthropics/ai-config/tools/party-cli/internal/transport"
	"github.com/spf13/cobra"
)

func newTransportCmd(store *state.Store, client *tmux.Client, repoRoot string) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "transport",
		Short: "Claude ↔ Codex transport layer",
		Long: `Transport commands for communicating between Claude (The Paladin)
and Codex (The Wizard) via tmux.`,
	}

	cmd.AddCommand(newTransportReviewCmd(store, client, repoRoot))
	cmd.AddCommand(newTransportPlanReviewCmd(store, client, repoRoot))
	cmd.AddCommand(newTransportPromptCmd(store, client, repoRoot))
	cmd.AddCommand(newTransportReviewCompleteCmd())
	cmd.AddCommand(newTransportNeedsDiscussionCmd())
	cmd.AddCommand(newTransportTriageOverrideCmd())

	return cmd
}

func newTransportReviewCmd(store *state.Store, client *tmux.Client, repoRoot string) *cobra.Command {
	var scope, disputeFile, priorFindings string

	cmd := &cobra.Command{
		Use:   "review <work_dir> [base_branch] [title]",
		Short: "Dispatch a code review to the Wizard",
		Long: `Request Codex to review changes on the current branch against a base branch.

Claude is NOT blocked — Codex will notify via tmux when complete.`,
		Args: cobra.RangeArgs(1, 3),
		RunE: func(cmd *cobra.Command, args []string) error {
			opts := transport.ReviewOpts{
				WorkDir:       args[0],
				Scope:         scope,
				DisputeFile:   disputeFile,
				PriorFindings: priorFindings,
			}
			if len(args) > 1 {
				opts.Base = args[1]
			}
			if len(args) > 2 {
				opts.Title = args[2]
			}

			svc := transport.NewService(store, client, repoRoot)
			result, err := svc.Review(cmd.Context(), opts)
			w := cmd.OutOrStdout()
			if err != nil {
				fmt.Fprintln(w, "CODEX_REVIEW_DROPPED")
				if result.FindingsFile != "" {
					fmt.Fprintf(w, "Findings will be written to: %s\n", result.FindingsFile)
				}
				return fmt.Errorf("review dispatch failed: %w", err)
			}

			fmt.Fprintln(w, "CODEX_REVIEW_REQUESTED")
			fmt.Fprintln(w, "Claude is NOT blocked. Codex will notify via tmux when complete.")
			fmt.Fprintf(w, "Findings will be written to: %s\n", result.FindingsFile)
			fmt.Fprintf(w, "Working directory: %s\n", opts.WorkDir)
			return nil
		},
	}

	cmd.Flags().StringVar(&scope, "scope", "", "restrict review to this scope")
	cmd.Flags().StringVar(&disputeFile, "dispute", "", "path to dismissed findings for dispute")
	cmd.Flags().StringVar(&priorFindings, "prior-findings", "", "path to prior findings for re-review")

	return cmd
}

func newTransportPlanReviewCmd(store *state.Store, client *tmux.Client, repoRoot string) *cobra.Command {
	return &cobra.Command{
		Use:   "plan-review <plan_path> <work_dir>",
		Short: "Dispatch a plan review to the Wizard",
		Args:  cobra.ExactArgs(2),
		RunE: func(cmd *cobra.Command, args []string) error {
			opts := transport.PlanReviewOpts{
				PlanPath: args[0],
				WorkDir:  args[1],
			}

			svc := transport.NewService(store, client, repoRoot)
			result, err := svc.PlanReview(cmd.Context(), opts)
			w := cmd.OutOrStdout()
			if err != nil {
				fmt.Fprintln(w, "CODEX_PLAN_REVIEW_DROPPED")
				return fmt.Errorf("plan-review dispatch failed: %w", err)
			}

			fmt.Fprintln(w, "CODEX_PLAN_REVIEW_REQUESTED")
			fmt.Fprintln(w, "Claude is NOT blocked. Codex will notify via tmux when complete.")
			fmt.Fprintf(w, "Findings will be written to: %s\n", result.FindingsFile)
			fmt.Fprintf(w, "Working directory: %s\n", opts.WorkDir)
			return nil
		},
	}
}

func newTransportPromptCmd(store *state.Store, client *tmux.Client, repoRoot string) *cobra.Command {
	return &cobra.Command{
		Use:   "prompt <text> <work_dir>",
		Short: "Dispatch a freeform task to the Wizard",
		Args:  cobra.ExactArgs(2),
		RunE: func(cmd *cobra.Command, args []string) error {
			opts := transport.PromptOpts{
				Text:    args[0],
				WorkDir: args[1],
			}

			svc := transport.NewService(store, client, repoRoot)
			result, err := svc.Prompt(cmd.Context(), opts)
			w := cmd.OutOrStdout()
			if err != nil {
				fmt.Fprintln(w, "CODEX_TASK_DROPPED")
				return fmt.Errorf("prompt dispatch failed: %w", err)
			}

			fmt.Fprintln(w, "CODEX_TASK_REQUESTED")
			fmt.Fprintln(w, "Codex will notify via tmux when complete.")
			fmt.Fprintf(w, "Response will be written to: %s\n", result.ResponseFile)
			fmt.Fprintf(w, "Working directory: %s\n", opts.WorkDir)
			return nil
		},
	}
}

func newTransportReviewCompleteCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "review-complete <findings_file>",
		Short: "Parse a completed review's findings and verdict",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			result, err := transport.ReviewComplete(args[0])
			if err != nil {
				return err
			}

			w := cmd.OutOrStdout()
			fmt.Fprintln(w, "CODEX_REVIEW_RAN")
			switch result.Verdict {
			case "APPROVED":
				fmt.Fprintln(w, "CODEX APPROVED")
			case "REQUEST_CHANGES":
				fmt.Fprintln(w, "CODEX REQUEST_CHANGES")
			default:
				fmt.Fprintln(cmd.ErrOrStderr(), "WARNING: No verdict line found in findings file. Review ran but no approval granted.")
				fmt.Fprintln(w, "CODEX VERDICT_MISSING")
			}
			return nil
		},
	}
}

func newTransportNeedsDiscussionCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "needs-discussion [reason]",
		Short: "Signal that findings require human discussion",
		Args:  cobra.MaximumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			reason := ""
			if len(args) > 0 {
				reason = args[0]
			}
			fmt.Fprintln(cmd.OutOrStdout(), transport.NeedsDiscussion(reason))
			return nil
		},
	}
}

func newTransportTriageOverrideCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "triage-override <type> <rationale>",
		Short: "Override a critic's verdict with rationale",
		Args:  cobra.ExactArgs(2),
		RunE: func(cmd *cobra.Command, args []string) error {
			fmt.Fprintln(cmd.OutOrStdout(), transport.TriageOverride(args[0], args[1]))
			return nil
		},
	}
}
