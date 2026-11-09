package host

// VaultConfig defines the host's Vault Agent: it logs in with the host's AppRole role (dev-infrastructure-<host>,
// created by github-infrastructure) and keeps a short-lived token for the host's user.
type VaultConfig struct {
	// Enabled indicates whether the host runs the Vault Agent. Default false. An enabled agent gets the role ID and
	// a generated secret ID (secrets/vault-role-id, secrets/vault-secret-id); the role must exist in Vault.
	Enabled *bool `yaml:"enabled,omitempty"`
	// Address is the URL of Vault (required when enabled).
	Address *string `yaml:"address,omitempty"`
}
