# `dev-health` (./host health, after every deploy): no unit has failed (system and the user's
# user manager), the data disk is mounted and below 80% (a warning above); a pending reboot (the
# booted kernel, initrd or modules are not the current system's) is a warning. Exits 1 on a
# failure.
{
  config,
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
