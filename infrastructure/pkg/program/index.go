package program

import (
	"os"
	"path"
	"path/filepath"

	"github.com/muhlba91/pulumi-shared-library/pkg/util/dir"
	"github.com/muhlba91/pulumi-shared-library/pkg/util/storage"
	scwUpload "github.com/muhlba91/pulumi-shared-library/pkg/util/storage/scaleway"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"github.com/muhlba91/homelab-dev-infrastructure/pkg/lib/config"
	"github.com/muhlba91/homelab-dev-infrastructure/pkg/lib/host"
)

// outputDir is the local directory the files are written to (./host's OUTPUTS).
const outputDir = "outputs"

// secretPermissions are the permissions of the written files.
const secretPermissions os.FileMode = 0o600

// outputDirPermissions are the permissions of the output directories, which hold private keys.
const outputDirPermissions os.FileMode = 0o700

// Run is the Pulumi program: it creates the resources of every host and writes its files.
// ctx: The Pulumi context.
func Run(ctx *pulumi.Context) error {
	hosts, sshKeys, err := config.LoadConfig(ctx)
	if err != nil {
		return err
	}

	if dErr := dir.Create(outputDir); dErr != nil {
		return dErr
	}

	outputs := pulumi.Map{}
	for _, data := range hosts {
		hostData, hErr := host.ConfigureHost(ctx, data, sshKeys)
		if hErr != nil {
			return hErr
		}

		if wErr := writeOutputFiles(ctx, data.Name, hostData); wErr != nil {
			return wErr
		}

		outputs[data.Name] = host.Output(data, hostData)
	}

	ctx.Export("hosts", outputs)

	return nil
}

// writeOutputFiles writes the files of a host below outputs/ (the layout ./host reads) and uploads them to the
// bucket under the same paths: hosts/<host>/vars.nix and, for an enabled host, keys/<host>/deploy-key (the deploy
// user's private key) and keys/<host>/secrets/ (pushed to the host: the SSH host key, the GitHub machine key, the
// Coder admin password, the backup credentials).
// ctx: The Pulumi context.
// name: The name of the host.
// hostData: The generated resources and files of the host.
func writeOutputFiles(ctx *pulumi.Context, name string, hostData *host.Data) error {
	type outputFile struct {
		dir     string
		name    string
		content pulumi.StringInput
	}

	keysDir := host.KeysDir(name)
	secretsDir := path.Join(keysDir, "secrets")

	files := []outputFile{{host.VarsDir(name), "vars.nix", hostData.Vars}}
	if hostData.DeployKey != nil {
		files = append(files, outputFile{keysDir, "deploy-key", hostData.DeployKey.PrivateKeyOpenssh})
	}
	if hostData.HostKey != nil {
		files = append(files, outputFile{secretsDir, "ssh-host-key", hostData.HostKey.PrivateKeyOpenssh})
	}
	if hostData.GitHubKey != nil {
		files = append(files, outputFile{secretsDir, "github-ssh-key", hostData.GitHubKey.PrivateKeyOpenssh})
	}
	if hostData.CoderAdminPassword != nil {
		files = append(files, outputFile{secretsDir, "coder-admin-password", *hostData.CoderAdminPassword})
	}
	if hostData.Backup != nil {
		files = append(files,
			outputFile{secretsDir, "restic-password", hostData.Backup.Password},
			outputFile{secretsDir, "restic-s3", hostData.Backup.S3Environment},
		)
	}

	for _, file := range files {
		// The files are written asynchronously, and a failed write is only logged: create the directory first.
		outputPath := filepath.Join(".", outputDir, filepath.FromSlash(file.dir))
		if err := os.MkdirAll(outputPath, outputDirPermissions); err != nil {
			return err
		}

		scwUpload.WriteFileAndUpload(ctx, &storage.WriteFileAndUploadOptions{
			BucketID:    config.BucketID,
			BucketPath:  path.Join(config.BucketPath, file.dir),
			OutputPath:  outputPath,
			Name:        file.name,
			Content:     file.content,
			Labels:      config.CommonLabels(),
			Permissions: []os.FileMode{secretPermissions},
		})
	}

	return nil
}
