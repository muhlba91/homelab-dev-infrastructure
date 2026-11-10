# Small pure helpers shared by the modules (`dlib` module argument).
{ lib, ... }:
{
  _module.args.dlib = {
    # An nftables set literal ("{ a, b }").
    nftSet = l: "{ ${lib.concatStringsSep ", " l} }";
    # systemd.user.extraConfig line giving the user manager (workspace agents, user services)
    # environment variables, which the session-only `environment.variables` does not reach.
    userEnv =
      env:
      "DefaultEnvironment=${lib.concatStringsSep " " (lib.mapAttrsToList (n: v: ''"${n}=${v}"'') env)}\n";
  };
}
