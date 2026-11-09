# All modules. Which ones do something is decided by dev.* (vars).
{
  imports = [
    ./options
    ./helpers.nix
    ./secrets.nix
    ./base.nix
    ./networking.nix
    ./firewall.nix
    ./time.nix
    ./storage.nix
    ./users.nix
    ./nix-ld.nix
    ./mise.nix
    ./docker.nix
    ./coder.nix
    ./backup.nix
    ./vault-agent.nix
    ./health.nix
  ];
}
