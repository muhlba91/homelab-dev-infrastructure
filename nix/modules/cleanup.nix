# The regular cleanup (dev.cleanup): a user timer of the host's user runs `dev-cleanup`
# (cleanup.sh) with the host's settings baked in; `dev-cleanup --dry-run` shows what it would
# delete. Docker data, Pulumi plugins and logs by age, mise by use, caches by size (/data is
# mounted noatime).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dev;
  c = cfg.cleanup;
  u = cfg.user;
  docker = c.docker && cfg.docker.enable;
  logGlobs = lib.optional cfg.paseo.enable ".paseo/*-daemon.log";
  logs = c.logs && logGlobs != [ ];
  enabled = docker || c.mise || c.caches.enable || logs;
  flag = b: if b then "1" else "0";
  # Defaults the caller's environment may override (`CLEANUP_DAYS=30 dev-cleanup --dry-run`).
  settings = {
    CLEANUP_DAYS = lib.removeSuffix "d" c.olderThan;
    CLEANUP_DOCKER = flag docker;
    CLEANUP_MISE = flag c.mise;
    CLEANUP_CACHES = flag c.caches.enable;
    CLEANUP_CACHE_MAX_MB = toString (c.caches.maxSize * 1024);
    CLEANUP_CACHE_PATHS = lib.concatStringsSep ":" c.caches.paths;
    CLEANUP_LOGS = flag logs;
    CLEANUP_LOG_GLOBS = lib.concatStringsSep ":" logGlobs;
  };
  script = pkgs.writeShellApplication {
    name = "dev-cleanup";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.mise
    ]
    ++ lib.optional docker config.virtualisation.docker.rootless.package;
    text =
      lib.concatStrings (
        lib.mapAttrsToList (n: v: "export ${n}=\${${n}:-${lib.escapeShellArg v}}\n") settings
      )
      + builtins.readFile ./cleanup.sh;
  };
in
lib.mkIf enabled {
  environment.systemPackages = [ script ];

  systemd.user.services.dev-cleanup = {
    description = "Prune unused Docker data, tool versions, caches and logs";
    unitConfig.ConditionUser = u.name;
    # Not Requires=: a Docker that is down fails only its section.
    after = lib.optional docker "docker.service";
    # No Restart=: a run waiting to restart is not "failed", and dev-health would not see it.
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe script;
      # Running workspaces and agents come first.
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };
  systemd.user.timers.dev-cleanup = {
    wantedBy = [ "timers.target" ];
    unitConfig.ConditionUser = u.name;
    timerConfig = {
      OnCalendar = c.schedule;
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };
}
