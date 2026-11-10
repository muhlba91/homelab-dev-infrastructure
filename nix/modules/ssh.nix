# SSH and the deploy user (passwordless sudo, keys only). A pinned host key (mgmt.hostKey) comes
# only from the secret `ssh-host-key`: no generated fallback, and a mismatch fails the activation.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dev;
  pinned = cfg.mgmt.hostKey != null;
  keyFields = lib.splitString " " cfg.mgmt.hostKey;
  keyPath = config.dev.secrets.ssh-host-key.path;
in
{
  assertions = [
    {
      assertion = !cfg.meta.deployable || cfg.mgmt.sshKeys != [ ];
      message = "dev.mgmt.sshKeys is empty: deploy-rs (user `deploy`) could not log in after this deploy";
    }
  ];

  users.users.deploy = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = cfg.mgmt.sshKeys;
  };
  security.sudo.wheelNeedsPassword = false;
  # Only declared users, no passwords: nothing changed on the host survives an activation.
  users.mutableUsers = false;

  services.openssh = {
    enable = true;
    openFirewall = false; # firewall.nix decides
    hostKeys = lib.mkIf pinned [
      {
        path = keyPath;
        type = lib.removePrefix "ssh-" (lib.head keyFields);
      }
    ];
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  dev.secrets = lib.mkIf pinned { ssh-host-key.reload = "systemctl reload sshd.service"; };
  systemd.services.sshd-keygen.enable = !pinned;
  # `false` fails the activation, so deploy-rs rolls back.
  system.activationScripts.devHostKey = lib.mkIf pinned {
    deps = [ "devSecrets" ];
    text = ''
      if [ -s ${keyPath} ] && [ "$(${pkgs.openssh}/bin/ssh-keygen -y -f ${keyPath} | cut -d' ' -f1,2)" != "${lib.concatStringsSep " " (lib.take 2 keyFields)}" ]; then
        echo "dev-secrets: ${keyPath} does not match dev.mgmt.hostKey" >&2
        false
      fi
    '';
  };
}
