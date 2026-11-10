package host

import (
	"bytes"
	"errors"
	"fmt"
	"path/filepath"
	"strings"
	"text/template"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"github.com/muhlba91/homelab-dev-infrastructure/pkg/lib/config"
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
	// OIDC is the OIDC provider of Coder's login (only its URL and client ID are rendered); nil without
	// coder.oidc.
	OIDC *config.OIDCConfig
}

// nixEscaper escapes what is special in a Nix double-quoted string.
//
//nolint:gochecknoglobals // constant replacer
var nixEscaper = strings.NewReplacer(`\`, `\\`, `"`, `\"`, "${", `\${`, "\n", `\n`, "\r", `\r`, "\t", `\t`)

// nixString quotes a string (or a *string) as a Nix string literal.
// v: The value.
func nixString(v any) (string, error) {
	switch s := v.(type) {
	case string:
		return `"` + nixEscaper.Replace(s) + `"`, nil
	case *string:
		if s == nil {
			return "", errors.New("nix: nil string")
		}
		return nixString(*s)
	default:
		return "", fmt.Errorf("nix: unsupported type %T", v)
	}
}

// renderVars renders a host's vars.nix.
// data: The template data.
func renderVars(data *varsData) (string, error) {
	tpl, err := template.New(filepath.Base(varsTemplate)).
		Funcs(template.FuncMap{"nix": nixString}).
		ParseFiles(varsTemplate)
	if err != nil {
		return "", err
	}

	var buf bytes.Buffer
	if eErr := tpl.Execute(&buf, data); eErr != nil {
		return "", eErr
	}
	return buf.String(), nil
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
