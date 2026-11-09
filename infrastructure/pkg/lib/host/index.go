package host

import (
	"fmt"
	"path"
	"slices"
	"strings"

	"github.com/muhlba91/pulumi-shared-library/pkg/lib/random"
	"github.com/muhlba91/pulumi-shared-library/pkg/lib/tls"
	rModel "github.com/muhlba91/pulumi-shared-library/pkg/model/rotation"
	tlsProv "github.com/pulumi/pulumi-tls/sdk/v5/go/tls"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"github.com/muhlba91/homelab-dev-infrastructure/pkg/lib/backup"
	"github.com/muhlba91/homelab-dev-infrastructure/pkg/lib/config"
	"github.com/muhlba91/homelab-dev-infrastructure/pkg/lib/vault"
	"github.com/muhlba91/homelab-dev-infrastructure/pkg/model/config/host"
)

const (
	// passwordLength is the length of the generated passwords (letters and digits only).
	passwordLength = 32
	// githubKeyRotationDays is the rotation period of the GitHub machine key (re-registered on GitHub by hand).
	githubKeyRotationDays = 365
)

// Data holds the generated resources and files of a host.
type Data struct {
	// DeployKey is the SSH key pair of the deploy user of the host; nil for a disabled host.
	DeployKey *tlsProv.PrivateKey
	// HostKey is the SSH host key pair of the host (its public key is pinned in vars.nix); nil for a disabled host.
	HostKey *tlsProv.PrivateKey
	// GitHubKey is the GitHub machine key of the host's user (authentication and commit signing; its public key is
	// in vars.nix for git's allowed signers and a stack output for the registration on GitHub); nil for a disabled
	// host.
	GitHubKey *tlsProv.PrivateKey
	// CoderAdminPassword is the password of Coder's first (admin) user (secret); nil for a disabled host or one
	// without Coder.
	CoderAdminPassword *pulumi.StringOutput
	// Backup holds the credentials of the host's database backups; nil for a disabled host or one without Coder
	// (the only application with a database so far).
	Backup *backup.Credentials
	// Vault holds the Vault Agent's AppRole login; nil for a disabled host or one without the agent.
	Vault *vault.Credentials
	// Vars is the content of the vars.nix file of the host.
	Vars pulumi.StringOutput
}

// ConfigureHost creates the resources of a host and renders its vars.nix. An enabled host gets a deploy key, an SSH
// host key, a GitHub machine key and, if it runs Coder, a Coder admin password and backup credentials (its restic
// repositories in the backup bucket), and if it runs the Vault Agent, the AppRole role ID and a secret ID. A disabled
// host gets none of them
// (disabling a host deletes them); its vars.nix holds only the static SSH keys, so it is still rendered and checked,
// but not deployable.
// ctx: The Pulumi context.
// h: The host configuration.
// staticSSHKeys: The static public SSH keys of the deploy user and the host's user; the host's generated deploy key
// is added to the deploy user's.
func ConfigureHost(ctx *pulumi.Context, h *host.Config, staticSSHKeys []string) (*Data, error) {
	if !h.IsEnabled() {
		vars, vErr := renderVars(h, staticSSHKeys, staticSSHKeys, "", "", "")
		if vErr != nil {
			return nil, vErr
		}

		return &Data{Vars: contextOutput(ctx, vars)}, nil
	}

	deployKey, dErr := tls.Create(ctx, config.ResourceName(fmt.Sprintf("%s-deploy", h.Name)), &tls.CreateOptions{
		Algorithm: tls.AlgorithmED25519,
	})
	if dErr != nil {
		return nil, dErr
	}

	hostKey, hErr := tls.Create(ctx, config.ResourceName(fmt.Sprintf("%s-host", h.Name)), &tls.CreateOptions{
		Algorithm: tls.AlgorithmED25519,
	})
	if hErr != nil {
		return nil, hErr
	}

	githubKey, gErr := tls.Create(ctx, config.ResourceName(fmt.Sprintf("%s-github", h.Name)), &tls.CreateOptions{
		Algorithm: tls.AlgorithmED25519,
		Rotation:  &rModel.Options{Days: githubKeyRotationDays},
	})
	if gErr != nil {
		return nil, gErr
	}

	var coderAdminPassword *pulumi.StringOutput
	if h.UsesCoder() {
		// The password helper adds no type prefix; the host name is unique within the stack.
		password, pErr := random.CreatePassword(
			ctx,
			fmt.Sprintf("password-coder-admin-%s-%s", h.Name, config.Environment),
			&random.PasswordOptions{
				Length:  passwordLength,
				Special: false,
			},
		)
		if pErr != nil {
			return nil, pErr
		}
		coderAdminPassword = &password.Password
	}
	var backupCredentials *backup.Credentials
	backupRepository := ""
	if h.UsesCoder() {
		creds, bErr := backup.Create(ctx, h.Name)
		if bErr != nil {
			return nil, bErr
		}
		backupCredentials = creds
		backupRepository = backup.Repository(h.Name)
	}
	var vaultCredentials *vault.Credentials
	if h.UsesVault() {
		creds, vErr := vault.Create(ctx, h.Name)
		if vErr != nil {
			return nil, vErr
		}
		vaultCredentials = creds
	}

	// An error returned from the apply fails the update instead of writing an empty file.
	vars, _ := pulumi.All(deployKey.PublicKeyOpenssh, hostKey.PublicKeyOpenssh, githubKey.PublicKeyOpenssh).
		ApplyT(func(keys []any) (string, error) {
			deployPublicKey, _ := keys[0].(string)
			hostPublicKey, _ := keys[1].(string)
			githubPublicKey, _ := keys[2].(string)
			return renderVars(
				h,
				slices.Concat(staticSSHKeys, []string{strings.TrimSpace(deployPublicKey)}),
				staticSSHKeys,
				strings.TrimSpace(hostPublicKey),
				strings.TrimSpace(githubPublicKey),
				backupRepository,
			)
		}).(pulumi.StringOutput)

	return &Data{
		DeployKey:          deployKey,
		HostKey:            hostKey,
		GitHubKey:          githubKey,
		CoderAdminPassword: coderAdminPassword,
		Backup:             backupCredentials,
		Vault:              vaultCredentials,
		Vars:               vars,
	}, nil
}

// VarsDir returns the directory of a host's vars.nix below the output directory and the bucket path: hosts/<host>.
// hosts/ is the flake's Nix input, copied into the world-readable Nix store as a whole: nothing but the vars.nix
// files may ever be written there.
// name: The host name.
func VarsDir(name string) string {
	return path.Join("hosts", name)
}

// KeysDir returns the directory of a host's private files below the output directory and the bucket path:
// keys/<host>, holding the deploy user's private key and, below secrets/, the files pushed to the host.
// name: The host name.
func KeysDir(name string) string {
	return path.Join("keys", name)
}

// contextOutput returns a known value as an output of the program's context. A plain pulumi.String output is not
// awaited when the program ends, so the applies writing it to a file could be cut off.
// ctx: The Pulumi context.
// value: The value of the output.
func contextOutput(ctx *pulumi.Context, value string) pulumi.StringOutput {
	out, resolve, _ := ctx.NewOutput()
	resolve(value)

	str, _ := out.ApplyT(func(v any) string {
		s, _ := v.(string)
		return s
	}).(pulumi.StringOutput)

	return str
}
