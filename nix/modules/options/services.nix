# Vars schema: the services (Docker, Coder and its backup, the Vault Agent, Paseo).
{ config, lib, ... }:
let
  inherit (lib) types;
  # A constant shared by modules, not set by vars.
  fixed =
    type: default: description:
    lib.mkOption {
      inherit type default description;
      readOnly = true;
      internal = true;
    };
  inherit (import ./types.nix { inherit lib; })
    bool
    nullable
    typedD
    ;
in
{
  options.dev.docker = {
    enable = bool false ''
      A rootless Docker daemon for the host's user (a systemd user unit, data in the home on the
      data disk); nobody is in the docker group. Published ports bind to 127.0.0.1 by default.
    '';
    trustedPorts = typedD (types.listOf (types.strMatching "[0-9]{1,5}(-[0-9]{1,5})?")) [ ] ''
      TCP ports or ranges ("8080", "8000-8999") opened to the trusted networks, for containers
      published on the host's address (`-p 0.0.0.0:8080:80`).
    '';
  };

  options.dev.backup = {
    repository = nullable types.str ''
      Base of the host's restic repositories (`s3:<endpoint>/<bucket>/dev/<host>`; each
      application appends /<application>), rendered by Pulumi for hosts with Coder. With Coder:
      a nightly dump of its database, backed up with restic (secrets `restic-password`,
      `restic-s3`). null = no backups.
    '';
  };

  options.dev.coder = {
    enable = bool false ''
      The Coder server, running as the host's user with the built-in provisioner (workspaces
      are directories in ~/workspaces); PostgreSQL on the data disk. Needs the secret
      `coder-admin-password` (the first user).
    '';
    accessUrl = nullable types.str ''
      URL Coder is reached at (null: http://<mgmt.address>:<port>). An https URL means a reverse
      proxy in front (the cluster's gateway): Coder then trusts its X-Forwarded-For from the
      trusted networks, sets secure cookies and relays DERP over websockets.
    '';
    port =
      fixed types.port 3000
        "Coder's port (the template's agent URL hardcodes it; an eval test checks).";
    stateDir =
      fixed types.str "${config.dev.storage.dataDir}/coder"
        "Coder's state (config, cache, tokens).";
    # Generic, so an SSO login with the user's own e-mail never collides with it (Coder refuses
    # an SSO login for a password account's e-mail). Pulumi's stack output repeats it.
    admin = {
      name = fixed types.str "admin" "Username of Coder's first user (the bootstrap admin).";
      email =
        fixed types.str "admin@${config.dev.host.hostname}.${config.dev.host.domain}"
          "E-mail (login) of the bootstrap admin.";
    };
    wildcardAccessUrl = nullable types.str ''
      Hostname pattern for workspace apps (e.g. `*.coder.example.org`; null: path-based apps only).
    '';
    oidc =
      nullable
        (types.submodule {
          options = {
            issuerUrl = lib.mkOption {
              type = types.strMatching "https://.*[^/]";
              description = "The issuer URL (no trailing slash).";
            };
            clientId = lib.mkOption {
              type = types.str;
              description = "The client ID.";
            };
          };
        })
        ''
          SSO login with an OIDC client (rendered by Pulumi from the stack config `zitadel`; needs an
          https accessUrl and the secret `coder-oidc`, the client secret as an environment file).
          Sign-ups are allowed: the provider decides who gets in. The password login stays.
          null = password login only.
        '';
  };

  options.dev.vault = {
    enable = bool false ''
      The Vault Agent: logs in with the AppRole role dev-infrastructure-<host> (secrets
      `vault-role-id`, `vault-secret-id`) and keeps a short-lived token for the host's user.
    '';
    address = nullable types.str "URL of Vault (required when enabled).";
    tokenFile = fixed types.str "/run/vault-agent/token" "The agent's token sink.";
  };

  options.dev.paseo = {
    enable = bool false ''
      The Paseo daemon (agent orchestration): a systemd user unit of the host's user, its web UI,
      apps and API on one port from the trusted networks, behind the password of the secret
      `paseo-env` (`PASEO_PASSWORD=…`). Settings changed in its UI persist (~/.paseo/config.json
      is not managed); the listen address, password, relay (off), web UI and proxy trust are
      environment variables and win over that file.
    '';
    hostname = nullable (types.strMatching "[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*") ''
      The name a TLS-terminating proxy forwards (the cluster's gateway): allowed in the Host
      header, and the proxy's X-Forwarded-* headers are trusted from the trusted networks.
      null = IP addresses and localhost only.
    '';
    port = fixed types.port 6767 "Paseo's port.";
  };
}
