package host

// DockerConfig defines the host user's rootless Docker daemon (a dev tool for the workspaces).
type DockerConfig struct {
	// Enabled indicates whether the host's user gets a rootless Docker daemon. Default false.
	Enabled *bool `yaml:"enabled,omitempty"`
	// TrustedPorts are TCP ports or ranges ("8080", "8000-8999") opened to the trusted networks for containers that
	// publish on the host's address (`-p 0.0.0.0:8080:80`; the default bind address is 127.0.0.1). Default none.
	TrustedPorts []string `yaml:"trustedPorts,omitempty"`
}
