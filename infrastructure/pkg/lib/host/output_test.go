package host_test

import (
	"strings"
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

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
			data, hErr := host.ConfigureHost(ctx, h, []string{mocks.PublicKey})
			require.NoError(t, hErr)

			output := host.Output(h, data)
			keys, ok := output["keys"].(pulumi.Map)
			require.True(t, ok)
			for _, name := range []string{"deploy", "host", "github"} {
				key, kOk := keys[name].(pulumi.Map)
				require.True(t, kOk, name)
				public, pOk := key["public"].(pulumi.StringOutput)
				require.True(t, pOk, name)
				public.ApplyT(func(v string) error {
					assert.Equal(t, mocks.PublicKey, v, name)
					assert.False(t, strings.HasSuffix(v, "\n"), name)
					return nil
				})
			}

			_, hasCoder := output["coder"]
			assert.Equal(t, coder, hasCoder)
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
		data, hErr := host.ConfigureHost(ctx, h, []string{mocks.PublicKey})
		require.NoError(t, hErr)

		assert.Empty(t, host.Output(h, data))
		return nil
	}, pulumi.WithMocks("project", "test", mocks.Mocks{}))
	require.NoError(t, err)
}
