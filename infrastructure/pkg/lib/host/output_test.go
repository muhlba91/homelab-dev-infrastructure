package host_test

import (
	"strings"
	"sync"
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/muhlba91/homelab-dev-infrastructure/pkg/lib/config"
	"github.com/muhlba91/homelab-dev-infrastructure/pkg/lib/host"
	hostModel "github.com/muhlba91/homelab-dev-infrastructure/pkg/model/config/host"
	"github.com/muhlba91/homelab-dev-infrastructure/test/mocks"
)

// testHost returns an enabled host configuration with or without Coder.
func testHost(coder bool) *hostModel.Config {
	enabled := true
	return &hostModel.Config{
		Name:     "host-a",
		Enabled:  &enabled,
		Hardware: &hostModel.HardwareConfig{Profile: "qemu", Disk: "/dev/sda"},
		Network: &hostModel.NetworkConfig{
			Domain:    "example.org",
			MAC:       "bc:24:11:00:00:01",
			Interface: "lan0",
			V4:        &hostModel.StaticIPConfig{Address: "10.0.0.2", Netmask: 24, Gateway: "10.0.0.1"},
		},
		User: &hostModel.UserConfig{
			Name: "user",
			UID:  1000,
			Git:  &hostModel.GitConfig{Name: "User", Email: "user@example.org"},
		},
		Coder: &hostModel.CoderConfig{Enabled: &coder},
	}
}

// TestOutput checks the structure of a host's stack output: the public keys (plain, without a trailing newline)
// and Coder's admin only for a host with Coder.
func TestOutput(t *testing.T) {
	// vars.nix is rendered from ./assets.
	t.Chdir("../../..")
	for _, coder := range []bool{false, true} {
		err := pulumi.RunErr(func(ctx *pulumi.Context) error {
			h := testHost(coder)
			data, hErr := host.ConfigureHost(ctx, h, []string{mocks.PublicKey}, nil)
			require.NoError(t, hErr)

			output := host.Output(h, data)
			keys, ok := output["keys"].(pulumi.Map)
			require.True(t, ok)
			var wg sync.WaitGroup
			for _, name := range []string{"deploy", "host", "github"} {
				key, kOk := keys[name].(pulumi.Map)
				require.True(t, kOk, name)
				public, pOk := key["public"].(pulumi.StringOutput)
				require.True(t, pOk, name)
				wg.Add(1)
				public.ApplyT(func(v string) error {
					defer wg.Done()
					assert.Equal(t, mocks.PublicKey, v, name)
					assert.False(t, strings.HasSuffix(v, "\n"), name)
					return nil
				})
			}
			wg.Wait()

			coderOutput, hasCoder := output["coder"].(pulumi.Map)
			assert.Equal(t, coder, hasCoder)
			if hasCoder {
				admin, aOk := coderOutput["admin"].(pulumi.Output)
				require.True(t, aOk)
				assert.True(t, pulumi.IsSecret(admin))
			}
			return nil
		}, pulumi.WithMocks("project", "test", mocks.Mocks{}))
		require.NoError(t, err)
	}
}

// TestOutputDisabled checks that a disabled host has an empty stack output.
func TestOutputDisabled(t *testing.T) {
	t.Chdir("../../..")
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		h := testHost(true)
		disabled := false
		h.Enabled = &disabled
		data, hErr := host.ConfigureHost(ctx, h, []string{mocks.PublicKey}, nil)
		require.NoError(t, hErr)

		assert.Empty(t, host.Output(h, data))
		return nil
	}, pulumi.WithMocks("project", "test", mocks.Mocks{}))
	require.NoError(t, err)
}

// TestSecrets checks that the generated credentials are Pulumi secrets (never plain in the state or logs).
func TestSecrets(t *testing.T) {
	t.Chdir("../../..")
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		h := testHost(true)
		enabled := true
		address := "https://vault.example.org"
		h.Vault = &hostModel.VaultConfig{Enabled: &enabled, Address: &address}
		accessURL := "https://coder.example.org"
		h.Coder.AccessURL, h.Coder.OIDC = &accessURL, &enabled
		provider := &config.OIDCConfig{URL: "https://id.example.org", ClientID: "id", ClientSecret: "secret"}
		data, hErr := host.ConfigureHost(ctx, h, []string{mocks.PublicKey}, provider)
		require.NoError(t, hErr)

		for name, value := range map[string]pulumi.Output{
			"coder admin password": *data.CoderAdminPassword,
			"coder oidc":           *data.CoderOIDC,
			"restic password":      data.Backup.Password,
			"restic s3":            data.Backup.S3Environment,
			"vault role id":        data.Vault.RoleID,
			"vault secret id":      data.Vault.SecretID,
		} {
			assert.True(t, pulumi.IsSecret(value), name)
		}
		return nil
	}, pulumi.WithMocks("project", "test", mocks.Mocks{}))
	require.NoError(t, err)
}

// TestOIDCNeedsProvider fails a host with coder.oidc when the stack config zitadel is missing.
func TestOIDCNeedsProvider(t *testing.T) {
	t.Chdir("../../..")
	err := pulumi.RunErr(func(ctx *pulumi.Context) error {
		h := testHost(true)
		enabled := true
		h.Coder.OIDC = &enabled
		_, hErr := host.ConfigureHost(ctx, h, []string{mocks.PublicKey}, nil)
		require.ErrorContains(t, hErr, "coder.oidc needs the stack config zitadel")
		return nil
	}, pulumi.WithMocks("project", "test", mocks.Mocks{}))
	require.NoError(t, err)
}
