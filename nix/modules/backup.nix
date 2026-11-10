# Nightly restic backup of Coder's database to dev.backup.repository/coder (credentials: secrets
# `restic-password`, `restic-s3`). `./host deploy` runs it before a system change: a Coder schema
# migration cannot be rolled back, the dump can. Restore: docs/install.md.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dev;
  repository = cfg.backup.repository;
  dumpDir = "${cfg.storage.dataDir}/backup/coder";
  pg = config.services.postgresql.package;
in
lib.mkIf (cfg.coder.enable && repository != null) {
  dev.secrets.restic-password = { };
  dev.secrets.restic-s3 = { };

  systemd.tmpfiles.rules = [
    "d ${cfg.storage.dataDir}/backup 0700 root root -"
    "d ${dumpDir} 0700 root root -"
  ];

  services.restic.backups.coder = {
    repository = "${repository}/coder";
    initialize = true;
    passwordFile = config.dev.secrets.restic-password.path;
    environmentFile = config.dev.secrets.restic-s3.path;
    paths = [ dumpDir ];
    # The dump as postgres (peer authentication), written by root: a failed dump fails the
    # backup and keeps the previous file.
    backupPrepareCommand = ''
      #!${pkgs.runtimeShell}
      set -eu
      ${pkgs.util-linux}/bin/runuser -u postgres -- ${pg}/bin/pg_dump --format=custom --dbname=coder > ${dumpDir}/coder.dump.new
      mv ${dumpDir}/coder.dump.new ${dumpDir}/coder.dump
    '';
    # The newest 3 snapshots plus the newest of each of the last 3 calendar weeks; pruned after
    # every backup.
    pruneOpts = [
      "--keep-last 3"
      "--keep-weekly 3"
    ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };
  systemd.services.restic-backups-coder = {
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
  };
}
