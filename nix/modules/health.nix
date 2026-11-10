# `dev-health` (./host health, after every deploy). FAIL (exit 1): failed units, the user manager
# lacking one of the user's groups (a deploy never restarts it), /data missing, Coder, Docker or the
# Vault token down. warn: failed user units, /data >= 80%, Vault unreachable, pending reboot.
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
        pkgs.gawk
        pkgs.gnugrep
      ]
      ++ lib.optionals cfg.vault.enable [
        pkgs.vault
        pkgs.jq
      ];
      text = ''
        rc=0
        failed=$(systemctl --failed --no-legend --plain)
        if [ -z "$failed" ]; then echo "ok   failed units: 0"; else echo "$failed"; echo "FAIL failed units"; rc=1; fi
        ufailed=$(systemctl --machine=${cfg.user.name}@.host --user --failed --no-legend --plain 2>/dev/null || true)
        if [ -z "$ufailed" ]; then echo "ok   failed user units (${cfg.user.name}): 0"; else echo "$ufailed"; echo "warn failed user units (${cfg.user.name})"; fi
        # The user manager keeps the groups it started with: a group added later (vault-token) is
        # missing in workspaces and user services until it restarts.
        upid=$(systemctl show --property=MainPID --value "user@${toString cfg.user.uid}.service" 2>/dev/null || true)
        if [ -z "$upid" ] || [ "$upid" = 0 ]; then
          echo "warn user manager (${cfg.user.name}): not running"
        else
          primary=$(id -g ${cfg.user.name})
          want=$(id -G ${cfg.user.name} | tr ' ' '\n' | grep -vx "$primary" | sort -u || true)
          have=$(awk '/^Groups:/ { for (i = 2; i <= NF; i++) print $i }' "/proc/$upid/status" | sort -u)
          missing=$(comm -23 <(printf '%s\n' "$want") <(printf '%s\n' "$have") | grep . | tr '\n' ' ' || true)
          if [ -n "$missing" ]; then
            echo "FAIL user manager (${cfg.user.name}): stale groups, missing gid $missing(restarts workspaces, user services, Docker: ./host ssh ${cfg.host.name} 'sudo systemctl restart user@${toString cfg.user.uid}.service')"; rc=1
          else
            echo "ok   user manager (${cfg.user.name}): current groups"
          fi
        fi
        if mountpoint -q ${cfg.storage.dataDir}; then
          use=$(df --output=pcent ${cfg.storage.dataDir} | tail -1 | tr -dc '0-9')
          if [ "$use" -ge 80 ]; then echo "warn ${cfg.storage.dataDir}: $use% used"; else echo "ok   ${cfg.storage.dataDir}: $use% used"; fi
        else
          echo "FAIL ${cfg.storage.dataDir} is not mounted"; rc=1
        fi
        ${lib.optionalString cfg.coder.enable ''
          if curl -fsS -m 5 -o /dev/null http://127.0.0.1:${toString cfg.coder.port}/healthz; then
            echo "ok   coder: healthy"
          else
            echo "FAIL coder: /healthz does not answer"; rc=1
          fi
        ''}
        ${lib.optionalString cfg.vault.enable ''
          if [ ! -s ${cfg.vault.tokenFile} ]; then
            echo "FAIL vault: the agent has no token"; rc=1
          elif ttl=$(VAULT_ADDR=${cfg.vault.address} VAULT_TOKEN=$(cat ${cfg.vault.tokenFile}) vault token lookup -format=json 2>/dev/null | jq -er .data.ttl); then
            echo "ok   vault: token valid (ttl ''${ttl}s)"
          else
            echo "warn vault: the token does not look up (Vault unreachable?)"
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
