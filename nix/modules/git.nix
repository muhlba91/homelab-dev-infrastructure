# git for the host's user. With a GitHub machine key (secret `github-ssh-key`), git authenticates
# to GitHub and signs every commit and tag with it (SSH signing from the file: no ssh-agent).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  u = config.dev.user;
  signing = u.githubKey != null;
  keyPath = config.dev.secrets.github-ssh-key.path;
  allowedSigners = pkgs.writeText "allowed-signers" "${u.git.email} ${u.githubKey}\n";
in
{
  programs.git = {
    enable = true;
    config = {
      user = {
        inherit (u.git) name email;
      }
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

  dev.secrets = lib.mkIf signing {
    github-ssh-key = {
      owner = u.name;
      group = "users";
      mode = "0400";
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
