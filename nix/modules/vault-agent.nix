# Vault Agent: logs in with the host's AppRole role (dev-infrastructure-<host>, read-only on the KV
# mounts) and keeps a short-lived token for the user. The agent is its own user, the only reader of
# the role and secret ID; the token sink is readable by the group `vault-token` (the user). The
# CLI's token helper reads the sink, so `vault`, fnox and Pulumi find it and `vault login` cannot
# replace it.
{
  config,
  lib,
  dlib,
  pkgs,
  ...
}:
let
  cfg = config.dev;
  v = cfg.vault;
  instance = "dev";
  unit = "vault-agent-${instance}.service";
  uid = 950; # pinned (owns files); also the gid of vault-token
  sink = "/run/vault-agent/token";
  tokenHelper = pkgs.writeShellScript "vault-token-helper" ''
    # get: the agent's token (an unreadable sink: nothing, and the cause on stderr); store and
    # erase do nothing (the agent owns the token).
    if [ "''${1:-}" = get ]; then
      if [ -r ${sink} ]; then
        ${pkgs.coreutils}/bin/cat ${sink}
      else
        echo "vault-token-helper: cannot read ${sink}: the agent has no token yet, or this process lacks the group vault-token (stale user manager: see dev-health)" >&2
      fi
    fi
  '';
  cliConfig = pkgs.writeText "vault-cli.hcl" ''
    token_helper = "${tokenHelper}"
  '';
  env = {
    VAULT_ADDR = v.address;
    VAULT_CONFIG_PATH = "${cliConfig}";
    # Pulumi's Vault provider uses the token as is (no child token), the same here and on the Mac.
    TERRAFORM_VAULT_SKIP_CHILD_TOKEN = "true";
  };
in
lib.mkIf v.enable {
  assertions = [
    {
      assertion = v.address != null;
      message = "dev.vault.address is required when dev.vault.enable is set";
    }
  ];

  users.users.vault-agent = {
    isSystemUser = true;
    inherit uid;
    group = "vault-token";
  };
  users.groups.vault-token = {
    gid = uid;
    members = [ cfg.user.name ];
  };

  dev.secrets = lib.genAttrs [ "vault-role-id" "vault-secret-id" ] (_: {
    owner = "vault-agent";
    group = "vault-token";
    mode = "0400";
    # A rotated secret ID: log in again with it.
    reload = "systemctl restart ${unit}";
  });

  services.vault-agent.instances.${instance} = {
    user = "vault-agent";
    group = "vault-token";
    settings = {
      vault.address = v.address;
      auto_auth = {
        method = [
          {
            type = "approle";
            mount_path = "auth/approle";
            config = {
              role_id_file_path = config.dev.secrets.vault-role-id.path;
              secret_id_file_path = config.dev.secrets.vault-secret-id.path;
              # The agent deletes the file by default; the secrets guard would then fail every
              # activation.
              remove_secret_id_file_after_reading = false;
            };
          }
        ];
        sink = [
          {
            type = "file";
            config = {
              path = sink;
              mode = 288; # 0440: the group vault-token
            };
          }
        ];
      };
    };
  };
  systemd.services."vault-agent-${instance}" = {
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig.RuntimeDirectoryMode = "0750";
  };

  environment.variables = env;
  systemd.user.extraConfig = dlib.userEnv env;
}
