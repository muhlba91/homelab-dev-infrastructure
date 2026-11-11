package program_test

import (
	"errors"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	hostModel "github.com/muhlba91/homelab-dev-infrastructure/pkg/model/config/host"
	"github.com/muhlba91/homelab-dev-infrastructure/pkg/program"
	"github.com/muhlba91/homelab-dev-infrastructure/pkg/util"
	"github.com/muhlba91/homelab-dev-infrastructure/test/mocks"
)

// project is the Pulumi project (its name scopes the stack configuration).
const project = "homelab-dev-infrastructure"

// enabledLine matches a host file's switch.
var enabledLine = regexp.MustCompile(`(?m)^enabled: false$`)

// failingRoleID are the mocks with an AppRole role ID that cannot be read (Vault unreachable, say).
type failingRoleID struct{ mocks.Mocks }

// Call fails the role ID lookup and answers every other call as the mocks do.
// args: The function's token and arguments.
func (m failingRoleID) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	if args.Token == "vault:appRole/getAuthBackendRoleId:getAuthBackendRoleId" {
		return nil, errors.New("vault unreachable")
	}
	return m.Mocks.Call(args)
}

// setup prepares dir for a run of the program: the host files of assets/hosts and the host template (all of them
// enabled if enable is set), the stack configuration, and stale files below outputs/keys (returned).
func setup(t *testing.T, dir string, enable bool) []string {
	t.Helper()

	assets, err := filepath.Abs("../../assets")
	require.NoError(t, err)
	require.NoError(t, os.RemoveAll(filepath.Join(dir, "assets")))
	require.NoError(t, os.CopyFS(filepath.Join(dir, "assets"), os.DirFS(assets)))

	// The host template documents every field: rendered as a host too, so the whole template is checked.
	template, err := os.ReadFile(filepath.Join(dir, "assets", "templates", "host.yml"))
	require.NoError(t, err)
	require.NoError(t, os.WriteFile(filepath.Join(dir, "assets", "hosts", "host.yml"), template, 0o600))

	files, err := filepath.Glob(filepath.Join(dir, "assets", "hosts", "*.yml"))
	require.NoError(t, err)
	require.NotEmpty(t, files)
	if enable {
		for _, file := range files {
			content, rErr := os.ReadFile(file)
			require.NoError(t, rErr)
			require.NoError(t, os.WriteFile(file, enabledLine.ReplaceAll(content, []byte("enabled: true")), 0o600))
		}
	}

	t.Chdir(dir)
	t.Setenv("SCW_ORGANIZATION_ID", "mock-organization")
	t.Setenv("SCW_PROJECT_ID", "mock-project")
	t.Setenv("SCW_DEFAULT_REGION", "fr-par")
	t.Setenv(
		"PULUMI_CONFIG",
		`{"`+project+`:bucketId":"mock-bucket","`+project+`:backupBucketId":"mock-backup-bucket",`+
			`"`+project+`:zitadel":"{\"url\":\"https://id.example.org\",\"clientId\":\"mock-client\",`+
			`\"clientSecret\":\"mock-secret\"}"}`,
	)
	t.Setenv("PULUMI_CONFIG_SECRET_KEYS", `["`+project+`:zitadel"]`)
	// Files no host writes any more are removed (./host pushes the whole secrets directory).
	stale := []string{
		filepath.Join("outputs", "keys", "removed-host", "deploy-key"),
		filepath.Join("outputs", "keys", "hetzner-fra-dev-001", "secrets", "stale"),
	}
	for _, f := range stale {
		require.NoError(t, os.MkdirAll(filepath.Dir(f), 0o700))
		require.NoError(t, os.WriteFile(f, []byte("stale"), 0o600))
	}

	return stale
}

// render runs the program under mocks in dir (see setup) and checks the written files.
func render(t *testing.T, dir string, enable bool) {
	t.Helper()

	stale := setup(t, dir, enable)
	require.NoError(t, pulumi.RunErr(program.Run, pulumi.WithMocks(project, "test", mocks.Mocks{})))

	for _, f := range stale {
		assert.NoFileExists(t, f)
	}

	hosts, err := util.ParseHostsFromFiles("./assets/hosts")
	require.NoError(t, err)

	for _, host := range hosts {
		if enable {
			assert.True(t, host.IsEnabled(), host.Name)
		}
		assert.FileExists(t, filepath.Join("outputs", "hosts", host.Name, "vars.nix"))
		if host.IsEnabled() {
			assertKeys(t, host)
		} else {
			assert.NoDirExists(t, filepath.Join("outputs", "keys", host.Name))
		}
	}

	// The vars folder is the flake's Nix input: nothing but <host>/vars.nix.
	require.NoError(
		t,
		filepath.WalkDir(filepath.Join("outputs", "hosts"), func(path string, entry os.DirEntry, wErr error) error {
			if wErr == nil && !entry.IsDir() {
				assert.Equal(t, "vars.nix", entry.Name(), path)
			}
			return wErr
		}),
	)
}

// assertKeys checks the key and secret files of an enabled host: the ones every host gets, and the Coder admin
// password and the backup credentials exactly when the host runs Coder, the Vault Agent's login exactly when it runs
// the agent, Paseo's password exactly when it runs Paseo.
func assertKeys(t *testing.T, host *hostModel.Config) {
	t.Helper()

	keys := filepath.Join("outputs", "keys", host.Name)
	secrets := filepath.Join(keys, "secrets")
	assert.FileExists(t, filepath.Join(keys, "deploy-key"))
	assert.FileExists(t, filepath.Join(secrets, "ssh-host-key"))
	assert.FileExists(t, filepath.Join(secrets, "github-ssh-key"))

	for _, name := range []string{"coder-admin-password", "restic-password", "restic-s3"} {
		if host.UsesCoder() {
			assert.FileExists(t, filepath.Join(secrets, name))
		} else {
			assert.NoFileExists(t, filepath.Join(secrets, name))
		}
	}
	oidc := filepath.Join(secrets, "coder-oidc")
	if host.UsesCoderOIDC() {
		content, err := os.ReadFile(oidc)
		require.NoError(t, err)
		assert.Equal(t, "CODER_OIDC_CLIENT_SECRET=mock-secret\n", string(content))
	} else {
		assert.NoFileExists(t, oidc)
	}
	paseo := filepath.Join(secrets, "paseo-env")
	if host.UsesPaseo() {
		content, err := os.ReadFile(paseo)
		require.NoError(t, err)
		assert.Equal(t, "PASEO_PASSWORD=mock-password-password-paseo-"+host.Name+"-test\n", string(content))
	} else {
		assert.NoFileExists(t, paseo)
	}
	for _, name := range []string{"vault-role-id", "vault-secret-id"} {
		if host.UsesVault() {
			assert.FileExists(t, filepath.Join(secrets, name))
		} else {
			assert.NoFileExists(t, filepath.Join(secrets, name))
		}
	}
	if host.UsesVault() {
		content, err := os.ReadFile(filepath.Join(secrets, "vault-role-id"))
		require.NoError(t, err)
		assert.Equal(t, "mock-role-id", string(content))
	}
	vars, err := os.ReadFile(filepath.Join("outputs", "hosts", host.Name, "vars.nix"))
	require.NoError(t, err)
	assert.Equal(
		t,
		host.UsesCoder(),
		strings.Contains(
			string(vars),
			`repository = "s3:https://s3.fr-par.scw.cloud/mock-backup-bucket/dev/`+host.Name+`";`,
		),
		host.Name,
	)
	assert.Equal(t, host.UsesCoderOIDC(), strings.Contains(string(vars), `clientId = "mock-client";`), host.Name)
	assert.Equal(t, host.UsesPaseo(), strings.Contains(string(vars), "paseo = {\n      enable = true;"), host.Name)
	assert.NotContains(t, string(vars), "mock-secret", host.Name)
	assert.NotContains(t, string(vars), "mock-password", host.Name)
}

// TestRunAsIs renders the host files as they are (only enabled hosts get keys).
func TestRunAsIs(t *testing.T) {
	render(t, t.TempDir(), false)
}

// TestRunEnabled renders every host file enabled (keys and secrets). RENDER_DIR keeps the result for the flake's
// checks: `OUTPUTS=$RENDER_DIR/outputs ./host check` in nix/.
func TestRunEnabled(t *testing.T) {
	dir := os.Getenv("RENDER_DIR")
	if dir == "" {
		dir = t.TempDir()
	}
	require.NoError(t, os.MkdirAll(dir, 0o700))

	render(t, dir, true)
}

// TestRunFailsWithoutRoleID fails the run when a host's AppRole role ID cannot be read, instead of leaving out its
// file (Pulumi would delete the bucket copy and the next deploy remove the host's file).
func TestRunFailsWithoutRoleID(t *testing.T) {
	setup(t, t.TempDir(), true)

	err := pulumi.RunErr(program.Run, pulumi.WithMocks(project, "test", failingRoleID{}))
	require.ErrorContains(t, err, "vault unreachable")
}
