# The user's dotfiles: a user timer clones the chezmoi repository once and then pulls and applies
# it daily (`--force`: the repository wins over local edits of managed files). The system zsh stays
# the fallback; a failed run is a failed user unit (dev-health).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  u = config.dev.user;
in
lib.mkIf (u.dotfiles != null) {
  environment.systemPackages = [ pkgs.chezmoi ];

  systemd.user.services.dotfiles = {
    description = "Apply the dotfiles (chezmoi)";
    unitConfig.ConditionUser = u.name;
    path = [
      pkgs.chezmoi
      pkgs.git
    ];
    # No Restart=: a run waiting to restart is not "failed", and dev-health would not see it.
    serviceConfig.Type = "oneshot";
    script = ''
      if [ -d "$HOME/.local/share/chezmoi/.git" ]; then
        chezmoi update --force --no-tty
      else
        chezmoi init --apply --force --no-tty ${lib.escapeShellArg u.dotfiles}
      fi
    '';
  };
  systemd.user.timers.dotfiles = {
    wantedBy = [ "timers.target" ];
    unitConfig.ConditionUser = u.name;
    timerConfig = {
      # After the user manager starts (linger, at boot): the network is up by then.
      OnStartupSec = "5min";
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };
}
