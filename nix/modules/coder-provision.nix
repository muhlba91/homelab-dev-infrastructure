# Coder provisioning: a oneshot creates the first (admin) user and an admin token, a second pushes
# the templates shipped in nix/coder/templates whenever they change.
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
  stateDir = "${cfg.storage.dataDir}/coder";
  tokenFile = "${stateDir}/tokens/admin";
  localUrl = "http://127.0.0.1:${toString c.port}";
  templates = ../coder/templates;
in
lib.mkIf c.enable {
  # The first user and an admin token for the template push (idempotent). The password is a
  # credential, so the secret stays root-owned.
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
      set -o pipefail
      url=${localUrl}
      for _ in $(seq 60); do curl -fsS "$url/healthz" >/dev/null 2>&1 && break; sleep 2; done
      if [ -s ${tokenFile} ] && curl -fsS -H "Coder-Session-Token: $(cat ${tokenFile})" "$url/api/v2/users/me" >/dev/null; then
        echo "coder-bootstrap: token valid"
        exit 0
      fi
      # The password stays out of argv (--rawfile).
      pw="$CREDENTIALS_DIRECTORY/admin-password"
      if [ "$(curl -s -o /dev/null -w '%{http_code}' "$url/api/v2/users/first")" = 404 ]; then
        jq -n --arg u ${lib.escapeShellArg u.name} --arg e ${lib.escapeShellArg u.git.email} \
          --arg n ${lib.escapeShellArg u.git.name} --rawfile p "$pw" \
          '{username: $u, email: $e, name: $n, password: ($p | rtrimstr("\n")), trial: false}' |
          curl -fsS -X POST -H 'Content-Type: application/json' --data @- "$url/api/v2/users/first" >/dev/null
        echo "coder-bootstrap: first user created"
      fi
      session=$(jq -n --arg e ${lib.escapeShellArg u.git.email} --rawfile p "$pw" \
        '{email: $e, password: ($p | rtrimstr("\n"))}' |
        curl -fsS -X POST -H 'Content-Type: application/json' --data @- "$url/api/v2/users/login" | jq -er .session_token)
      jq -n '{token_name: "bootstrap", lifetime: 0}' |
        curl -fsS -X POST -H 'Content-Type: application/json' -H "Coder-Session-Token: $session" --data @- \
          "$url/api/v2/users/me/keys/tokens" | jq -er .key > ${tokenFile}.new
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
    path = [
      pkgs.coder
      pkgs.coreutils
    ];
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
        trap 'rm -rf "$work"' EXIT
        cp -r "$dir". "$work"
        chmod -R u+w "$work"
        coder templates push "$name" --directory "$work" --yes --message "pushed by coder-templates (${templates})"
        rm -rf "$work"
        echo "$dir" > ${stateDir}/templates/"$name"
      done
    '';
  };
}
