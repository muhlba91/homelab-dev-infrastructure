package program

import (
	"errors"
	"io/fs"
	"os"
	"path"
	"path/filepath"

	"github.com/muhlba91/pulumi-shared-library/pkg/util/storage"
	scwUpload "github.com/muhlba91/pulumi-shared-library/pkg/util/storage/scaleway"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"github.com/muhlba91/homelab-dev-infrastructure/pkg/lib/config"
	"github.com/muhlba91/homelab-dev-infrastructure/pkg/lib/host"
)

const (
	// outputDir is the local directory the files are written to (./host's OUTPUTS).
	outputDir = "outputs"
	// filePermissions are the permissions of the written files.
	filePermissions os.FileMode = 0o600
	// dirPermissions are the permissions of the output directories, which hold private keys.
	dirPermissions os.FileMode = 0o700
)

// Run is the Pulumi program: it creates the resources of every host and writes its files.
// ctx: The Pulumi context.
func Run(ctx *pulumi.Context) error {
	hosts, sshKeys, err := config.LoadConfig(ctx)
	if err != nil {
		return err
	}

	outputs := pulumi.Map{}
	written := map[string]bool{}
	for _, h := range hosts {
		data, hErr := host.ConfigureHost(ctx, h, sshKeys, config.OIDC)
		if hErr != nil {
			return hErr
		}

		files, wErr := writeOutputFiles(ctx, h.Name, data)
		if wErr != nil {
			return wErr
		}
		for _, f := range files {
			written[f] = true
		}

		outputs[h.Name] = host.Output(h, data)
	}

	// Not in a preview: it writes nothing.
	if !ctx.DryRun() {
		if pErr := pruneKeys(written); pErr != nil {
			return pErr
		}
	}

	ctx.Export("hosts", outputs)

	return nil
}

// writeOutputFiles writes a host's files below outputs/ (the layout ./host reads) and uploads them to the bucket
// under the same paths: hosts/<host>/vars.nix, keys/<host>/deploy-key and keys/<host>/secrets/*.
// Returns the local paths of the files.
// ctx: The Pulumi context.
// name: The name of the host.
// hostData: The generated resources and files of the host.
func writeOutputFiles(ctx *pulumi.Context, name string, hostData *host.Data) ([]string, error) {
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
	if hostData.CoderOIDC != nil {
		files = append(files, outputFile{secretsDir, "coder-oidc", *hostData.CoderOIDC})
	}
	if hostData.PaseoEnv != nil {
		files = append(files, outputFile{secretsDir, "paseo-env", *hostData.PaseoEnv})
	}
	if hostData.Backup != nil {
		files = append(files,
			outputFile{secretsDir, "restic-password", hostData.Backup.Password},
			outputFile{secretsDir, "restic-s3", hostData.Backup.S3Environment},
		)
	}
	if hostData.Vault != nil {
		files = append(files,
			outputFile{secretsDir, "vault-role-id", hostData.Vault.RoleID},
			outputFile{secretsDir, "vault-secret-id", hostData.Vault.SecretID},
		)
	}

	paths := make([]string, 0, len(files))
	for _, file := range files {
		// The files are written asynchronously (a failed write fails the run): create the directory first.
		outputPath := filepath.Join(".", outputDir, filepath.FromSlash(file.dir))
		if err := os.MkdirAll(outputPath, dirPermissions); err != nil {
			return nil, err
		}
		paths = append(paths, filepath.Join(outputPath, file.name))

		scwUpload.WriteFileAndUpload(ctx, &storage.WriteFileAndUploadOptions{
			BucketID:    config.BucketID,
			BucketPath:  path.Join(config.BucketPath, file.dir),
			OutputPath:  outputPath,
			Name:        file.name,
			Content:     file.content,
			Labels:      config.CommonLabels(),
			Permissions: []os.FileMode{filePermissions},
		})
	}

	return paths, nil
}

// pruneKeys removes the files below outputs/keys that no host writes any more (a host disabled or removed, Coder or
// the Vault Agent turned off): ./host pushes a host's whole secrets directory. The bucket copies are resources and
// are deleted by Pulumi.
// written: The local paths of the files written in this run.
func pruneKeys(written map[string]bool) error {
	dir := filepath.Join(".", outputDir, "keys")
	root, err := os.OpenRoot(dir)
	if errors.Is(err, fs.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	defer root.Close()

	return fs.WalkDir(root.FS(), ".", func(p string, d fs.DirEntry, wErr error) error {
		if wErr != nil || d.IsDir() || written[filepath.Join(dir, filepath.FromSlash(p))] {
			return wErr
		}
		return root.Remove(p)
	})
}
