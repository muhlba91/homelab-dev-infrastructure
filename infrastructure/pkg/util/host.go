package util

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"maps"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"

	"github.com/rs/zerolog/log"
	"gopkg.in/yaml.v3"

	"github.com/muhlba91/homelab-dev-infrastructure/pkg/model/config/host"
)

// fileName matches a host file's name without its extension: an optional deploy order (digits and a dash), then
// the host name.
var fileName = regexp.MustCompile(`^(?:([0-9]+)-)?(.+)$`)

// hostName matches a valid host name: a hostname label of at most 30 characters (the longest derived name,
// dev-infrastructure-<host>-backup-<stack>, must fit Scaleway's 64-character IAM names).
var hostName = regexp.MustCompile(`^[a-z0-9]([a-z0-9-]{0,28}[a-z0-9])?$`)

// ParseHostsFromFiles reads the host files (*.yml, *.yaml) of a directory. A file is named after its host,
// optionally prefixed with its deploy order ([<order>-]<name>.yml); host names are unique.
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
		return fmt.Errorf("file name %q: the host name must be a hostname label of at most 30 characters", name)
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
	if lErr := checkValues(&r); lErr != nil {
		return nil, fmt.Errorf("%s: %w", path, lErr)
	}

	return &r, nil
}

// checkRequired rejects a missing required section: the template reads them unchecked.
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

// checkValues rejects values the template would render wrongly: empty required or set optional strings, out-of-range
// numbers, a missing Vault address, and empty lists whose omission changes the result (`trustedNetworks.v4: []`
// would open the host to the default networks).
// h: The host configuration.
func checkValues(h *host.Config) error {
	if err := checkStrings(h); err != nil {
		return err
	}
	if n := h.Network.V4.Netmask; n < 1 || n > 32 {
		return fmt.Errorf("network.v4.netmask %d: must be 1-32", n)
	}
	if v6 := h.Network.V6; v6 != nil && (v6.Netmask < 1 || v6.Netmask > 128) {
		return fmt.Errorf("network.v6.netmask %d: must be 1-128", v6.Netmask)
	}
	if uid := h.User.UID; uid < 1000 || uid > 59999 {
		return fmt.Errorf("user.uid %d: must be 1000-59999", uid)
	}
	if h.UsesVault() && h.Vault.Address == nil {
		return errors.New("vault.address is required when vault.enabled is true")
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

// checkStrings rejects empty strings: required ones, and optional ones that are set.
// h: The host configuration.
func checkStrings(h *host.Config) error {
	required := map[string]string{
		"hardware.profile":   h.Hardware.Profile,
		"hardware.disk":      h.Hardware.Disk,
		"network.domain":     h.Network.Domain,
		"network.mac":        h.Network.MAC,
		"network.interface":  h.Network.Interface,
		"network.v4.address": h.Network.V4.Address,
		"network.v4.gateway": h.Network.V4.Gateway,
		"user.name":          h.User.Name,
		"user.git.name":      h.User.Git.Name,
		"user.git.email":     h.User.Git.Email,
	}
	optional := map[string]*string{
		"network.managementAddress": h.Network.ManagementAddress,
	}
	if v6 := h.Network.V6; v6 != nil {
		required["network.v6.address"] = v6.Address
		optional["network.v6.gateway"] = v6.Gateway
	}
	if s := h.System; s != nil {
		optional["system.watchdog"] = s.Watchdog
		if s.GC != nil {
			optional["system.gc.olderThan"] = s.GC.OlderThan
		}
	}
	if c := h.Coder; c != nil {
		optional["coder.accessUrl"] = c.AccessURL
		optional["coder.wildcardAccessUrl"] = c.WildcardAccessURL
	}
	if v := h.Vault; v != nil {
		optional["vault.address"] = v.Address
	}
	for _, field := range slices.Sorted(maps.Keys(optional)) {
		if value := optional[field]; value != nil {
			required[field] = *value
		}
	}

	for _, field := range slices.Sorted(maps.Keys(required)) {
		if required[field] == "" {
			return fmt.Errorf("%s must not be empty", field)
		}
	}
	return nil
}
