package util_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"gopkg.in/yaml.v3"

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
	require.ErrorContains(t, err, "does not match the file name")
}

// TestParseHostsDuplicate rejects a host defined in two files.
func TestParseHostsDuplicate(t *testing.T) {
	_, err := util.ParseHostsFromFiles(writeHosts(t, map[string]string{
		"010-host-a.yml": "host-a",
		"020-host-a.yml": "host-a",
	}))
	require.ErrorContains(t, err, "defined twice")
}

// TestParseHostsNoName rejects a file named only by its extension.
func TestParseHostsNoName(t *testing.T) {
	for _, file := range []string{".yml", ".yaml"} {
		_, err := util.ParseHostsFromFiles(writeHosts(t, map[string]string{file: "host-a"}))
		require.ErrorContains(t, err, "hostname label", file)
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
	for _, name := range []string{"..", "Host-A", "host_a", "-host", "a-host-name-of-thirty-one-chars"} {
		_, err := util.ParseHostsFromFiles(writeHost(t, name+".yml", "name: "+name+"\n"+required))
		require.ErrorContains(t, err, "hostname label", name)
	}
}

// TestParseHostsMultipleDocuments rejects a file with a second YAML document.
func TestParseHostsMultipleDocuments(t *testing.T) {
	_, err := util.ParseHostsFromFiles(writeHost(t, "host-a.yml", "name: host-a\n"+required+"---\nenabled: true\n"))
	require.ErrorContains(t, err, "more than one YAML document")
}

// TestParseHostsEmptyLists rejects empty lists that would render like omitted ones (the defaults instead of none).
func TestParseHostsEmptyLists(t *testing.T) {
	for name, network := range map[string]string{
		"nameservers": "nameservers: []\n",
		"trusted v4":  "trustedNetworks:\n    v4: []\n",
		"trusted v6":  "trustedNetworks:\n    v6: []\n",
	} {
		_, err := util.ParseHostsFromFiles(writeHost(t, "host-a.yml", "name: host-a\n"+required+"  "+network))
		require.ErrorContains(t, err, "must not be empty", name)
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

// TestParseHostsValues rejects values the template would render wrongly; an empty trustedPorts is valid.
func TestParseHostsValues(t *testing.T) {
	for want, change := range map[string]struct {
		path  string
		value any
	}{
		"network.domain must not be empty":   {"network.domain", ""},
		"network.v4.netmask 0: must be 1-32": {"network.v4.netmask", nil},
		"coder.accessUrl must not be empty":  {"coder.accessUrl", ""},
		"user.uid 999: must be 1000-59999":   {"user.uid", 999},
		"vault.address is required":          {"vault.enabled", true},
		"coder.oidc needs an https":          {"coder", map[string]any{"enabled": true, "oidc": true}},
		"user.dotfiles \"git@x\": must be":   {"user.dotfiles", "git@x"},
		"field unknown not found":            {"unknown", 1},
	} {
		_, err := util.ParseHostsFromFiles(writeHost(t, "host-a.yml", withValue(t, change.path, change.value)))
		require.ErrorContains(t, err, want, want)
	}

	_, err := util.ParseHostsFromFiles(writeHost(t, "host-a.yml", withValue(t, "docker.trustedPorts", []string{})))
	require.NoError(t, err)
}

// withValue returns the valid host file host-a with one value set (nil: removed); path is dot-separated.
func withValue(t *testing.T, path string, value any) string {
	t.Helper()

	var file map[string]any
	require.NoError(t, yaml.Unmarshal([]byte("name: host-a\n"+required), &file))
	keys := strings.Split(path, ".")
	node := file
	for _, key := range keys[:len(keys)-1] {
		child, ok := node[key].(map[string]any)
		if !ok {
			child = map[string]any{}
			node[key] = child
		}
		node = child
	}
	if value == nil {
		delete(node, keys[len(keys)-1])
	} else {
		node[keys[len(keys)-1]] = value
	}

	out, err := yaml.Marshal(file)
	require.NoError(t, err)
	return string(out)
}
