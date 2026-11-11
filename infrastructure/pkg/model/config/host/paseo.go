package host

// PaseoConfig defines the Paseo daemon of the host (agent orchestration): a systemd user unit of the host's user,
// its web UI and API on one port behind the cluster's gateway.
type PaseoConfig struct {
	// Enabled indicates whether the host runs the Paseo daemon. Default false. An enabled Paseo gets a generated
	// password (secrets/paseo-env).
	Enabled *bool `yaml:"enabled,omitempty"`
	// Hostname is the name the gateway forwards to Paseo (e.g. paseo.example.org): allowed in the Host header,
	// and the gateway's X-Forwarded-* headers are trusted from the trusted networks. Default none (only IP
	// addresses and localhost).
	Hostname *string `yaml:"hostname,omitempty"`
}
