package agent

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/BurntSushi/toml"
)

// Config is the parsed .party.toml configuration.
type Config struct {
	Agents   map[string]AgentConfig `toml:"agents"`
	Roles    RolesConfig            `toml:"roles"`
	Evidence EvidenceConfig         `toml:"evidence"`
}

// AgentConfig describes one configured agent provider.
type AgentConfig struct {
	CLI string `toml:"cli"`
}

// RolesConfig maps abstract roles to concrete agents.
type RolesConfig struct {
	Primary   *RoleConfig `toml:"primary"`
	Companion *RoleConfig `toml:"companion"`
}

// RoleConfig configures a single role binding.
type RoleConfig struct {
	Agent  string `toml:"agent"`
	Window int    `toml:"window"`
}

// EvidenceConfig controls PR-gate evidence requirements.
type EvidenceConfig struct {
	Required []string `toml:"required"`
}

// ConfigOverrides are per-session role overrides.
type ConfigOverrides struct {
	Primary     string
	Companion   string
	NoCompanion bool
}

// DefaultConfig returns the built-in Claude primary + Codex companion layout.
func DefaultConfig() *Config {
	return &Config{
		Agents: map[string]AgentConfig{
			"claude": {CLI: "claude"},
			"codex":  {CLI: "codex"},
		},
		Roles: RolesConfig{
			Primary:   &RoleConfig{Agent: "claude", Window: -1},
			Companion: &RoleConfig{Agent: "codex", Window: 0},
		},
	}
}

// LoadConfig resolves .party.toml from cwd up to the git root, then applies
// optional per-session role overrides.
func LoadConfig(cwd string, overrides *ConfigOverrides) (*Config, error) {
	if cwd == "" {
		var err error
		cwd, err = os.Getwd()
		if err != nil {
			return nil, fmt.Errorf("get working directory: %w", err)
		}
	}

	path, found, err := findConfigPath(cwd)
	if err != nil {
		return nil, err
	}

	var cfg *Config
	if !found {
		cfg = DefaultConfig()
	} else {
		cfg, err = loadConfigFile(path)
		if err != nil {
			return nil, err
		}
	}

	applyOverrides(cfg, overrides)
	hydrateReferencedAgents(cfg)
	return cfg, nil
}

func loadConfigFile(path string) (*Config, error) {
	var parsed Config
	meta, err := toml.DecodeFile(path, &parsed)
	if err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}

	cfg := &Config{
		Agents:   parsed.Agents,
		Evidence: parsed.Evidence,
	}
	if cfg.Agents == nil {
		cfg.Agents = make(map[string]AgentConfig)
	}

	defaults := DefaultConfig()
	hasRoles := meta.IsDefined("roles")
	hasPrimary := meta.IsDefined("roles", "primary")
	hasCompanion := meta.IsDefined("roles", "companion")

	if !hasRoles {
		cfg.Roles.Primary = cloneRoleConfig(defaults.Roles.Primary)
		cfg.Roles.Companion = cloneRoleConfig(defaults.Roles.Companion)
	} else {
		if hasPrimary {
			cfg.Roles.Primary = mergeRoleConfig(
				parsed.Roles.Primary,
				defaults.Roles.Primary,
				meta.IsDefined("roles", "primary", "agent"),
				meta.IsDefined("roles", "primary", "window"),
			)
		} else {
			cfg.Roles.Primary = cloneRoleConfig(defaults.Roles.Primary)
		}
		if hasCompanion {
			cfg.Roles.Companion = mergeRoleConfig(
				parsed.Roles.Companion,
				defaults.Roles.Companion,
				meta.IsDefined("roles", "companion", "agent"),
				meta.IsDefined("roles", "companion", "window"),
			)
		} else {
			cfg.Roles.Companion = nil
		}
	}

	return cfg, nil
}

func findConfigPath(cwd string) (string, bool, error) {
	current, err := filepath.Abs(cwd)
	if err != nil {
		return "", false, fmt.Errorf("resolve %s: %w", cwd, err)
	}

	for {
		path := filepath.Join(current, ".party.toml")
		if fi, err := os.Stat(path); err == nil && !fi.IsDir() {
			return path, true, nil
		} else if err != nil && !os.IsNotExist(err) {
			return "", false, fmt.Errorf("stat %s: %w", path, err)
		}

		gitPath := filepath.Join(current, ".git")
		if _, err := os.Stat(gitPath); err == nil {
			return "", false, nil
		} else if err != nil && !os.IsNotExist(err) {
			return "", false, fmt.Errorf("stat %s: %w", gitPath, err)
		}

		parent := filepath.Dir(current)
		if parent == current {
			return "", false, nil
		}
		current = parent
	}
}

func applyOverrides(cfg *Config, overrides *ConfigOverrides) {
	if cfg == nil || overrides == nil {
		return
	}
	if cfg.Roles.Primary == nil {
		cfg.Roles.Primary = cloneRoleConfig(DefaultConfig().Roles.Primary)
	}
	if overrides.Primary != "" {
		cfg.Roles.Primary.Agent = overrides.Primary
	}
	if overrides.NoCompanion {
		cfg.Roles.Companion = nil
		return
	}
	if overrides.Companion != "" {
		if cfg.Roles.Companion == nil {
			cfg.Roles.Companion = &RoleConfig{Window: 0}
		}
		cfg.Roles.Companion.Agent = overrides.Companion
	}
}

func hydrateReferencedAgents(cfg *Config) {
	if cfg.Agents == nil {
		cfg.Agents = make(map[string]AgentConfig)
	}

	defaults := DefaultConfig().Agents
	for name, agentCfg := range cfg.Agents {
		if agentCfg.CLI == "" {
			if builtin, ok := defaults[name]; ok {
				agentCfg.CLI = builtin.CLI
				cfg.Agents[name] = agentCfg
			}
		}
	}

	for _, roleCfg := range []*RoleConfig{cfg.Roles.Primary, cfg.Roles.Companion} {
		if roleCfg == nil || roleCfg.Agent == "" {
			continue
		}
		if _, ok := cfg.Agents[roleCfg.Agent]; ok {
			continue
		}
		if builtin, ok := defaults[roleCfg.Agent]; ok {
			cfg.Agents[roleCfg.Agent] = builtin
		}
	}
}

func cloneRoleConfig(cfg *RoleConfig) *RoleConfig {
	if cfg == nil {
		return nil
	}
	out := *cfg
	return &out
}

func mergeRoleConfig(parsed, base *RoleConfig, hasAgent, hasWindow bool) *RoleConfig {
	if parsed == nil && base == nil {
		return nil
	}

	merged := &RoleConfig{}
	if hasAgent {
		merged.Agent = parsed.Agent
	} else if base != nil {
		merged.Agent = base.Agent
	}

	if hasWindow {
		merged.Window = parsed.Window
	} else if base != nil {
		merged.Window = base.Window
	}

	return merged
}
