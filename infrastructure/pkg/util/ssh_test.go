package util_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/muhlba91/homelab-dev-infrastructure/pkg/util"
	"github.com/muhlba91/homelab-dev-infrastructure/test/mocks"
)

// writeFiles writes the given files (name -> content) into a new directory.
func writeFiles(t *testing.T, files map[string]string) string {
	t.Helper()

	dir := t.TempDir()
	for name, content := range files {
		require.NoError(t, os.WriteFile(filepath.Join(dir, name), []byte(content), 0o600))
	}
	return dir
}

// TestParseSSHKeys reads every key line of the *.pub files; comments, blank lines and other files are skipped.
func TestParseSSHKeys(t *testing.T) {
	keys, err := util.ParseSSHKeysFromFiles(writeFiles(t, map[string]string{
		"a.pub":   "# comment\n\n" + mocks.PublicKey + "\n",
		"b.txt":   "not a key\n",
		"c.pub":   "  " + mocks.PublicKey + "  \n",
		"d.pub.x": "not a key\n",
	}))
	require.NoError(t, err)
	assert.Equal(t, []string{mocks.PublicKey, mocks.PublicKey}, keys)
}

// TestParseSSHKeysInvalid names the file and line of an invalid key.
func TestParseSSHKeysInvalid(t *testing.T) {
	_, err := util.ParseSSHKeysFromFiles(writeFiles(t, map[string]string{"a.pub": mocks.PublicKey + "\nnot a key\n"}))
	require.ErrorContains(t, err, "a.pub:2: invalid public key")
}

// TestParseSSHKeysNone rejects a directory without keys: deploys would be locked out.
func TestParseSSHKeysNone(t *testing.T) {
	_, err := util.ParseSSHKeysFromFiles(writeFiles(t, map[string]string{"a.pub": "# only a comment\n"}))
	require.ErrorContains(t, err, "no public keys found")
}
