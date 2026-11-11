# Claude Code for the host's user: Anthropic's native build in ~/.local/bin (not nixpkgs, which lags
# by days and pins every version), on the `latest` channel. A user timer installs it once and runs
# `claude update` daily, so sessions that never start interactively (orchestrators, `claude -p`)
# still get updates. The install follows Anthropic's documented verification: the release manifest's
# PGP signature against the pinned release-signing key (claude-code-release.asc, fingerprint checked
# at build), then the binary's checksum from that manifest, then `claude install`. The binary runs
# through nix-ld; login stays manual (`claude`, then /login). A failed or hanging run is a failed
# user unit (dev-health).
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
  # https://code.claude.com/docs/en/setup#binary-integrity-and-code-signing
  fingerprint = "31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE";
  keyring = pkgs.runCommand "claude-code-keyring" { nativeBuildInputs = [ pkgs.gnupg ]; } ''
    export GNUPGHOME=$(mktemp -d)
    gpg --batch --quiet --import ${./claude-code-release.asc}
    gpg --batch --with-colons --fingerprint | grep -qx 'fpr:::::::::${fingerprint}:' \
      || { echo "claude-code-release.asc is not the key ${fingerprint}" >&2; exit 1; }
    gpg --batch --dearmor < ${./claude-code-release.asc} > $out
  '';
  curl = "curl -fsSL --connect-timeout 15 --max-time 600 --retry 3";
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
      pkgs.gnupg
      pkgs.coreutils
    ];
    # No Restart=: a run waiting to restart is not "failed", and dev-health would not see it. A
    # hanging download fails instead of blocking the timer.
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "20min";
    };
    script = ''
      # As in login shells (the installer warns otherwise).
      export PATH="$HOME/.local/bin:$PATH"
      bin="$HOME/.local/bin/claude"
      if [ -x "$bin" ] && "$bin" --version >/dev/null 2>&1; then
        exec "$bin" update
      fi
      base=https://downloads.claude.ai/claude-code-releases
      version=$(${curl} "$base/latest")
      if ! [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$ ]]; then
        echo "unexpected version from $base/latest: $version" >&2
        exit 1
      fi
      tmp=$(mktemp -d)
      trap 'rm -rf "$tmp"' EXIT
      ${curl} -o "$tmp/manifest.json" "$base/$version/manifest.json"
      ${curl} -o "$tmp/manifest.json.sig" "$base/$version/manifest.json.sig"
      gpgv --keyring ${keyring} "$tmp/manifest.json.sig" "$tmp/manifest.json"
      checksum=$(jq -er '.platforms["${platform}"].checksum' "$tmp/manifest.json")
      ${curl} -o "$tmp/claude" "$base/$version/${platform}/claude"
      echo "$checksum  $tmp/claude" | sha256sum --check --quiet -
      chmod +x "$tmp/claude"
      "$tmp/claude" install latest
    '';
  };
  systemd.user.timers.claude-code-update = {
    wantedBy = [ "timers.target" ];
    unitConfig.ConditionUser = u.name;
    timerConfig = {
      # After the user manager starts (linger, at boot), and at once when a deploy adds the timer
      # (seen on the first deploy: the startup point has passed).
      OnStartupSec = "5min";
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };
}
