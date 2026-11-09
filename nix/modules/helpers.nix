# Small pure helpers shared by the modules (`dlib` module argument).
{ lib, ... }:
{
  _module.args.dlib = {
    # Address of a CIDR ("10.100.60.1/16" -> "10.100.60.1").
    addr = cidr: builtins.head (lib.splitString "/" cidr);
    # An nftables set literal ("{ a, b }").
    nftSet = l: "{ ${lib.concatStringsSep ", " l} }";
  };
}
