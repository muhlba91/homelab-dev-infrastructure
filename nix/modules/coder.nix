# Coder as the host's user with the built-in provisioner, so a template's local actions run as that
# user (coder/templates/local-dir). PostgreSQL on the data disk, socket and peer auth mapped to the
# role `coder`. First user and templates: coder-provision.nix.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dev;
  c = cfg.coder;
  u = cfg.user;
  uid = toString u.uid;
  inherit (c) port stateDir;
  accessUrl =
    if c.accessUrl != null then c.accessUrl else "http://${cfg.mgmt.address}:${toString port}";
  # Behind a TLS-terminating reverse proxy (the cluster's gateway).
  proxied = lib.hasPrefix "https://" accessUrl;
  pgPackage = pkgs.postgresql_17;
  # What the server and its provisioner (Terraform's local-exec) run with.
  toolPath = [
    pkgs.coder
    pkgs.terraform
    pkgs.bash
    pkgs.coreutils
    pkgs.systemd
    pkgs.git
    pkgs.openssh
  ];
in
lib.mkIf c.enable {
  assertions = [
    {
      assertion = c.oidc == null || proxied;
      message = "dev.coder.oidc needs an https dev.coder.accessUrl";
    }
  ];

  # Terraform is BSL-licensed (unfree in nixpkgs).
  dev.unfree = [ "terraform" ];

  # The agent of a workspace runs this binary (/run/current-system/sw/bin/coder): always the
  # server's version, and never a store path the garbage collection could remove.
  environment.systemPackages = [ pkgs.coder ];

  dev.secrets = {
    coder-admin-password = { };
  }
  // lib.optionalAttrs (c.oidc != null) {
    # CODER_OIDC_CLIENT_SECRET=… (systemd reads it as root).
    coder-oidc.reload = "systemctl try-restart coder.service";
  };

  services.postgresql = {
    enable = true;
    package = pgPackage;
    dataDir = "${cfg.storage.dataDir}/postgresql/${pgPackage.psqlSchema}";
    ensureDatabases = [ "coder" ];
    ensureUsers = [
      {
        name = "coder";
        ensureDBOwnership = true;
      }
    ];
    # The user's processes (the Coder server) log in as the role `coder` over the socket.
    identMap = ''
      coder ${u.name} coder
    '';
    authentication = lib.mkBefore ''
      local coder coder peer map=coder
    '';
  };
  systemd.tmpfiles.rules = [
    "d ${cfg.storage.dataDir}/postgresql 0750 postgres postgres -"
    "d ${config.services.postgresql.dataDir} 0700 postgres postgres -"
    "d ${stateDir} 0700 ${u.name} users -"
  ];

  services.coder = {
    enable = true;
    user = u.name;
    group = "users";
    listenAddress = "0.0.0.0:${toString port}";
    inherit accessUrl;
    inherit (c) wildcardAccessUrl;
    environment.file = lib.mkIf (c.oidc != null) config.dev.secrets.coder-oidc.path;
    database = {
      createLocally = false;
      host = "/run/postgresql";
      username = "coder";
      database = "coder";
    };
    environment.extra = {
      CODER_CONFIG_DIR = "${stateDir}/config";
      CODER_CACHE_DIRECTORY = "${stateDir}/cache";
      TF_PLUGIN_CACHE_DIR = "${stateDir}/terraform-plugins";
      CODER_TELEMETRY_ENABLE = "false";
      # Terraform's update check would write ~/.terraform.d.
      CHECKPOINT_DISABLE = "1";
      CODER_UPDATE_CHECK = "false";
      # The provisioner's local-exec manages the user's systemd units (the workspace agents).
      XDG_RUNTIME_DIR = "/run/user/${uid}";
      DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/${uid}/bus";
    }
    // lib.optionalAttrs proxied {
      # The client's address for audit logs and Coder's per-IP login rate limit; only the
      # trusted networks may set it (the gateway reaches the host from the cluster's pods).
      CODER_PROXY_TRUSTED_HEADERS = "X-Forwarded-For";
      CODER_PROXY_TRUSTED_ORIGINS = lib.concatStringsSep "," (cfg.trusted.v4 ++ cfg.trusted.v6);
      CODER_SECURE_AUTH_COOKIE = "true";
      # The gateway upgrades only websockets, not DERP's own upgrade.
      CODER_DERP_FORCE_WEBSOCKETS = "true";
    }
    // lib.optionalAttrs (c.oidc != null) {
      CODER_OIDC_ISSUER_URL = c.oidc.issuerUrl;
      CODER_OIDC_CLIENT_ID = c.oidc.clientId;
      CODER_OIDC_SIGN_IN_TEXT = "Sign in with SSO";
      CODER_OIDC_ALLOW_SIGNUPS = "true";
    };
  };
  systemd.services.coder = {
    after = [
      "postgresql.service"
      "postgresql-setup.service"
      "user@${uid}.service"
    ];
    requires = [ "postgresql.service" ];
    wants = [ "user@${uid}.service" ];
    path = toolPath;
    preStart = ''
      mkdir -p ${stateDir}/config ${stateDir}/cache ${stateDir}/terraform-plugins
    '';
  };
}
