# `./host dump <host>` (flake output `hostDump.<host>`): the evaluated parts of a host that
# matter for behaviour, as JSON. Diff two dumps to prove a refactor changes nothing (or exactly
# what was intended). `drv` alone answers "identical or not".
c:
let
  l = builtins;
  user = c.users.users.${c.dev.user.name};
in
{
  drv = c.system.build.toplevel.drvPath;
  nft = l.mapAttrs (_: t: t.family + "\n" + t.content) c.networking.nftables.tables;
  networkd = l.mapAttrs (_: u: u.text) c.systemd.network.units;
  fileSystems = l.mapAttrs (_: f: {
    inherit (f) device fsType neededForBoot;
  }) c.fileSystems;
  user = {
    inherit (user)
      uid
      group
      home
      linger
      subUidRanges
      subGidRanges
      extraGroups
      ;
  };
  git = c.programs.git.config;
  coder = {
    inherit (c.services.coder) enable;
    environment = c.systemd.services.coder.environment or { };
  };
  postgresql = {
    inherit (c.services.postgresql) enable dataDir identMap;
  };
  secrets = c.dev.secrets;
  secretsActivation = c.system.activationScripts.devSecrets.text or "";
}
