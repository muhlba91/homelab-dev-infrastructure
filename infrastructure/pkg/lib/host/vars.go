package host

import (
	"github.com/muhlba91/pulumi-shared-library/pkg/util/template"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"github.com/muhlba91/homelab-dev-infrastructure/pkg/model/config/host"
)

// varsTemplate is the template of vars.nix (Go text/template).
const varsTemplate = "./assets/vars.nix.j2"

// varsData is the data of the vars.nix template.
type varsData struct {
	// Host is the host configuration.
	Host *host.Config
	// DeployKeys are the deploy user's public SSH keys (the static ones plus the generated deploy key).
	DeployKeys []string
	// UserKeys are the user's public SSH keys.
	UserKeys []string
	// HostKey is the public SSH host key; empty for a disabled host.
	HostKey string
	// GitHubKey is the public GitHub machine key; empty for a disabled host.
	GitHubKey string
	// BackupRepository is the base of the restic repositories; empty without backups.
	BackupRepository string
}

// renderVars renders a host's vars.nix.
// data: The template data.
func renderVars(data *varsData) (string, error) {
	return template.Render(varsTemplate, data)
}

// contextOutput returns a known value as an output of the program's context: a plain pulumi.String is not awaited
// when the program ends, which could cut off the file writes.
// ctx: The Pulumi context.
// value: The value.
func contextOutput(ctx *pulumi.Context, value string) pulumi.StringOutput {
	out, resolve, _ := ctx.NewOutput()
	resolve(value)

	str, _ := out.ApplyT(func(v any) string {
		s, _ := v.(string)
		return s
	}).(pulumi.StringOutput)

	return str
}
