package host

// Config defines Host-related configuration.
type Config struct {
	// Name is the name of the host: also its hostname and the name of its file ([<order>-]<name>.yml).
	Name string `yaml:"name"`
	// DeployOrder is the number a file name starts with (<order>-<name>.yml): the hosts are deployed in ascending
	// order (hosts without one last). Set from the file name, not part of the file.
	DeployOrder *int `yaml:"-"`
	// Enabled marks the host deployable. Default false: a disabled host is rendered and checked but gets no keys
	// or secrets, and disabling a deployed host deletes them (re-enabling needs a reinstall or the new host key
	// pushed by hand, and the new GitHub key registered).
	Enabled *bool `yaml:"enabled,omitempty"`
	// Deploy is the deployment configuration (automated deploys by CI) of the host.
	Deploy *DeployConfig `yaml:"deploy,omitempty"`
	// Hardware is the hardware configuration of the host.
	Hardware *HardwareConfig `yaml:"hardware"`
	// System is the system configuration (watchdog, garbage collection) of the host.
	System *SystemConfig `yaml:"system,omitempty"`
	// Network is the network configuration of the host.
	Network *NetworkConfig `yaml:"network"`
	// User is the configuration of the host's (human) user.
	User *UserConfig `yaml:"user"`
	// Docker is the configuration of the user's rootless Docker daemon.
	Docker *DockerConfig `yaml:"docker,omitempty"`
	// Coder is the configuration of the Coder server.
	Coder *CoderConfig `yaml:"coder,omitempty"`
	// Vault is the configuration of the Vault Agent.
	Vault *VaultConfig `yaml:"vault,omitempty"`
	// Paseo is the configuration of the Paseo daemon.
	Paseo *PaseoConfig `yaml:"paseo,omitempty"`
}

// IsEnabled reports whether the host is enabled (deployable); unset means disabled.
func (c *Config) IsEnabled() bool {
	return isTrue(c.Enabled)
}

// UsesCoder reports whether the host runs the Coder server (coder.enabled).
func (c *Config) UsesCoder() bool {
	return c.Coder != nil && isTrue(c.Coder.Enabled)
}

// UsesCoderOIDC reports whether the host's Coder logs in with OIDC (coder.oidc).
func (c *Config) UsesCoderOIDC() bool {
	return c.UsesCoder() && isTrue(c.Coder.OIDC)
}

// UsesVault reports whether the host runs the Vault Agent (vault.enabled).
func (c *Config) UsesVault() bool {
	return c.Vault != nil && isTrue(c.Vault.Enabled)
}

// UsesPaseo reports whether the host runs the Paseo daemon (paseo.enabled).
func (c *Config) UsesPaseo() bool {
	return c.Paseo != nil && isTrue(c.Paseo.Enabled)
}

// isTrue reports whether an optional flag is set and true.
func isTrue(b *bool) bool {
	return b != nil && *b
}
