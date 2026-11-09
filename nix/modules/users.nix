# The host's user (§5.3, §5.6 of the plan): pinned uid and subordinate id ranges (files on /data
# keep their owner across reinstalls), home on the data disk, linger (user services run without
# a login), SSH keys only, no sudo, no docker group. git signs every commit with the GitHub
# machine key (secret `github-ssh-key`, readable only by the user).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dev;
  u = cfg.user;
  home = "${cfg.storage.dataDir}/home/${u.name}";
  signing = u.githubKey != null;
  keyPath = config.dev.secrets.github-ssh-key.path;
  allowedSigners = pkgs.writeText "allowed-signers" "${u.git.email} ${u.githubKey}\n";
in
{
  users.users.${u.name} = {
    isNormalUser = true;
    inherit (u) uid;
    group = "users"; # gid 100, fixed in NixOS
    inherit home;
    createHome = true;
    shell = pkgs.zsh;
    # Not in wheel (admin tasks: ./host ssh as deploy), not in docker (rootless Docker, Phase 2).
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

  dev.secrets = lib.mkIf signing {
    github-ssh-key = {
      owner = u.name;
      group = "users";
      mode = "0400";
    };
  };

  programs.git = {
    enable = true;
    config = {
      user = {
        inherit (u.git) name email;
      }
      # SSH signing with the machine key's file: no ssh-agent needed.
      // lib.optionalAttrs signing { signingkey = keyPath; };
      init.defaultBranch = "main";
    }
    // lib.optionalAttrs signing {
      gpg.format = "ssh";
      gpg.ssh.allowedSignersFile = "${allowedSigners}";
      commit.gpgsign = true;
      tag.gpgsign = true;
    };
  };

  programs.ssh.extraConfig = lib.optionalString signing ''
    Host github.com
      User git
      IdentityFile ${keyPath}
      IdentitiesOnly yes
  '';
  programs.ssh.knownHosts = lib.mkIf signing {
    "github.com".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
  };
}
