# Secrets are files delivered outside Nix (./host push-secrets, or --extra-files on install) into
# /var/lib/secrets; Nix declares only names, owners and modes (the store is world-readable).
#  1. Every activation checks each file exists and is non-empty and applies owner/mode; a missing
#     secret fails the activation (deploy-rs rolls back); at boot it is only logged.
#  2. A path unit per secret re-applies owner/mode and runs its `reload` when the file changes.
#  3. The directory is not listable (0711); file modes protect the content.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  dir = "/var/lib/secrets"; # also in ./host (SECRETS_DIR)
  secrets = config.dev.secrets;
  # Owner and mode only when they differ: PathChanged also fires on attribute changes, so
  # an unconditional chown/chmod would run every secret's reload on every activation.
  applyPerms =
    s:
    let
      mode = builtins.head (builtins.match "0*([0-7]+)" s.mode); # as `stat -c %a` prints it
    in
    ''
      [ "$(stat -c %U:%G:%a ${s.path})" = "${s.owner}:${s.group}:${mode}" ] \
        || { chown ${s.owner}:${s.group} ${s.path} && chmod ${s.mode} ${s.path}; }
    '';

  secretType = types.submodule (
    { name, ... }:
    {
      options = {
        path = mkOption {
          type = types.str;
          readOnly = true;
          default = "${dir}/${name}";
          description = "Where the file lives on the host.";
        };
        owner = mkOption {
          type = types.str;
          default = "root";
          description = "File owner.";
        };
        group = mkOption {
          type = types.str;
          default = "root";
          description = "File group.";
        };
        mode = mkOption {
          type = types.str;
          default = "0400";
          description = "File mode.";
        };
        reload = mkOption {
          type = types.str;
          default = "";
          description = "Shell command run when the file changes (e.g. `networkctl reload`).";
        };
      };
    }
  );
in
{
  options.dev.secrets = mkOption {
    type = types.attrsOf secretType;
    default = { };
    description = "Secret files the host needs (declared by modules; values are delivered out of band).";
  };

  config = lib.mkIf (secrets != { }) {
    system.activationScripts.devSecrets = {
      deps = [
        "users"
        "groups"
      ];
      text = ''
        install -d -m 0711 -o root -g root ${dir}
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (_: s: ''
            if [ ! -s ${s.path} ]; then
              echo "dev-secrets: ${s.path} is missing or empty (deliver it: ./host push-secrets <host>)" >&2
              false
            else
              ${applyPerms s}
            fi
          '') secrets
        )}
      '';
    };

    systemd.paths = lib.mapAttrs' (
      n: s:
      lib.nameValuePair "dev-secret-${n}" {
        wantedBy = [ "multi-user.target" ];
        pathConfig.PathChanged = s.path;
      }
    ) secrets;

    systemd.services = lib.mapAttrs' (
      n: s:
      lib.nameValuePair "dev-secret-${n}" {
        description = "Apply permissions and reload after ${s.path} changed";
        serviceConfig.Type = "oneshot";
        path = [
          pkgs.coreutils
          pkgs.systemd
        ];
        script = ''
          ${applyPerms s}
          ${s.reload}
        '';
      }
    ) secrets;
  };
}
