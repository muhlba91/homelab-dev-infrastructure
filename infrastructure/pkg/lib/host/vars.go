package host

import (
	"github.com/muhlba91/pulumi-shared-library/pkg/util/template"

	"github.com/muhlba91/homelab-dev-infrastructure/pkg/model/config/host"
)

// varsTemplate is the template of the vars.nix file (Go text/template).
const varsTemplate = "./assets/vars.nix.j2"

// renderVars renders the vars.nix file of a host.
// h: The host configuration.
// deployKeys: The public SSH keys of the deploy user (the static ones plus the host's generated deploy key).
// userKeys: The public SSH keys of the host's user (the static ones).
// hostKey: The public SSH host key of the host; empty for a disabled host.
// githubKey: The public GitHub machine key of the host's user; empty for a disabled host.
// backupRepository: The base of the host's restic repositories; empty for a host without backups.
func renderVars(
	h *host.Config,
	deployKeys []string,
	userKeys []string,
	hostKey string,
	githubKey string,
	backupRepository string,
) (string, error) {
	return template.Render(varsTemplate, map[string]any{
		"Host":             h,
		"DeployKeys":       deployKeys,
		"UserKeys":         userKeys,
		"HostKey":          hostKey,
		"GitHubKey":        githubKey,
		"BackupRepository": backupRepository,
	})
}
