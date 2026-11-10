# Vars schema: the network (one NIC on the site LAN, static addresses).
{ lib, ... }:
let
  inherit (lib) types;
  inherit (import ./types.nix { inherit lib; })
    str
    bool
    nullable
    typed
    ip4
    ip6
    cidr4
    cidr6
    mac
    ;
in
{
  options.dev.network = {
    mac = typed mac "MAC address of the NIC: it is renamed by it (a wrong MAC locks the host out).";
    iface = str "Name the NIC gets (e.g. `lan0`).";
    v4 = {
      address = typed cidr4 "Static IPv4 address with prefix length.";
      gateway = typed ip4 "IPv4 default gateway (the site router).";
    };
    v6 = nullable (types.submodule {
      options = {
        address = typed cidr6 "Static IPv6 address with prefix length.";
        gateway = nullable ip6 "IPv6 default gateway (null: from the router advertisements).";
        acceptRA = bool true ''
          Listen to router advertisements: the default route and the DNS server (RDNSS), never an
          address (no SLAAC, no DHCPv6 even if the router sets the managed flag).
        '';
      };
    }) "Static IPv6 configuration (null: IPv4 only).";
    nameservers = nullable (types.listOf (types.either ip4 ip6)) "DNS servers (null: the IPv4 gateway, the site router's resolver).";
  };
}
