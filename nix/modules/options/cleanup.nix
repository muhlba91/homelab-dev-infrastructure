# Vars schema: the regular cleanup of what builds and agents pile up in the user's home.
{ lib, ... }:
let
  inherit (lib) types;
  inherit (import ./types.nix { inherit lib; })
    bool
    strD
    typedD
    ;
  # A path relative to the home: no leading '/', no empty, '.' or '..' segment (`.` would clear the
  # whole home), no ':' (the script's list separator).
  homePath =
    types.addCheck (types.strMatching "[^/:\n][^:\n]*") (
      s:
      lib.all (
        x:
        !lib.elem x [
          ""
          "."
          ".."
        ]
      ) (lib.splitString "/" s)
    )
    // {
      description = "path relative to the home";
    };
in
{
  options.dev.cleanup = {
    olderThan = typedD (types.strMatching "[1-9][0-9]{0,4}d") "14d" ''
      Age (`<n>d`): unused Docker data and mise's download cache entries older than this, Pulumi
      plugins unused for this long, and older logs and agent state are deleted.
    '';
    schedule = strD "weekly" ''
      When the cleanup runs (a systemd OnCalendar expression; `systemd-analyze calendar` checks one).
    '';
    docker = bool true ''
      With dev.docker.enable: `docker system prune --all` (unused images, stopped containers,
      networks, build cache older than olderThan), then every anonymous volume no container uses,
      regardless of age (a removed container's data goes at the next run). Named volumes are kept.
    '';
    mise = bool true ''
      `mise prune`: tool versions no config file mise has seen selects any more (a deleted
      workspace's tools and `mise x tool@version` installs go, a running program's stay).
    '';
    caches = {
      enable = bool true ''
        Deletes Pulumi plugins unused for olderThan and clears every cache in caches.paths larger
        than caches.maxSize (tools refill them; a build running meanwhile may fail). Size, not age:
        /data is mounted noatime, so a cache's age says nothing about its use.
      '';
      maxSize = typedD types.ints.positive 5 "Size limit of each cache in caches.paths, in GiB.";
      paths = typedD (types.listOf homePath) [
        ".cache/go-build"
        "go/pkg/mod"
        ".cache/pip"
        ".cache/uv"
        ".npm/_cacache"
        ".cache/yarn"
        ".yarn/berry/cache"
        ".local/share/pnpm/store"
      ] "Cache directories, relative to the user's home.";
    };
    logs = bool true ''
      With dev.paseo.enable: Paseo's daily daemon logs (`~/.paseo/*-daemon.log`) older than
      olderThan. With dev.coder.enable: the state (logs, script data) of workspace agents that have
      no unit (a deleted or stopped workspace) and nothing newer than olderThan.
    '';
  };
}
