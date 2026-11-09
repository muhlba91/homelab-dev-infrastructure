package util_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/muhlba91/homelab-dev-infrastructure/pkg/util"
)

// required is the rest of a valid host file: the required sections (the network last, so tests can extend it).
const required = "hardware:\n  profile: qemu\n  disk: /dev/sda\n" +
	"user:\n  name: user\n  uid: 1000\n  git:\n    name: User\n    email: user@example.org\n" +
	"network:\n  domain: example.org\n  mac: bc:24:11:00:00:01\n  interface: lan0\n" +
	"  v4:\n    address: 10.0.0.2\n    netmask: 24\n    gateway: 10.0.0.1\n"

// writeHosts writes one host file per entry (file name -> host name) into a new directory.
func writeHosts(t *testing.T, files map[string]string) string {
	t.Helper()

	dir := t.TempDir()
	for file, name := range files {
		require.NoError(t, os.WriteFile(filepath.Join(dir, file), []byte("name: "+name+"\n"+required), 0o600))
	}
	return dir
}

// TestParseHostsDeployOrder reads the deploy order from the file name prefix; a file without one has none.
func TestParseHostsDeployOrder(t *testing.T) {
	hosts, err := util.ParseHostsFromFiles(writeHosts(t, map[string]string{
		"010-host-a.yml": "host-a",
		"host-b.yaml":    "host-b",
	}))
	require.NoError(t, err)
	require.Len(t, hosts, 2)

	assert.Equal(t, "host-a", hosts[0].Name)
	require.NotNil(t, hosts[0].DeployOrder)
	assert.Equal(t, 10, *hosts[0].DeployOrder)
	assert.Equal(t, "host-b", hosts[1].Name)
	assert.Nil(t, hosts[1].DeployOrder)
}

// TestParseHostsNameMismatch rejects a file whose name (without the prefix) is not its host's name.
func TestParseHostsNameMismatch(t *testing.T) {
	_, err := util.ParseHostsFromFiles(writeHosts(t, map[string]string{"010-host-a.yml": "host-b"}))
	require.Error(t, err)
}

// TestParseHostsDuplicate rejects a host defined in two files.
func TestParseHostsDuplicate(t *testing.T) {
	_, err := util.ParseHostsFromFiles(writeHosts(t, map[string]string{
		"010-host-a.yml": "host-a",
		"020-host-a.yml": "host-a",
	}))
	require.Error(t, err)
}

// TestParseHostsNoName rejects a file named only by its extension.
func TestParseHostsNoName(t *testing.T) {
	for _, file := range []string{".yml", ".yaml"} {
		_, err := util.ParseHostsFromFiles(writeHosts(t, map[string]string{file: "host-a"}))
		require.Error(t, err, file)
	}
}

// writeHost writes one host file with the given content into a new directory.
func writeHost(t *testing.T, file, content string) string {
	t.Helper()

	dir := t.TempDir()
	require.NoError(t, os.WriteFile(filepath.Join(dir, file), []byte(content), 0o600))
	return dir
}

// TestParseHostsInvalidName rejects host names that are not hostname labels.
func TestParseHostsInvalidName(t *testing.T) {
	for _, name := range []string{"..", "Host-A", "host_a", "-host"} {
		_, err := util.ParseHostsFromFiles(writeHost(t, name+".yml", "name: "+name+"\n"+required))
		require.Error(t, err, name)
	}
}

// TestParseHostsMultipleDocuments rejects a file with a second YAML document.
func TestParseHostsMultipleDocuments(t *testing.T) {
	_, err := util.ParseHostsFromFiles(writeHost(t, "host-a.yml", "name: host-a\n"+required+"---\nenabled: true\n"))
	require.Error(t, err)
}

// TestParseHostsEmptyLists rejects empty lists that would render like omitted ones (the defaults instead of none).
func TestParseHostsEmptyLists(t *testing.T) {
	for name, network := range map[string]string{
		"nameservers": "nameservers: []\n",
		"trusted v4":  "trustedNetworks:\n    v4: []\n",
		"trusted v6":  "trustedNetworks:\n    v6: []\n",
	} {
		_, err := util.ParseHostsFromFiles(writeHost(t, "host-a.yml", "name: host-a\n"+required+"  "+network))
		require.Error(t, err, name)
	}

	_, err := util.ParseHostsFromFiles(
		writeHost(t, "host-a.yml", "name: host-a\n"+required+"  trustedNetworks:\n    v4: [10.0.0.0/8]\n"),
	)
	require.NoError(t, err)
}

// TestParseHostsRequired rejects a host file without one of the required sections.
func TestParseHostsRequired(t *testing.T) {
	for name, content := range map[string]string{
		"hardware":   "user:\n  name: u\n  uid: 1000\n  git:\n    name: U\n    email: u@example.org\nnetwork:\n  v4:\n    address: 10.0.0.2\n",
		"network":    "hardware:\n  profile: qemu\nuser:\n  name: u\n  uid: 1000\n  git:\n    name: U\n    email: u@example.org\n",
		"network.v4": "hardware:\n  profile: qemu\nnetwork:\n  domain: example.org\nuser:\n  name: u\n  uid: 1000\n  git:\n    name: U\n    email: u@example.org\n",
		"user":       "hardware:\n  profile: qemu\nnetwork:\n  v4:\n    address: 10.0.0.2\n",
		"user.git":   "hardware:\n  profile: qemu\nnetwork:\n  v4:\n    address: 10.0.0.2\nuser:\n  name: u\n  uid: 1000\n",
	} {
		_, err := util.ParseHostsFromFiles(writeHost(t, "host-a.yml", "name: host-a\n"+content))
		require.ErrorContains(t, err, name+" is required", name)
	}
}
