# Firewall (nftables, NixOS firewall): default deny inbound; SSH (and Coder, when enabled) only
# from the trusted networks. Outbound is open. The site router filters first; this is the second
# layer.
{
  config,
  lib,
  dlib,
  ...
}:
let
  cfg = config.dev;
  ports = [ 22 ] ++ lib.optional cfg.coder.enable 3000;
  rule = family: nets: ''
    ${family} saddr ${dlib.nftSet nets} tcp dport ${dlib.nftSet (map toString ports)} accept
  '';
in
{
  networking.nftables.enable = true;
  networking.firewall = {
    enable = true;
    allowPing = true;
    extraInputRules =
      lib.optionalString (cfg.trusted.v4 != [ ]) (rule "ip" cfg.trusted.v4)
      + lib.optionalString (cfg.trusted.v6 != [ ]) (rule "ip6" cfg.trusted.v6);
  };
}
