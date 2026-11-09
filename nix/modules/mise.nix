# The development environment of the host's user (§5.5 of the plan): mise for tool versions
# (runtimes run through nix-ld), direnv, git and the CLI tools from nixpkgs, configured
# system-wide (home-manager vs chezmoi is decided later).
{
  config,
  pkgs,
  pkgsUnstable,
  ...
}:
let
  cfg = config.dev;
  home = "${cfg.storage.dataDir}/home/${cfg.user.name}";
in
{
  # mise from nixos-unstable: the repositories require a newer mise (`min_version`) than the
  # release ships.
  nixpkgs.overlays = [ (_: _: { inherit (pkgsUnstable) mise; }) ];

  # The Vault CLI is BSL-licensed (unfree in nixpkgs).
  dev.unfree = [ "vault" ];

  environment.systemPackages = with pkgs; [
    mise
    gh
    vault
    tmux
    ripgrep
    fd
    jq
    yq-go
    htop
    gnumake
    unzip
  ];

  programs.direnv.enable = true;

  # mise in interactive shells; workspaces and scripts call `mise exec`/`mise x` or use the shims.
  programs.zsh.interactiveShellInit = ''
    eval "$(${pkgs.mise}/bin/mise activate zsh)"
  '';
  programs.bash.interactiveShellInit = ''
    eval "$(${pkgs.mise}/bin/mise activate bash)"
  '';

  # mise is updated with the flake (nixos-unstable), not by itself: no "version available" warning.
  environment.variables.MISE_HIDE_UPDATE_WARNING = "1";

  # The global (system) mise configuration: prebuilt Python and Node (mise from nixpkgs compiles
  # Node by default), the workspaces trusted.
  environment.etc."mise/config.toml".text = ''
    [settings]
    python.compile = false
    node.compile = false
    trusted_config_paths = ["${home}/workspaces"]
  '';
}
