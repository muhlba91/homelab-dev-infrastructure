# Claude Code for the host's user: Anthropic's native build in ~/.local/bin (not nixpkgs, which lags
# by days and pins every version), on the `latest` channel. A user timer installs it once (the
# official installer's steps: the release manifest's checksum, then `claude install`) and runs
# `claude update` daily, so sessions that never start interactively (orchestrators, `claude -p`)
# still get updates. The binary runs through nix-ld; login stays manual (`claude`, then /login).
# A failed run is a failed user unit (dev-health).
{
  config,
  pkgs,
  ...
}:
let
  u = config.dev.user;
  platform =
    {
      x86_64-linux = "linux-x64";
      aarch64-linux = "linux-arm64";
    }
    .${pkgs.stdenv.hostPlatform.system};
in
{
  # ~/.local/bin in PATH (login shells), where `claude install` links the current version.
  environment.localBinInPath = true;
  # The system ripgrep (mise.nix) instead of the bundled one (the documented fix for search on
  # NixOS).
  environment.variables.USE_BUILTIN_RIPGREP = "0";

  systemd.user.services.claude-code-update = {
    description = "Install or update Claude Code";
    unitConfig.ConditionUser = u.name;
    path = [
      pkgs.curl
      pkgs.jq
      pkgs.coreutils
    ];
    # No Restart=: a run waiting to restart is not "failed", and dev-health would not see it.
    serviceConfig.Type = "oneshot";
    script = ''
      # As in login shells (the installer warns otherwise).
      export PATH="$HOME/.local/bin:$PATH"
      bin="$HOME/.local/bin/claude"
      if [ -x "$bin" ] && "$bin" --version >/dev/null 2>&1; then
        exec "$bin" update
      fi
      base=https://downloads.claude.ai/claude-code-releases
      version=$(curl -fsSL "$base/latest")
      if ! [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        echo "unexpected version from $base/latest: $version" >&2
        exit 1
      fi
      checksum=$(curl -fsSL "$base/$version/manifest.json" | jq -er '.platforms["${platform}"].checksum')
      tmp=$(mktemp -d)
      trap 'rm -rf "$tmp"' EXIT
      curl -fsSL -o "$tmp/claude" "$base/$version/${platform}/claude"
      echo "$checksum  $tmp/claude" | sha256sum --check --quiet -
      chmod +x "$tmp/claude"
      "$tmp/claude" install latest
    '';
  };
  systemd.user.timers.claude-code-update = {
    wantedBy = [ "timers.target" ];
    unitConfig.ConditionUser = u.name;
    timerConfig = {
      # After the user manager starts (linger, at boot), and at once when a deploy adds the timer.
      OnStartupSec = "5min";
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };
}
