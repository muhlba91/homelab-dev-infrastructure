package config

import (
	"fmt"
	"os"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
	"github.com/rs/zerolog/log"

	"github.com/muhlba91/homelab-dev-infrastructure/pkg/model/config/host"
	"github.com/muhlba91/homelab-dev-infrastructure/pkg/util"
)

const (
	// hostsDir is the directory of the host configuration files.
	hostsDir = "./assets/hosts"
	// sshKeysDir is the directory of the static public SSH keys of the deploy user and the host's user.
	sshKeysDir = "./assets/ssh"
)

const (
	// GlobalName is the prefix of the resource names and the bucket path.
	GlobalName = "dev-infrastructure"
	// BackupPath is the folder of this project in the backup bucket.
	BackupPath = "dev"
)

//nolint:gochecknoglobals // global configuration is acceptable here
var (
	// Environment is the stack name (e.g. prod).
	Environment string
	// BucketPath is the path within the buckets for this project.
	BucketPath string
	// BucketID is the ID of the main storage bucket.
	BucketID string
	// BackupBucketID is the ID of the backup bucket (database backups below <BackupPath>/<host>/<application>/).
	BackupBucketID string
	// ScalewayOrganizationID is the Scaleway organization (SCW_ORGANIZATION_ID): IAM resources belong to it.
	ScalewayOrganizationID string
	// ScalewayProjectID is the Scaleway project of the buckets (SCW_PROJECT_ID): the scope of the backup
	// credentials.
	ScalewayProjectID string
	// ScalewayRegion is the Scaleway region of the buckets (SCW_DEFAULT_REGION): the S3 endpoint.
	ScalewayRegion string
)

// LoadConfig loads the configuration for the given Pulumi context: the host configurations and the static public
// SSH keys (the same for every host: the deploy user's and the host user's).
// ctx: The Pulumi context.
func LoadConfig(ctx *pulumi.Context) ([]*host.Config, []string, error) {
	Environment = ctx.Stack()

	cfg := config.New(ctx, "")

	BucketID = cfg.Require("bucketId")
	BackupBucketID = cfg.Require("backupBucketId")

	// The Scaleway provider itself reads SCW_DEFAULT_ORGANIZATION_ID and SCW_DEFAULT_PROJECT_ID, which local.env
	// and CI do not set: the values the backups need are passed explicitly.
	var sErr error
	if ScalewayOrganizationID, sErr = requireEnv("SCW_ORGANIZATION_ID"); sErr != nil {
		return nil, nil, sErr
	}
	if ScalewayProjectID, sErr = requireEnv("SCW_PROJECT_ID"); sErr != nil {
		return nil, nil, sErr
	}
	if ScalewayRegion, sErr = requireEnv("SCW_DEFAULT_REGION"); sErr != nil {
		return nil, nil, sErr
	}
	BucketPath = fmt.Sprintf("%s/%s", GlobalName, Environment)

	hosts, rErr := util.ParseHostsFromFiles(hostsDir)
	if rErr != nil {
		log.Err(rErr).Msg("[config] error parsing host configurations from files")
		return nil, nil, rErr
	}

	sshKeys, kErr := util.ParseSSHKeysFromFiles(sshKeysDir)
	if kErr != nil {
		log.Err(kErr).Msg("[config] error parsing ssh keys from files")
		return nil, nil, kErr
	}

	return hosts, sshKeys, nil
}

// requireEnv returns the value of an environment variable, or an error if it is unset or empty.
// name: The variable's name.
func requireEnv(name string) (string, error) {
	value := os.Getenv(name)
	if value == "" {
		return "", fmt.Errorf("environment variable %s is required", name)
	}
	return value, nil
}

// ResourceName returns the name of a host's resources: <global name>-<host>-<environment>. The resource helpers of
// the shared library prefix it with their type (e.g. ed25519-key-).
// host: The host name.
func ResourceName(host string) string {
	return fmt.Sprintf("%s-%s-%s", GlobalName, host, Environment)
}

// CommonLabels returns a map of common labels to be used across resources.
func CommonLabels() map[string]string {
	return map[string]string{
		"environment": Environment,
		"application": GlobalName,
	}
}
