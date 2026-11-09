# The vars schema (by area): everything a host's vars.nix can set, typed and validated at
# evaluation time; the modules only read `config.dev`. No secret values here (copied to the
# Nix store): secrets are files (dev.secrets, modules/secrets.nix).
{
  imports = [
    ./host.nix
    ./network.nix
    ./user.nix
    ./services.nix
  ];
}
