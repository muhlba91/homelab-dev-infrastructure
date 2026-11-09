package host

// DeployConfig defines how a host is deployed.
type DeployConfig struct {
	// Automated indicates whether CI deploys the host after every `pulumi up` on main (default false; only for an
	// enabled host). Off, the host keeps its keys and is deployed by hand only (`./host deploy`).
	Automated *bool `yaml:"automated,omitempty"`
}
