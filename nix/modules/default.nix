# All modules. Which ones do something is decided by dev.* (vars).
{
  imports = [
    ./options
    ./helpers.nix
    ./secrets.nix
    ./base.nix
    ./nix.nix
    ./ssh.nix
    ./networking.nix
    ./firewall.nix
    ./time.nix
    ./storage.nix
    ./users.nix
    ./git.nix
    ./dotfiles.nix
    ./nix-ld.nix
    ./mise.nix
    ./claude-code.nix
    ./docker.nix
    ./coder.nix
    ./coder-provision.nix
    ./backup.nix
    ./vault-agent.nix
    ./fnox.nix
    ./health.nix
  ];
}
