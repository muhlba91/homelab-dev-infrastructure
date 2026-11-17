package host

// CleanupConfig defines the regular cleanup of the user's home (Docker data, mise tool versions, caches, logs,
// agent state).
type CleanupConfig struct {
	// OlderThan is the age (`<n>d`): unused Docker data and mise's download cache older than this, Pulumi plugins
	// unused for this long, and older logs and agent state are deleted. Default 14d.
	OlderThan *string `yaml:"olderThan,omitempty"`
	// Schedule is when the cleanup runs (a systemd OnCalendar expression). Default weekly.
	Schedule *string `yaml:"schedule,omitempty"`
	// Docker prunes unused Docker data and every unused anonymous volume (with docker.enabled). Default true.
	Docker *bool `yaml:"docker,omitempty"`
	// Mise prunes tool versions no config selects any more. Default true.
	Mise *bool `yaml:"mise,omitempty"`
	// Caches is the cleanup of unused Pulumi plugins and the tools' caches.
	Caches *CacheCleanupConfig `yaml:"caches,omitempty"`
	// Logs deletes Paseo's old daemon logs (with paseo.enabled) and the old state of agents of deleted or stopped
	// workspaces (with coder.enabled). Default true.
	Logs *bool `yaml:"logs,omitempty"`
}

// CacheCleanupConfig defines the cleanup of unused Pulumi plugins and the tools' caches.
type CacheCleanupConfig struct {
	// Enabled deletes unused Pulumi plugins and clears every cache larger than MaxSize. Default true.
	Enabled *bool `yaml:"enabled,omitempty"`
	// MaxSize is the size limit of each cache, in GiB. Default 5.
	MaxSize *int `yaml:"maxSize,omitempty"`
}
