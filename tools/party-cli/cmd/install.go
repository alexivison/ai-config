package cmd

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"
)

func newInstallCmd(repoRoot string) *cobra.Command {
	var symlinksOnly bool

	cmd := &cobra.Command{
		Use:   "install",
		Short: "Install config symlinks and CLI tools",
		Long: `Create config symlinks and optionally install CLI tools.

Replaces install.sh with native Go implementation.
Creates symlinks for Claude, Codex, tmux, and nvim configurations.`,
		RunE: func(cmd *cobra.Command, _ []string) error {
			root := resolveRepoRoot(repoRoot)
			if root == "" {
				return fmt.Errorf("cannot determine repo root: set PARTY_REPO_ROOT or run from the repo")
			}

			w := cmd.OutOrStdout()
			r := bufio.NewReader(os.Stdin)

			fmt.Fprintln(w, "party-cli installer")
			fmt.Fprintln(w, "===================")
			fmt.Fprintf(w, "Repo location: %s\n\n", root)

			if symlinksOnly {
				fmt.Fprintln(w, "This installer will:")
				fmt.Fprintln(w, "  1. Create config symlinks")
				fmt.Fprintln(w, "\n(CLI installation skipped with --symlinks-only)")
			} else {
				fmt.Fprintln(w, "This installer will:")
				fmt.Fprintln(w, "  1. Create config symlinks")
				fmt.Fprintln(w, "  2. Install CLI tools (optional)")
				fmt.Fprintln(w, "  3. Set up authentication (optional)")
			}

			fmt.Fprintf(w, "\nContinue? [Y/n] ")
			line, _ := r.ReadString('\n')
			if strings.TrimSpace(strings.ToLower(line)) == "n" {
				fmt.Fprintln(w, "Installation cancelled.")
				return nil
			}

			home := os.Getenv("HOME")
			if home == "" {
				return fmt.Errorf("HOME environment variable is not set")
			}

			// Claude config
			fmt.Fprintln(w, "\n━━━ claude ━━━")
			createDirSymlink(w, filepath.Join(root, "claude"), filepath.Join(home, ".claude"))
			if !symlinksOnly {
				installCLIIfMissing(w, r, "claude", "curl -fsSL https://cli.anthropic.com/install.sh | sh", "curl installer (cli.anthropic.com)")
			}

			// Codex config
			fmt.Fprintln(w, "\n━━━ codex ━━━")
			createDirSymlink(w, filepath.Join(root, "codex"), filepath.Join(home, ".codex"))
			if !symlinksOnly {
				installCLIIfMissing(w, r, "codex", "brew install --cask codex", "brew install --cask codex")
			}

			// tmux config
			fmt.Fprintln(w, "\n━━━ tmux ━━━")
			createFileSymlink(w, filepath.Join(root, "tmux", "tmux.conf"), filepath.Join(home, ".tmux.conf"), "tmux config")

			// nvim config
			fmt.Fprintln(w, "\n━━━ nvim ━━━")
			nvimSource := filepath.Join(root, "nvim")
			xdgConfig := os.Getenv("XDG_CONFIG_HOME")
			if xdgConfig == "" {
				xdgConfig = filepath.Join(home, ".config")
			}
			nvimTarget := filepath.Join(xdgConfig, "nvim")
			if _, err := os.Stat(nvimSource); err == nil {
				os.MkdirAll(filepath.Dir(nvimTarget), 0o755)
				createDirSymlink(w, nvimSource, nvimTarget)
			}

			// fzf
			if !symlinksOnly {
				fmt.Fprintln(w, "\n━━━ fzf ━━━")
				if _, err := exec.LookPath("fzf"); err == nil {
					fmt.Fprintln(w, "✓  fzf already installed")
				} else {
					installCLIIfMissing(w, r, "fzf", "brew install fzf", "brew install fzf")
				}
			}

			// Summary
			fmt.Fprintln(w, "\n━━━━━━━━━━━━━━━━━━━━")
			fmt.Fprintln(w, "Installation complete!")
			fmt.Fprintln(w, "\nInstalled symlinks:")
			for _, tool := range []string{"claude", "codex"} {
				target := filepath.Join(home, "."+tool)
				if dest, err := os.Readlink(target); err == nil {
					fmt.Fprintf(w, "  ~/.%s → %s\n", tool, dest)
				}
			}
			tmuxTarget := filepath.Join(home, ".tmux.conf")
			if dest, err := os.Readlink(tmuxTarget); err == nil {
				fmt.Fprintf(w, "  ~/.tmux.conf → %s\n", dest)
			}
			if dest, err := os.Readlink(nvimTarget); err == nil {
				fmt.Fprintf(w, "  %s → %s\n", nvimTarget, dest)
			}

			return nil
		},
	}

	cmd.Flags().BoolVar(&symlinksOnly, "symlinks-only", false, "only create config symlinks, skip CLI installation")
	return cmd
}

func newUninstallCmd(repoRoot string) *cobra.Command {
	return &cobra.Command{
		Use:   "uninstall",
		Short: "Remove config symlinks created by install",
		Long:  `Removes symlinks created by 'party-cli install'. Does not remove the repo.`,
		RunE: func(cmd *cobra.Command, _ []string) error {
			root := resolveRepoRoot(repoRoot)
			if root == "" {
				return fmt.Errorf("cannot determine repo root: set PARTY_REPO_ROOT or run from the repo")
			}

			w := cmd.OutOrStdout()
			home := os.Getenv("HOME")
			if home == "" {
				return fmt.Errorf("HOME environment variable is not set")
			}

			fmt.Fprintln(w, "party-cli uninstaller")
			fmt.Fprintln(w, "=====================")
			fmt.Fprintln(w)
			fmt.Fprintln(w, "Removing symlinks...")

			for _, tool := range []string{"claude", "codex"} {
				removeDirSymlink(w, filepath.Join(root, tool), filepath.Join(home, "."+tool))
			}
			removeFileSymlink(w, filepath.Join(root, "tmux", "tmux.conf"), filepath.Join(home, ".tmux.conf"), "~/.tmux.conf")

			// nvim config
			nvimSource := filepath.Join(root, "nvim")
			xdgConfig := os.Getenv("XDG_CONFIG_HOME")
			if xdgConfig == "" {
				xdgConfig = filepath.Join(home, ".config")
			}
			nvimTarget := filepath.Join(xdgConfig, "nvim")
			removeDirSymlink(w, nvimSource, nvimTarget)

			fmt.Fprintln(w, "\nUninstall complete!")
			fmt.Fprintf(w, "The repo remains at: %s\n", root)
			return nil
		},
	}
}

// resolveRepoRoot determines the repo root from the provided value,
// PARTY_REPO_ROOT env var, or by walking up from the executable.
func resolveRepoRoot(provided string) string {
	if provided != "" {
		return provided
	}
	if env := os.Getenv("PARTY_REPO_ROOT"); env != "" {
		return env
	}
	// Try to find the repo by walking up from executable location or CWD.
	// Look for the claude/ directory as a repo marker (install.sh was removed
	// during CLI-ification).
	for _, start := range []func() (string, error){os.Executable, os.Getwd} {
		base, err := start()
		if err != nil {
			continue
		}
		dir := base
		// os.Executable returns a file path; start from its directory.
		if fi, err := os.Stat(dir); err != nil || !fi.IsDir() {
			dir = filepath.Dir(dir)
		}
		for i := 0; i < 5; i++ {
			if _, err := os.Stat(filepath.Join(dir, "claude")); err == nil {
				if _, err := os.Stat(filepath.Join(dir, "tools", "party-cli")); err == nil {
					return dir
				}
			}
			dir = filepath.Dir(dir)
		}
	}
	return ""
}

func createDirSymlink(w io.Writer, source, target string) {
	if _, err := os.Stat(source); err != nil {
		fmt.Fprintf(w, "⏭  Skipping %s (source not found)\n", filepath.Base(source))
		return
	}

	// Already correct?
	if dest, err := os.Readlink(target); err == nil && dest == source {
		fmt.Fprintf(w, "✓  %s config already linked\n", filepath.Base(source))
		return
	}

	backupExisting(w, target)
	if err := os.Symlink(source, target); err != nil {
		fmt.Fprintf(w, "✗  Failed to create symlink: %v\n", err)
		return
	}
	fmt.Fprintf(w, "✓  Created symlink: %s → %s\n", target, source)
}

func createFileSymlink(w io.Writer, source, target, label string) {
	if _, err := os.Stat(source); err != nil {
		fmt.Fprintf(w, "⏭  Skipping %s (source not found)\n", label)
		return
	}

	if dest, err := os.Readlink(target); err == nil && dest == source {
		fmt.Fprintf(w, "✓  %s already linked\n", label)
		return
	}

	backupExisting(w, target)
	if err := os.Symlink(source, target); err != nil {
		fmt.Fprintf(w, "✗  Failed to create symlink: %v\n", err)
		return
	}
	fmt.Fprintf(w, "✓  Created symlink: %s → %s\n", target, source)
}

func removeDirSymlink(w io.Writer, source, target string) {
	fi, err := os.Lstat(target)
	if err != nil || fi.Mode()&os.ModeSymlink == 0 {
		fmt.Fprintf(w, "⏭  Skipping %s (not a symlink)\n", target)
		return
	}
	dest, err := os.Readlink(target)
	if err != nil || dest != source {
		fmt.Fprintf(w, "⏭  Skipping %s (points elsewhere: %s)\n", target, dest)
		return
	}
	os.Remove(target)
	fmt.Fprintf(w, "✓  Removed symlink: %s\n", target)
}

func removeFileSymlink(w io.Writer, source, target, label string) {
	fi, err := os.Lstat(target)
	if err != nil || fi.Mode()&os.ModeSymlink == 0 {
		fmt.Fprintf(w, "⏭  Skipping %s (not a symlink)\n", label)
		return
	}
	dest, err := os.Readlink(target)
	if err != nil || dest != source {
		fmt.Fprintf(w, "⏭  Skipping %s (points elsewhere: %s)\n", label, dest)
		return
	}
	os.Remove(target)
	fmt.Fprintf(w, "✓  Removed symlink: %s\n", label)
}

func backupExisting(w io.Writer, target string) {
	fi, err := os.Lstat(target)
	if err != nil {
		return // doesn't exist
	}
	if fi.Mode()&os.ModeSymlink != 0 {
		fmt.Fprintf(w, "  Removing existing symlink: %s\n", target)
		if err := os.Remove(target); err != nil {
			fmt.Fprintf(w, "  ✗  Failed to remove symlink: %v\n", err)
		}
		return
	}
	if fi.IsDir() || fi.Mode().IsRegular() {
		backup := target + ".backup"
		// Avoid clobbering an existing backup
		if _, err := os.Lstat(backup); err == nil {
			backup = fmt.Sprintf("%s.backup.%d", target, os.Getpid())
		}
		fmt.Fprintf(w, "  Backing up: %s → %s\n", target, backup)
		if err := os.Rename(target, backup); err != nil {
			fmt.Fprintf(w, "  ✗  Failed to back up: %v\n", err)
		}
	}
}

func installCLIIfMissing(w io.Writer, r *bufio.Reader, name, installCmd, desc string) {
	if _, err := exec.LookPath(name); err == nil {
		fmt.Fprintf(w, "✓  %s CLI already installed\n", name)
		return
	}
	fmt.Fprintf(w, "📦 %s CLI not found.\n", name)
	fmt.Fprintf(w, "   Install via: %s\n", desc)
	fmt.Fprintf(w, "   Run install? [y/N] ")
	line, _ := r.ReadString('\n')
	if strings.TrimSpace(strings.ToLower(line)) == "y" {
		fmt.Fprintln(w, "   Installing...")
		c := exec.Command("sh", "-c", installCmd)
		c.Stdout = w
		c.Stderr = os.Stderr
		if err := c.Run(); err != nil {
			fmt.Fprintf(w, "✗  Installation failed: %v\n", err)
			return
		}
		fmt.Fprintf(w, "✓  %s CLI installed\n", name)
	} else {
		fmt.Fprintf(w, "⏭  Skipping %s CLI installation\n", name)
	}
}
