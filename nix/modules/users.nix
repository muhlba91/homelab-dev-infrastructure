# The host's user: pinned uid and subuid/subgid ranges (files on /data keep their owner across
# reinstalls), home on the data disk, linger, SSH keys only, no sudo.
{ config, pkgs, ... }:
let
  cfg = config.dev;
  u = cfg.user;
  home = "${cfg.storage.dataDir}/home/${u.name}";
in
{
  users.users.${u.name} = {
    isNormalUser = true;
    inherit (u) uid;
    group = "users"; # gid 100, fixed in NixOS
    inherit home;
    createHome = true;
    shell = pkgs.zsh;
    # Not in wheel (admin tasks: ./host ssh as deploy), not in docker (rootless Docker, docker.nix).
    extraGroups = [ ];
    # Fixed ranges (rootless containers): automatically allocated ones could change on a reinstall.
    subUidRanges = [
      {
        startUid = 100000;
        count = 65536;
      }
    ];
    subGidRanges = [
      {
        startGid = 100000;
        count = 65536;
      }
    ];
    linger = true;
    # In /etc/ssh/authorized_keys.d: sshd never depends on the home directory.
    openssh.authorizedKeys.keys = u.sshKeys;
  };

  programs.zsh.enable = true;
}
