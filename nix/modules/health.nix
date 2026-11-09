# `dev-health` (./host health, after every deploy): no unit has failed (system and the user's
# user manager), the data disk is mounted and below 80% (a warning above), Coder answers (hosts
# with Coder), the user's rootless Docker runs (hosts with Docker); a failed backup is a failed
# unit; a pending reboot (the booted kernel, initrd or modules are not
# the current system's) is a warning. Exits 1 on a failure.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dev;
in
{
  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "dev-health";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.util-linux
        pkgs.systemd
        pkgs.curl
      ];
      text = ''
        rc=0
        failed=$(systemctl --failed --no-legend --plain)
        if [ -z "$failed" ]; then echo "ok   failed units: 0"; else echo "$failed"; echo "FAIL failed units"; rc=1; fi
        ufailed=$(systemctl --machine=${cfg.user.name}@.host --user --failed --no-legend --plain 2>/dev/null || true)
        if [ -z "$ufailed" ]; then echo "ok   failed user units (${cfg.user.name}): 0"; else echo "$ufailed"; echo "warn failed user units (${cfg.user.name})"; fi
        if mountpoint -q ${cfg.storage.dataDir}; then
          use=$(df --output=pcent ${cfg.storage.dataDir} | tail -1 | tr -dc '0-9')
          if [ "$use" -ge 80 ]; then echo "warn ${cfg.storage.dataDir}: $use% used"; else echo "ok   ${cfg.storage.dataDir}: $use% used"; fi
        else
          echo "FAIL ${cfg.storage.dataDir} is not mounted"; rc=1
        fi
        ${lib.optionalString cfg.coder.enable ''
          if curl -fsS -m 5 -o /dev/null http://127.0.0.1:3000/healthz; then
            echo "ok   coder: healthy"
          else
            echo "FAIL coder: /healthz does not answer"; rc=1
          fi
        ''}
        ${lib.optionalString cfg.docker.enable ''
          if systemctl --machine=${cfg.user.name}@.host --user is-active --quiet docker 2>/dev/null; then
            echo "ok   docker (${cfg.user.name}): active"
          else
            echo "FAIL docker (${cfg.user.name}): not active"; rc=1
          fi
        ''}
        for p in kernel initrd kernel-modules; do
          if [ "$(readlink /run/booted-system/$p)" != "$(readlink /run/current-system/$p)" ]; then
            echo "warn reboot required: the booted $p is not the current one"
            break
          fi
        done
        exit "$rc"
      '';
    })
  ];
}
