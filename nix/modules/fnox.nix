# fnox on the host (Q31 of the plan, the local secrets plan): repositories read their secrets from
# Vault with `fnox exec`, the same way on the Mac and here. fnox itself comes from each repository's
# mise.toml. The host selects the repositories' `dev` profile (Pulumi token, a repository-scoped
# Vault token minted through the token role) and gets a global config, managed here: the Vault
# provider for the developer machines' mount `dev-infrastructure` (token through the CLI's token
# helper, i.e. the Vault Agent's token) and the host's own GCP key as the source of the
# impersonation file the repositories build (`GCP_SOURCE_CREDENTIALS`, only in the `dev` profile
# and never put into the environment).
{
  config,
  lib,
  ...
}:
let
  cfg = config.dev;
  configDir = "/etc/fnox";
  # Written as text (strings quoted as JSON, which TOML accepts), so the eval tests read it without
  # building anything.
  q = builtins.toJSON;
  globalConfig = ''
    # Managed by NixOS (dev-infrastructure, fnox.nix).
    [providers.dev-infrastructure]
    type = "vault"
    path = "dev-infrastructure"
    credential_command = "vault print token"

    [profiles.dev.secrets.GCP_SOURCE_CREDENTIALS]
    provider = "dev-infrastructure"
    value = ${q "gcp-dev-${cfg.host.name}/credentials"}
    env = false
    description = ${q "this host's GCP service account key (dev-${cfg.host.name}): it can only impersonate"}
  '';
  env = {
    FNOX_PROFILE = "dev";
    # The global config; fnox's default (~/.config/fnox) would not be managed.
    FNOX_CONFIG_DIR = configDir;
  };
in
lib.mkIf cfg.vault.enable {
  environment.etc."fnox/config.toml".text = globalConfig;

  environment.variables = env;
  # The user manager (workspace agents, user services) as well: coder_agent.env does not set them.
  systemd.user.extraConfig = ''
    DefaultEnvironment=${lib.concatStringsSep " " (lib.mapAttrsToList (n: val: "\"${n}=${val}\"") env)}
  '';
}
