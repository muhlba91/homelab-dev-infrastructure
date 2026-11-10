# Vault Agent (Phase 4 of the plan, D9, D34, D42): logs in with the host's AppRole role
# (dev-infrastructure-<host>, created by github-infrastructure: read-only on the KV mounts) and
# keeps a short-lived token (1 h, renewed, at most 24 h, then a new login) for the host's user.
# The agent runs as its own user `vault-agent`, the only one that can read the role ID and the
# secret ID; the token sink is readable by the group `vault-token` (the user is a member), so
# everything running as the user (agents included, D30) gets the token, never the secret ID.
# The Vault CLI's token helper reads the sink: `vault`, fnox (`vault print token`) and Pulumi's
# Vault provider find the token, and `vault login` cannot overwrite it.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dev;
  v = cfg.vault;
  instance = "dev";
  unit = "vault-agent-${instance}.service";
  uid = 950; # pinned like every identity owning files (D33)
  sink = "/run/vault-agent/token";
  tokenHelper = pkgs.writeShellScript "vault-token-helper" ''
    # get: the agent's token; store and erase do nothing (the agent owns the token).
    if [ "''${1:-}" = get ]; then cat ${sink} 2>/dev/null || true; fi
  '';
  cliConfig = pkgs.writeText "vault-cli.hcl" ''
    token_helper = "${tokenHelper}"
  '';
  env = {
    VAULT_ADDR = v.address;
    VAULT_CONFIG_PATH = "${cliConfig}";
    # Pulumi's (Terraform's) Vault provider uses the token as is: the host policy has no
    # auth/token/create. Minted repository tokens (fnox, Q31) could create child tokens, but the
    # variable stays so long runs behave the same here and on the Mac (local secrets plan D52).
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
  # The user manager (workspace agents, user services) as well.
  systemd.user.extraConfig = ''
    DefaultEnvironment=${lib.concatStringsSep " " (lib.mapAttrsToList (n: val: "\"${n}=${val}\"") env)}
  '';
}
