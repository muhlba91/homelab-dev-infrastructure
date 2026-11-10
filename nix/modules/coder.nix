# Coder (Phase 3 of the plan): the server runs as the host's user with the
# built-in provisioner, so a template's local actions run as that user (workspaces are directories
# in ~/workspaces with a `coder agent` user unit, nix/coder/templates/local-dir). PostgreSQL holds its
# database on the data disk, reached over the socket with peer authentication mapped to the role
# `coder` (createLocally insists on a user named `coder`). A bootstrap oneshot creates the first
# user and an admin token; a second oneshot pushes the templates shipped with the system.
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
  stateDir = "${cfg.storage.dataDir}/coder";
  tokenFile = "${stateDir}/tokens/admin";
  port = 3000;
  accessUrl =
    if c.accessUrl != null then c.accessUrl else "http://${cfg.mgmt.address}:${toString port}";
  localUrl = "http://127.0.0.1:${toString port}";
  # Behind a TLS-terminating reverse proxy (Phase 5: the cluster's gateway).
  proxied = lib.hasPrefix "https://" accessUrl;
  templates = ../coder/templates;
  pgPackage = pkgs.postgresql_17;
  # What the server, its provisioner (Terraform's local-exec) and the oneshots run with.
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
  # Terraform is BSL-licensed (unfree in nixpkgs).
  dev.unfree = [ "terraform" ];

  # The agent of a workspace runs this binary (/run/current-system/sw/bin/coder): always the
  # server's version, and never a store path the garbage collection could remove.
  environment.systemPackages = [ pkgs.coder ];

  dev.secrets.coder-admin-password = { };

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
    "d ${stateDir}/tokens 0700 ${u.name} users -"
  ];

  services.coder = {
    enable = true;
    user = u.name;
    group = "users";
    listenAddress = "0.0.0.0:${toString port}";
    inherit accessUrl;
    inherit (c) wildcardAccessUrl;
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

  # The first (admin) user and an admin token for the template push. Idempotent: a valid token
  # ends it; without one it creates the first user if none exists, then logs in with the
  # password (a credential: the secret stays root-owned) and creates a token.
  systemd.services.coder-bootstrap = {
    description = "Create Coder's first user and an admin token";
    after = [ "coder.service" ];
    requires = [ "coder.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [
      pkgs.curl
      pkgs.jq
      pkgs.coreutils
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = u.name;
      Group = "users";
      LoadCredential = "admin-password:${config.dev.secrets.coder-admin-password.path}";
      UMask = "0077";
    };
    script = ''
      url=${localUrl}
      for _ in $(seq 60); do curl -fsS "$url/healthz" >/dev/null 2>&1 && break; sleep 2; done
      if [ -s ${tokenFile} ] && curl -fsS -H "Coder-Session-Token: $(cat ${tokenFile})" "$url/api/v2/users/me" >/dev/null; then
        echo "coder-bootstrap: token valid"
        exit 0
      fi
      password=$(cat "$CREDENTIALS_DIRECTORY/admin-password")
      if [ "$(curl -s -o /dev/null -w '%{http_code}' "$url/api/v2/users/first")" = 404 ]; then
        jq -n --arg u ${u.name} --arg e '${u.git.email}' --arg n '${u.git.name}' --arg p "$password" \
          '{username: $u, email: $e, name: $n, password: $p, trial: false}' |
          curl -fsS -X POST -H 'Content-Type: application/json' --data @- "$url/api/v2/users/first" >/dev/null
        echo "coder-bootstrap: first user created"
      fi
      session=$(jq -n --arg e '${u.git.email}' --arg p "$password" '{email: $e, password: $p}' |
        curl -fsS -X POST -H 'Content-Type: application/json' --data @- "$url/api/v2/users/login" | jq -r .session_token)
      jq -n '{token_name: "bootstrap", lifetime: 0}' |
        curl -fsS -X POST -H 'Content-Type: application/json' -H "Coder-Session-Token: $session" --data @- \
          "$url/api/v2/users/me/keys/tokens" | jq -r .key > ${tokenFile}.new
      mv ${tokenFile}.new ${tokenFile}
      echo "coder-bootstrap: token created"
    '';
  };

  # The templates shipped with the system (nix/coder/templates/<name>), pushed when they change
  # (the last pushed store path per template in /data/coder/templates).
  systemd.services.coder-templates = {
    description = "Push the Coder templates shipped with the system";
    after = [ "coder-bootstrap.service" ];
    requires = [ "coder-bootstrap.service" ];
    wantedBy = [ "multi-user.target" ];
    restartTriggers = [ templates ];
    path = toolPath;
    environment = {
      CODER_URL = localUrl;
      CODER_CONFIG_DIR = "${stateDir}/cli";
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = u.name;
      Group = "users";
    };
    script = ''
      CODER_SESSION_TOKEN=$(cat ${tokenFile})
      export CODER_SESSION_TOKEN
      mkdir -p ${stateDir}/templates
      for dir in ${templates}/*/; do
        name=$(basename "$dir")
        # The store path changes exactly when the template does: push only then (this unit also
        # restarts with every Coder restart).
        if [ "$(cat ${stateDir}/templates/"$name" 2>/dev/null)" = "$dir" ]; then
          echo "coder-templates: $name unchanged"
          continue
        fi
        # A copy: coder writes a lock file next to the template.
        work=$(mktemp -d)
        cp -r "$dir". "$work"
        chmod -R u+w "$work"
        coder templates push "$name" --directory "$work" --yes --message "pushed by coder-templates (${templates})"
        rm -rf "$work"
        echo "$dir" > ${stateDir}/templates/"$name"
      done
    '';
  };
}
