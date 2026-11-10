package host

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	hostModel "github.com/muhlba91/homelab-dev-infrastructure/pkg/model/config/host"
)

// TestRenderVars checks values the template must not drop: false flags, the Coder URLs, and no keys for a
// disabled host.
func TestRenderVars(t *testing.T) {
	t.Chdir("../../..")

	disabled := false
	accessURL := "https://coder.example.org"
	wildcardURL := "*.coder.example.org"
	h := &hostModel.Config{
		Name:     "host-a",
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
		Coder: &hostModel.CoderConfig{Enabled: &disabled, AccessURL: &accessURL, WildcardAccessURL: &wildcardURL},
	}

	vars, err := renderVars(&varsData{Host: h, DeployKeys: []string{"ssh-ed25519 AAAA a"}, UserKeys: []string{}})
	require.NoError(t, err)

	assert.Contains(t, vars, "enable = false;")
	assert.Contains(t, vars, `accessUrl = "https://coder.example.org";`)
	assert.Contains(t, vars, `wildcardAccessUrl = "*.coder.example.org";`)
	assert.NotContains(t, vars, "hostKey")
	assert.NotContains(t, vars, "githubKey")
}
