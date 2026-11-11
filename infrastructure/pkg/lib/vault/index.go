// Package vault creates a host's Vault AppRole login: it reads the role ID and creates a secret ID. The role
// (dev-infrastructure-<host>) and its policy are managed by github-infrastructure.
package vault

import (
	"fmt"

	"github.com/muhlba91/pulumi-shared-library/pkg/lib/vault/approle"
	rModel "github.com/muhlba91/pulumi-shared-library/pkg/model/rotation"
	vaultApprole "github.com/pulumi/pulumi-vault/sdk/v7/go/vault/approle"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"github.com/muhlba91/homelab-dev-infrastructure/pkg/lib/config"
)

const (
	// backend is the mount path of the AppRole auth method (as in github-infrastructure).
	backend = "approle"
	// secretIDRotationDays is the rotation period of the secret ID (delivered again by the next deploy).
	secretIDRotationDays = 90
)

// Credentials are the files a host's Vault Agent logs in with.
type Credentials struct {
	// RoleID is the role ID of the host's AppRole role (secret).
	RoleID pulumi.StringOutput
	// SecretID is a secret ID of the host's AppRole role (secret).
	SecretID pulumi.StringOutput
}

// roleName returns the name of a host's AppRole role and policy: <global name>-<host>.
// host: The host name.
func roleName(host string) string {
	return fmt.Sprintf("%s-%s", config.GlobalName, host)
}

// Create reads the role ID of a host's AppRole role and creates a rotating secret ID for it.
// ctx: The Pulumi context.
// host: The host name.
func Create(ctx *pulumi.Context, host string) (*Credentials, error) {
	role := roleName(host)
	b := backend

	// A plain invoke, not the Output form: a failed read must fail the program. A rejected Output only skips the
	// applies built on it, so the role ID file would silently not be written and its bucket copy deleted.
	roleID, rErr := vaultApprole.GetAuthBackendRoleId(ctx, &vaultApprole.GetAuthBackendRoleIdArgs{
		Backend:  &b,
		RoleName: role,
	})
	if rErr != nil {
		return nil, fmt.Errorf("reading the role ID of %s: %w", role, rErr)
	}

	secretID, sErr := approle.CreateSecretID(ctx, config.ResourceName(host), &approle.SecretIDOptions{
		RoleName: pulumi.String(role),
		Backend:  &b,
		Metadata: pulumi.String(fmt.Sprintf(`{"host":%q}`, host)),
		Rotation: &rModel.Options{Days: secretIDRotationDays},
	})
	if sErr != nil {
		return nil, sErr
	}

	// The role ID is not secret in Vault's sense, but only the host needs it.
	secretRoleID, _ := pulumi.ToSecret(pulumi.String(roleID.RoleId)).(pulumi.StringOutput)

	return &Credentials{RoleID: secretRoleID, SecretID: secretID.SecretId}, nil
}
