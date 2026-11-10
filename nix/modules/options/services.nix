# Vars schema: the services on the host (Docker: Phase 2, Coder and its backups: Phase 3, the
# Vault Agent: Phase 4).
{ lib, ... }:
let
  inherit (lib) types;
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
      URL Coder is reached at (null: http://<mgmt.address>:3000). An https URL means a reverse
      proxy in front (the cluster's gateway): Coder then trusts its X-Forwarded-For from the
      trusted networks, sets secure cookies and relays DERP over websockets.
    '';
    wildcardAccessUrl = nullable types.str ''
      Hostname pattern for workspace apps (e.g. `*.coder.example.org`; null: path-based apps only).
    '';
  };

  options.dev.vault = {
    enable = bool false ''
      The Vault Agent: logs in with the AppRole role dev-infrastructure-<host> (secrets
      `vault-role-id`, `vault-secret-id`) and keeps a short-lived token for the host's user.
    '';
    address = nullable types.str "URL of Vault (required when enabled).";
  };
}
