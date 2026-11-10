// Package backup creates a host's database backup credentials: a restic password and S3 access to the backup
// bucket (repositories below dev/<host>/<application>/).
package backup

import (
	"fmt"

	"github.com/muhlba91/pulumi-shared-library/pkg/lib/random"
	"github.com/muhlba91/pulumi-shared-library/pkg/lib/scaleway/iam/apikey"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumiverse/pulumi-scaleway/sdk/go/scaleway/iam"

	"github.com/muhlba91/homelab-dev-infrastructure/pkg/lib/config"
)

// passwordLength is the length of the restic repository password (letters and digits only).
const passwordLength = 48

// permissionSets are what restic needs: list the bucket, read, write and delete objects (prune). Scaleway IAM
// grants them for the whole project (it cannot limit an application to a bucket path).
//
//nolint:gochecknoglobals // constant list
var permissionSets = []string{
	"ObjectStorageBucketsRead",
	"ObjectStorageObjectsRead",
	"ObjectStorageObjectsWrite",
	"ObjectStorageObjectsDelete",
}

// Credentials are the files a host's backups need.
type Credentials struct {
	// Password is the password of the host's restic repositories (secret).
	Password pulumi.StringOutput
	// S3Environment is an environment file with the S3 credentials of the host's backup application (secret).
	S3Environment pulumi.StringOutput
}

// Repository returns the base of a host's restic repositories, s3:<endpoint>/<backup bucket>/dev/<host>; each
// application appends /<application>.
// host: The host name.
func Repository(host string) string {
	return fmt.Sprintf(
		"s3:https://s3.%s.scw.cloud/%s/%s/%s",
		config.ScalewayRegion, config.BackupBucketID, config.BackupPath, host,
	)
}

// Create creates a host's Scaleway IAM application, API key and policy, and the restic password. The application
// and the policy are created directly: the shared library's helpers do not take the organization.
// ctx: The Pulumi context.
// host: The host name.
func Create(ctx *pulumi.Context, host string) (*Credentials, error) {
	name := config.ResourceName(fmt.Sprintf("%s-backup", host))
	description := fmt.Sprintf("Backups of %s (%s)", host, config.GlobalName)

	app, aErr := iam.NewApplication(ctx, fmt.Sprintf("scaleway-application-%s", name), &iam.ApplicationArgs{
		Name:           pulumi.String(name),
		Description:    pulumi.String(description),
		OrganizationId: pulumi.String(config.ScalewayOrganizationID),
	})
	if aErr != nil {
		return nil, aErr
	}

	key, kErr := apikey.Create(ctx, name, &apikey.CreateOptions{
		Description:      pulumi.String(description),
		ApplicationID:    app.ID(),
		DefaultProjectID: pulumi.String(config.ScalewayProjectID),
		PulumiOptions:    []pulumi.ResourceOption{pulumi.DependsOn([]pulumi.Resource{app})},
	})
	if kErr != nil {
		return nil, kErr
	}

	if _, pErr := iam.NewPolicy(ctx, fmt.Sprintf("scaleway-policy-%s", name), &iam.PolicyArgs{
		// Like the application's (IAM names are limited to 64 characters).
		Name:           pulumi.String(name),
		Description:    pulumi.String(fmt.Sprintf("Backups of %s: object storage in the project", host)),
		OrganizationId: pulumi.String(config.ScalewayOrganizationID),
		ApplicationId:  app.ID(),
		Rules: iam.PolicyRuleArray{
			&iam.PolicyRuleArgs{
				ProjectIds:         pulumi.ToStringArray([]string{config.ScalewayProjectID}),
				PermissionSetNames: pulumi.ToStringArray(permissionSets),
			},
		},
	}); pErr != nil {
		return nil, pErr
	}

	password, rErr := random.CreatePassword(
		ctx,
		fmt.Sprintf("password-restic-%s-%s", host, config.Environment),
		&random.PasswordOptions{Length: passwordLength, Special: false},
	)
	if rErr != nil {
		return nil, rErr
	}

	// Secret, as the API key's secret key is.
	env := pulumi.Sprintf(
		"AWS_ACCESS_KEY_ID=%s\nAWS_SECRET_ACCESS_KEY=%s\nAWS_DEFAULT_REGION=%s\n",
		key.AccessKey, key.SecretKey, config.ScalewayRegion,
	)

	return &Credentials{Password: password.Password, S3Environment: env}, nil
}
