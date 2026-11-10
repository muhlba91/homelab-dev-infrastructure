# Nix: flakes only, deploy-rs as a trusted user, store optimisation and garbage collection.
{ config, ... }:
let
  inherit (config.dev.system) gc;
in
{
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    # deploy-rs copies closures as `deploy` (wheel).
    trusted-users = [
      "root"
      "@wheel"
    ];
  };
  nix.channel.enable = false;
  nix.optimise.automatic = true;

  # Keep the newest `keep` generations (runs first), then drop those older than `olderThan`.
  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than ${gc.olderThan}";
  };
  systemd.services.nix-gc.preStart = "${config.nix.package}/bin/nix-env --profile /nix/var/nix/profiles/system --delete-generations +${toString gc.keep}";
}
