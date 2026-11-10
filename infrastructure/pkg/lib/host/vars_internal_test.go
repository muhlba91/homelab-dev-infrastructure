package host

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	hostModel "github.com/muhlba91/homelab-dev-infrastructure/pkg/model/config/host"
)

// testVarsHost returns a host configuration with the values the template must not get wrong.
func testVarsHost() *hostModel.Config {
	disabled := false
	accessURL := "https://coder.example.org"
	wildcardURL := "*.coder.example.org"
	return &hostModel.Config{
		Name:     "host-a",
		Hardware: &hostModel.HardwareConfig{Profile: "qemu", Disk: "/dev/sda"},
		Network: &hostModel.NetworkConfig{
			Domain:      "example.org",
			MAC:         "bc:24:11:00:00:01",
			Interface:   "lan0",
			V4:          &hostModel.StaticIPConfig{Address: "10.0.0.2", Netmask: 24, Gateway: "10.0.0.1"},
			V6:          &hostModel.StaticIPv6Config{Address: "fd00::2", Netmask: 64},
			Nameservers: []string{"10.0.0.53"},
		},
		User: &hostModel.UserConfig{
			Name: "user",
			UID:  1000,
			Git:  &hostModel.GitConfig{Name: `O"Brien ${x} \ y`, Email: "user@example.org"},
		},
		Coder: &hostModel.CoderConfig{Enabled: &disabled, AccessURL: &accessURL, WildcardAccessURL: &wildcardURL},
	}
}

// TestRenderVars checks false flags, optional values, composed addresses, escaping, and no keys for a disabled
// host.
func TestRenderVars(t *testing.T) {
	t.Chdir("../../..")

	vars, err := renderVars(&varsData{Host: testVarsHost(), DeployKeys: []string{"ssh-ed25519 AAAA a"}})
	require.NoError(t, err)

	for _, want := range []string{
		"enable = false;",
		`accessUrl = "https://coder.example.org";`,
		`wildcardAccessUrl = "*.coder.example.org";`,
		`address = "10.0.0.2";`, // mgmt.address defaults to the IPv4 address
		`address = "10.0.0.2/24";`,
		`address = "fd00::2/64";`,
		`"10.0.0.53"`,
		`name = "O\"Brien \${x} \\ y";`,
	} {
		assert.Contains(t, vars, want)
	}
	assert.NotContains(t, vars, "hostKey")
	assert.NotContains(t, vars, "githubKey")
	assert.NotContains(t, vars, "gateway = \"\"")
}

// TestNixString quotes strings and *string; anything else is an error.
func TestNixString(t *testing.T) {
	s := `a"b`
	for in, want := range map[any]string{"x": `"x"`, &s: `"a\"b"`} {
		got, err := nixString(in)
		require.NoError(t, err)
		assert.Equal(t, want, got)
	}
	_, err := nixString(1)
	require.Error(t, err)
}
