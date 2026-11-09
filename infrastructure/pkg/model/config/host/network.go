package host

// NetworkConfig defines the network configuration for a host: one NIC on the site LAN with static addresses.
type NetworkConfig struct {
	// Domain is the DNS domain of the host (the site's domain).
	Domain string `yaml:"domain"`
	// MAC is the MAC address of the NIC: the NIC is renamed by it (a wrong MAC locks the host out).
	MAC string `yaml:"mac"`
	// Interface is the name the NIC gets.
	Interface string `yaml:"interface"`
	// V4 is the static IPv4 configuration of the NIC.
	V4 *StaticIPConfig `yaml:"v4"`
	// V6 is the static IPv6 configuration of the NIC (optional).
	V6 *StaticIPv6Config `yaml:"v6,omitempty"`
	// Nameservers are the DNS servers of the host (default: the IPv4 gateway, the site router).
	Nameservers []string `yaml:"nameservers,omitempty"`
	// ManagementAddress is the address (or name) used to manage the host (default: the IPv4 address).
	ManagementAddress *string `yaml:"managementAddress,omitempty"`
	// TrustedNetworks are the networks that may reach the host's services (SSH, Coder) (default: the Nix defaults).
	TrustedNetworks *TrustedNetworksConfig `yaml:"trustedNetworks,omitempty"`
}

// StaticIPConfig defines a static address and its gateway.
type StaticIPConfig struct {
	// Address is the address of the host (without prefix length).
	Address string `yaml:"address"`
	// Netmask is the prefix length of the address.
	Netmask int `yaml:"netmask"`
	// Gateway is the default gateway (the site router).
	Gateway string `yaml:"gateway"`
}

// StaticIPv6Config defines a static IPv6 address; the default route can come from the router advertisements.
type StaticIPv6Config struct {
	// Address is the address of the host (without prefix length).
	Address string `yaml:"address"`
	// Netmask is the prefix length of the address.
	Netmask int `yaml:"netmask"`
	// Gateway is the default gateway (default: the router advertisements; one of both is needed).
	Gateway *string `yaml:"gateway,omitempty"`
	// AcceptRA indicates whether the host listens to router advertisements (default true): the default route and the
	// DNS server, never an address (no SLAAC, no DHCPv6).
	AcceptRA *bool `yaml:"acceptRA,omitempty"`
}

// TrustedNetworksConfig defines the trusted networks for a host.
type TrustedNetworksConfig struct {
	// V4 is the list of trusted IPv4 networks.
	V4 []string `yaml:"v4,omitempty"`
	// V6 is the list of trusted IPv6 networks.
	V6 []string `yaml:"v6,omitempty"`
}
