# Network (systemd-networkd): one NIC on the site LAN, renamed by its MAC, static addresses,
# the site router as gateway and resolver.
{ config, lib, ... }:
let
  net = config.dev.network;
  v6 = net.v6 != null;
  ra = v6 && net.v6.acceptRA;
in
{
  networking.useNetworkd = true;
  networking.useDHCP = false;
  assertions = [
    {
      assertion = !v6 || net.v6.acceptRA || net.v6.gateway != null;
      message = "dev.network.v6: without acceptRA, a gateway is needed for the IPv6 default route";
    }
  ];

  networking.nameservers = if net.nameservers == null then [ net.v4.gateway ] else net.nameservers;
  networking.search = [ config.dev.host.domain ];
  # Unicast DNS from the site router only: no LLMNR/mDNS name resolution on the LAN.
  services.resolved.settings.Resolve = {
    LLMNR = false;
    MulticastDNS = false;
  };

  systemd.network.links."10-lan" = {
    matchConfig.MACAddress = net.mac;
    linkConfig.Name = net.iface;
  };

  systemd.network.networks."10-lan" = {
    matchConfig.Name = net.iface;
    address = [ net.v4.address ] ++ lib.optional v6 net.v6.address;
    routes = [
      { Gateway = net.v4.gateway; }
    ]
    ++ lib.optional (v6 && net.v6.gateway != null) { Gateway = net.v6.gateway; };
    # Static addresses only. With acceptRA, the router advertisements bring the IPv6 default
    # route and the DNS server, never an address: no SLAAC, and no DHCPv6 client even though the
    # site routers set the managed flag (M=1).
    networkConfig.IPv6AcceptRA = ra;
    ipv6AcceptRAConfig = lib.mkIf ra {
      UseAutonomousPrefix = false;
      DHCPv6Client = false;
      UseDNS = true;
      UseDomains = false;
    };
    linkConfig.RequiredForOnline = "routable";
  };
}
