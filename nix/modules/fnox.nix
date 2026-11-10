# fnox: repositories read their secrets from Vault with `fnox exec` (fnox from their mise.toml). The
# host selects their `dev` profile and gets a global config in /etc/fnox: the Vault provider for the
# mount `dev-infrastructure` (the Vault Agent's token via the CLI's token helper) and this host's GCP
# key as the source of the repositories' impersonation file (never exported).
{
  config,
  lib,
  dlib,
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
  systemd.user.extraConfig = dlib.userEnv env;
}
