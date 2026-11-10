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

// Data holds the generated resources and files of a host. The keys are nil for a disabled host; the Coder and
// backup values also for a host without Coder, the Vault values for a host without the Vault Agent.
type Data struct {
	// DeployKey is the SSH key of the deploy user.
	DeployKey *tlsProv.PrivateKey
	// HostKey is the SSH host key (its public key is pinned in vars.nix).
	HostKey *tlsProv.PrivateKey
	// GitHubKey is the user's GitHub key for authentication and commit signing.
	GitHubKey *tlsProv.PrivateKey
	// CoderAdminPassword is the password of Coder's first user (secret).
	CoderAdminPassword *pulumi.StringOutput
	// CoderOIDC is Coder's OIDC client secret as an environment file (secret); nil without coder.oidc.
	CoderOIDC *pulumi.StringOutput
	// Backup holds the credentials of the database backups.
	Backup *backup.Credentials
	// Vault holds the Vault Agent's AppRole login.
	Vault *vault.Credentials
	// Vars is the content of the host's vars.nix.
	Vars pulumi.StringOutput
}

// ConfigureHost creates a host's keys and secrets and renders its vars.nix. A disabled host gets only the vars.nix
// with the static SSH keys: it is rendered and checked, but not deployable.
// ctx: The Pulumi context.
// h: The host configuration.
// staticSSHKeys: The static public SSH keys of the deploy user and the user.
// provider: The OIDC provider of the stack config (nil when unset).
func ConfigureHost(
	ctx *pulumi.Context, h *host.Config, staticSSHKeys []string, provider *config.OIDCConfig,
) (*Data, error) {
	if !h.IsEnabled() {
		vars, err := renderVars(&varsData{Host: h, DeployKeys: staticSSHKeys, UserKeys: staticSSHKeys})
		if err != nil {
			return nil, err
		}
		return &Data{Vars: contextOutput(ctx, vars)}, nil
	}

	data := &Data{}
	var err error
	if data.DeployKey, err = createKey(ctx, h.Name, "deploy", nil); err != nil {
		return nil, err
	}
	if data.HostKey, err = createKey(ctx, h.Name, "host", nil); err != nil {
		return nil, err
	}
	githubRotation := &rModel.Options{Days: githubKeyRotationDays}
	if data.GitHubKey, err = createKey(ctx, h.Name, "github", githubRotation); err != nil {
		return nil, err
	}

	backupRepository := ""
	if h.UsesCoder() {
		password, pErr := random.CreatePassword(
			ctx,
			fmt.Sprintf("password-coder-admin-%s-%s", h.Name, config.Environment),
			&random.PasswordOptions{Length: passwordLength, Special: false},
		)
		if pErr != nil {
			return nil, pErr
		}
		data.CoderAdminPassword = &password.Password

		if data.Backup, err = backup.Create(ctx, h.Name); err != nil {
			return nil, err
		}
		backupRepository = backup.Repository(h.Name)
	}

	oidc, oErr := oidcProvider(h, provider)
	if oErr != nil {
		return nil, oErr
	}
	data.CoderOIDC = oidcEnvFile(ctx, oidc)

	if h.UsesVault() {
		if data.Vault, err = vault.Create(ctx, h.Name); err != nil {
			return nil, err
		}
	}

	// An error returned from the apply fails the update instead of writing an empty file.
	data.Vars, _ = pulumi.All(
		data.DeployKey.PublicKeyOpenssh, data.HostKey.PublicKeyOpenssh, data.GitHubKey.PublicKeyOpenssh,
	).ApplyT(func(keys []any) (string, error) {
		public := make([]string, len(keys))
		for i, k := range keys {
			s, ok := k.(string)
			if !ok {
				return "", fmt.Errorf("host %s: public key %d is not a string", h.Name, i)
			}
			public[i] = strings.TrimSpace(s)
		}
		return renderVars(&varsData{
			Host:             h,
			DeployKeys:       slices.Concat(staticSSHKeys, public[:1]),
			UserKeys:         staticSSHKeys,
			HostKey:          public[1],
			GitHubKey:        public[2],
			BackupRepository: backupRepository,
			OIDC:             oidc,
		})
	}).(pulumi.StringOutput)

	return data, nil
}

// oidcProvider returns the OIDC provider of a host with coder.oidc; nil without.
// h: The host configuration.
// provider: The OIDC provider of the stack config (nil when unset).
func oidcProvider(h *host.Config, provider *config.OIDCConfig) (*config.OIDCConfig, error) {
	if !h.UsesCoderOIDC() {
		return nil, nil //nolint:nilnil // no provider is not an error
	}
	if provider == nil {
		return nil, fmt.Errorf("host %s: coder.oidc needs the stack config zitadel", h.Name)
	}
	return provider, nil
}

// oidcEnvFile returns the client secret as Coder's environment file (secret); nil without a provider.
// ctx: The Pulumi context.
// provider: The OIDC provider.
func oidcEnvFile(ctx *pulumi.Context, provider *config.OIDCConfig) *pulumi.StringOutput {
	if provider == nil {
		return nil
	}
	env := pulumi.Sprintf("CODER_OIDC_CLIENT_SECRET=%s\n", pulumi.ToSecret(contextOutput(ctx, provider.ClientSecret)))
	return &env
}

// createKey creates an ed25519 key of a host, named <global name>-<host>-<purpose>-<environment>.
// ctx: The Pulumi context.
// name: The host name.
// purpose: The key's purpose (deploy, host, github).
// rotation: The rotation; nil for none.
func createKey(ctx *pulumi.Context, name, purpose string, rotation *rModel.Options) (*tlsProv.PrivateKey, error) {
	return tls.Create(ctx, config.ResourceName(fmt.Sprintf("%s-%s", name, purpose)), &tls.CreateOptions{
		Algorithm: tls.AlgorithmED25519,
		Rotation:  rotation,
	})
}

// VarsDir returns hosts/<host>, below the output directory and the bucket path. hosts/ is the flake's input and
// lands in the world-readable Nix store: only vars.nix files may be written there.
// name: The host name.
func VarsDir(name string) string {
	return path.Join("hosts", name)
}

// KeysDir returns keys/<host>, below the output directory and the bucket path: the deploy key and, in secrets/,
// the files pushed to the host.
// name: The host name.
func KeysDir(name string) string {
	return path.Join("keys", name)
}
