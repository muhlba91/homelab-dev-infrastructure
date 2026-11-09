package util

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"

	"github.com/rs/zerolog/log"
	"gopkg.in/yaml.v3"

	"github.com/muhlba91/homelab-dev-infrastructure/pkg/model/config/host"
)

// fileName matches a host file's name without its extension: an optional deploy order (digits and a dash), then
// the host name.
var fileName = regexp.MustCompile(`^(?:([0-9]+)-)?(.+)$`)

// hostName matches a valid host name: a hostname label.
var hostName = regexp.MustCompile(`^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$`)

// ParseHostsFromFiles reads the host configuration files (*.yml, *.yaml) from the specified directory.
// Other entries (e.g. .gitkeep) are skipped. A file must be named after its host, optionally prefixed with its deploy
// order ([<order>-]<name>.yml), and every host name must be unique.
// dir: The directory of the host configuration files.
func ParseHostsFromFiles(dir string) ([]*host.Config, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		log.Err(err).Msgf("[host] error reading host configuration directory: %s", dir)
		return nil, err
	}

	var hosts []*host.Config
	seen := make(map[string]string)
	for _, e := range entries {
		ext := filepath.Ext(e.Name())
		if !e.Type().IsRegular() || (ext != ".yml" && ext != ".yaml") {
			continue
		}

		full := filepath.Join(dir, e.Name())
		r, lErr := loadHostFile(full, strings.TrimSuffix(e.Name(), ext))
		if lErr != nil {
			return nil, lErr
		}
		if other, ok := seen[r.Name]; ok {
			dErr := fmt.Errorf("host %q is defined twice: %s and %s", r.Name, other, full)
			log.Err(dErr).Msgf("[host] error validating host configuration file: %s", full)
			return nil, dErr
		}
		seen[r.Name] = full
		hosts = append(hosts, r)
	}

	return hosts, nil
}

// loadHostFile reads one host file and applies its name: the host name must match it, and its prefix (if any) is
// the host's deploy order.
// path: The path of the file.
// name: The file name without its extension ([<order>-]<name>).
func loadHostFile(path string, name string) (*host.Config, error) {
	r, err := parseHostFile(path)
	if err != nil {
		return nil, err
	}

	if nErr := applyFileName(r, name); nErr != nil {
		log.Err(nErr).Msgf("[host] error validating host configuration file: %s", path)
		return nil, nErr
	}

	return r, nil
}

// applyFileName checks the file name of a host against its name and sets the deploy order from its prefix.
// r: The host configuration.
// name: The file name without its extension ([<order>-]<name>).
func applyFileName(r *host.Config, name string) error {
	parts := fileName.FindStringSubmatch(name)
	if parts == nil || !hostName.MatchString(parts[2]) {
		return fmt.Errorf("file name %q: the host name must be a hostname label", name)
	}
	if r.Name != parts[2] {
		return fmt.Errorf("host name %q does not match the file name %q", r.Name, name)
	}
	if parts[1] == "" {
		return nil
	}

	order, err := strconv.Atoi(parts[1])
	if err != nil {
		return fmt.Errorf("deploy order of %q: %w", name, err)
	}
	r.DeployOrder = &order

	return nil
}

// parseHostFile decodes one host configuration file. Unknown keys are errors, so a typo cannot silently
// leave a value at its default.
// path: The path of the file.
func parseHostFile(path string) (*host.Config, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		log.Err(err).Msgf("[host] error reading host configuration file: %s", path)
		return nil, err
	}

	var r host.Config
	dec := yaml.NewDecoder(bytes.NewReader(b))
	dec.KnownFields(true)
	if yErr := dec.Decode(&r); yErr != nil {
		log.Err(yErr).Msgf("[host] error parsing host configuration file: %s", path)
		return nil, fmt.Errorf("%s: %w", path, yErr)
	}
	if !errors.Is(dec.Decode(new(any)), io.EOF) {
		return nil, fmt.Errorf("%s: more than one YAML document", path)
	}
	if qErr := checkRequired(&r); qErr != nil {
		return nil, fmt.Errorf("%s: %w", path, qErr)
	}
	if lErr := checkLists(&r); lErr != nil {
		return nil, fmt.Errorf("%s: %w", path, lErr)
	}

	return &r, nil
}

// checkRequired rejects a host file without one of the required sections: the template and the stack output read
// them without a check, so a missing one would fail late (or panic) instead of naming the file.
// h: The host configuration.
func checkRequired(h *host.Config) error {
	switch {
	case h.Hardware == nil:
		return errors.New("hardware is required")
	case h.Network == nil:
		return errors.New("network is required")
	case h.Network.V4 == nil:
		return errors.New("network.v4 is required")
	case h.User == nil:
		return errors.New("user is required")
	case h.User.Git == nil:
		return errors.New("user.git is required")
	}
	return nil
}

// checkLists rejects empty lists: the template renders them like omitted ones, so the Nix default would apply
// (`trustedNetworks.v4: []` would open the host to the default networks instead of closing it).
// h: The host configuration.
func checkLists(h *host.Config) error {
	if h.Docker != nil && h.Docker.TrustedPorts != nil && len(h.Docker.TrustedPorts) == 0 {
		return errors.New("docker.trustedPorts must not be empty (omit it for none)")
	}
	if h.Network == nil {
		return nil
	}
	if h.Network.Nameservers != nil && len(h.Network.Nameservers) == 0 {
		return errors.New("network.nameservers must not be empty (omit it for the IPv4 gateway)")
	}
	if t := h.Network.TrustedNetworks; t != nil &&
		((t.V4 != nil && len(t.V4) == 0) || (t.V6 != nil && len(t.V6) == 0)) {
		return errors.New("network.trustedNetworks: v4 and v6 must not be empty (omit them for the defaults)")
	}
	return nil
}
