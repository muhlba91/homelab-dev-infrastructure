package host

// CoderConfig defines the Coder server of the host: it runs as the host's user, workspaces are directories.
type CoderConfig struct {
	// Enabled indicates whether the host runs the Coder server. Default false. An enabled Coder gets a generated
	// admin password (secrets/coder-admin-password).
	Enabled *bool `yaml:"enabled,omitempty"`
	// AccessURL is the URL Coder is reached at (default: http://<mgmt address>:3000).
	AccessURL *string `yaml:"accessUrl,omitempty"`
	// WildcardAccessURL is the hostname pattern for workspace apps (e.g. *.coder.example.org; default: none, apps
	// are path-based).
	WildcardAccessURL *string `yaml:"wildcardAccessUrl,omitempty"`
}
