# Rootless Docker for the host's user (a dev tool, not used by Coder): a systemd user unit started
# by linger, data on the data disk. Nobody is in the docker group.
{
  config,
  lib,
  dlib,
  ...
}:
let
  cfg = config.dev;
  u = cfg.user;
  socket = "/run/user/${toString u.uid}/docker.sock";
  host = "unix://${socket}";
in
lib.mkIf cfg.docker.enable {
  virtualisation.docker.rootless = {
    enable = true;
    # DOCKER_HOST in login shells.
    setSocketVariable = true;
    daemon.settings = {
      # Published ports bind to localhost unless a port says otherwise (`-p 0.0.0.0:8080:80`); the
      # firewall (default deny) is the real guard. `ip` covers only the default bridge; networks
      # created later (every compose project) take default-network-opts.
      ip = "127.0.0.1";
      default-network-opts.bridge."com.docker.network.bridge.host_binding_ipv4" = "127.0.0.1";
      log-driver = "local";
    };
  };

  systemd.user.services.docker = {
    # The module's unit runs for every user manager (`deploy` included, which has no subordinate
    # ids): only the host's user.
    unitConfig.ConditionUser = lib.mkForce u.name;
    # A deploy restarting the daemon would stop every container: a new version runs after
    # `systemctl --user restart docker` or a reboot.
    restartIfChanged = false;
  };

  # The user manager (workspace agents, user services) gets DOCKER_HOST as well; testcontainers'
  # reaper mounts the socket by this path. The other users' managers have no access to it.
  systemd.user.extraConfig = dlib.userEnv {
    DOCKER_HOST = host;
    TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE = socket;
  };
  environment.variables.TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE = socket;
}
