package host

// UserConfig defines the host's (human) user: home on /data, the GitHub machine key, no sudo.
// Its SSH keys are the static keys in assets/ssh/*.pub (the same as the deploy user's).
type UserConfig struct {
	// Name is the login name.
	Name string `yaml:"name"`
	// UID is the pinned user id (1000-59999): files on /data keep their owner across reinstalls.
	UID int `yaml:"uid"`
	// Git is the identity of the commits made on the host.
	Git *GitConfig `yaml:"git"`
}

// GitConfig defines the git identity of the host's user.
type GitConfig struct {
	// Name is the author name.
	Name string `yaml:"name"`
	// Email is the author e-mail; the GitHub machine key signs commits for it (allowed signers).
	Email string `yaml:"email"`
}
