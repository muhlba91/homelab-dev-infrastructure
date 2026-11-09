# Vars schema: the services on the host (Coder: Phase 3).
{ lib, ... }:
let
  inherit (lib) types;
  inherit (import ./types.nix { inherit lib; })
    bool
    nullable
    ;
in
{
  options.dev.coder = {
    enable = bool false ''
      The Coder server, running as the host's user with the built-in provisioner (workspaces
      are directories in ~/workspaces); PostgreSQL on the data disk. Needs the secret
      `coder-admin-password` (the first user).
    '';
    accessUrl = nullable types.str "URL Coder is reached at (null: http://<mgmt.address>:3000).";
  };
}
