package host

import "github.com/muhlba91/pulumi-shared-library/pkg/util/defaults"

// defaultEnabled is the default of Config.Enabled: a host is enabled explicitly.
const defaultEnabled = false

// defaultCoderEnabled is the default of CoderConfig.Enabled (the Nix default of dev.coder.enable).
const defaultCoderEnabled = false

// Config defines Host-related configuration.
type Config struct {
	// Name is the name of the host: also its hostname and the name of its file ([<order>-]<name>.yml).
	Name string `yaml:"name"`
	// DeployOrder is the number a file name starts with (<order>-<name>.yml): the hosts are deployed in ascending
	// order (hosts without one last). Set from the file name, not part of the file.
	DeployOrder *int `yaml:"-"`
	// Enabled indicates whether the host may be deployed. Default false: a host is enabled explicitly, never by a
	// file that is still being written. A disabled host is still rendered and checked, but gets no generated keys
	// or secrets. Disabling a deployed host deletes them: after re-enabling it, the host still has the old deploy
	// key and host key, so the first deploy needs a static key and the new host key pushed by hand (or a reinstall),
	// and the new GitHub key must be registered again.
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
}

// IsEnabled reports whether the host is enabled (deployable); unset means disabled.
func (c *Config) IsEnabled() bool {
	return defaults.GetOrDefault(c.Enabled, defaultEnabled)
}

// UsesCoder reports whether the host runs the Coder server (coder.enabled).
func (c *Config) UsesCoder() bool {
	return c.Coder != nil && defaults.GetOrDefault(c.Coder.Enabled, defaultCoderEnabled)
}
