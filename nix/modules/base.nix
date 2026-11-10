# Base system: unfree allow-list, the hardware watchdog, journal size, terminfo, server tools.
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
  system.stateVersion = "26.05";

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) cfg.unfree;

  # systemd pets the hardware watchdog; a hung system is reset. "0s" (any zero) disables it.
  systemd.settings.Manager.RuntimeWatchdogSec = lib.mkIf (
    builtins.match "0+[smh]" cfg.system.watchdog == null
  ) cfg.system.watchdog;

  services.journald.extraConfig = "SystemMaxUse=1G";
  documentation.nixos.enable = false; # man pages stay
  environment.enableAllTerminfo = true; # ssh from ghostty, kitty, ...

  environment.systemPackages = with pkgs; [
    dig
    mtr
    vim
  ];
}
