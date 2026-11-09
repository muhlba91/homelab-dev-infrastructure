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
    ./coder.nix
    ./health.nix
  ];
}
