package program_test

import (
	"os"
	"path/filepath"
	"regexp"
	"testing"

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

// render runs the program under mocks in dir, with the host files of assets/hosts and the host template (all of them
// enabled if enable is set) and checks the written files.
func render(t *testing.T, dir string, enable bool) {
	t.Helper()

	assets, err := filepath.Abs("../../assets")
	require.NoError(t, err)
	require.NoError(t, os.RemoveAll(filepath.Join(dir, "assets")))
	require.NoError(t, os.CopyFS(filepath.Join(dir, "assets"), os.DirFS(assets)))

	// The host template sets every field: rendered as a host too, so the whole template is checked.
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
	t.Setenv("PULUMI_CONFIG", `{"`+project+`:bucketId":"mock-bucket"}`)
	require.NoError(t, pulumi.RunErr(program.Run, pulumi.WithMocks(project, "test", mocks.Mocks{})))

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
// password exactly when the host runs Coder.
func assertKeys(t *testing.T, host *hostModel.Config) {
	t.Helper()

	keys := filepath.Join("outputs", "keys", host.Name)
	secrets := filepath.Join(keys, "secrets")
	assert.FileExists(t, filepath.Join(keys, "deploy-key"))
	assert.FileExists(t, filepath.Join(secrets, "ssh-host-key"))
	assert.FileExists(t, filepath.Join(secrets, "github-ssh-key"))

	if host.UsesCoder() {
		assert.FileExists(t, filepath.Join(secrets, "coder-admin-password"))
	} else {
		assert.NoFileExists(t, filepath.Join(secrets, "coder-admin-password"))
	}
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
