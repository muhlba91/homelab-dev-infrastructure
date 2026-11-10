# Host data without nixpkgs: a host's dev.* values (cheap: only the vars schema) and, for a folder
# of host data (one directory per host, holding its vars.nix), the list and targets ./host uses.
{ lib }:
let
  cfg =
    vars:
    (lib.evalModules {
      modules = [
        ../modules/options
        vars
      ];
      specialArgs = { inherit lib; };
    }).config.dev;
in
{
  inherit cfg;

  of =
    dir:
    let
      names = lib.attrNames (lib.filterAttrs (_: t: t == "directory") (builtins.readDir dir));
      cfgOf = host: cfg (dir + "/${host}/vars.nix");
      # Hosts without a deploy order last; ties by name (the sort is stable).
      rank =
        host:
        let
          order = (cfgOf host).meta.deployOrder;
        in
        if order == null then 9223372036854775807 else order;
      ordered = lib.sortOn rank names;
      deployable = lib.filter (h: (cfgOf h).meta.deployable) ordered;
    in
    {
      inherit names deployable cfgOf;
      # `./host hosts`: "<name> deployable=<bool> automated=<bool> mgmt=<address>" per line, in
      # deploy order. automated = deployable and meta.deployAutomated: CI deploys exactly these.
      list = lib.concatMapStrings (
        host:
        let
          h = cfgOf host;
        in
        "${host} deployable=${lib.boolToString h.meta.deployable} automated=${
          lib.boolToString (h.meta.deployable && h.meta.deployAutomated)
        } mgmt=${h.mgmt.address}\n"
      ) ordered;
      # `./host`'s target: "<mgmt address>[ <host key>]" (with a pinned key: a known_hosts line).
      target = lib.genAttrs deployable (
        host:
        let
          inherit (cfgOf host) mgmt;
        in
        toString ([ mgmt.address ] ++ lib.optional (mgmt.hostKey != null) mgmt.hostKey)
      );
    };
}
