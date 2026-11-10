# Default-deny inbound (nftables): SSH, Coder and docker.trustedPorts only from the trusted
# networks; outbound open. The site router is the first layer, this the second.
{
  config,
  lib,
  dlib,
  ...
}:
let
  cfg = config.dev;
  ports = [
    "22"
  ]
  ++ lib.optional cfg.coder.enable (toString cfg.coder.port)
  ++ lib.optionals cfg.docker.enable cfg.docker.trustedPorts;
  rule = family: nets: ''
    ${family} saddr ${dlib.nftSet nets} tcp dport ${dlib.nftSet ports} accept
  '';
in
{
  networking.nftables.enable = true;
  networking.firewall = {
    enable = true;
    extraInputRules =
      lib.optionalString (cfg.trusted.v4 != [ ]) (rule "ip" cfg.trusted.v4)
      + lib.optionalString (cfg.trusted.v6 != [ ]) (rule "ip6" cfg.trusted.v6);
  };
}
