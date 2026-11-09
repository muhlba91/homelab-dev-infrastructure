# Vars schema: the host's (human) user and the storage layout its home lives on.
{ lib, ... }:
let
  inherit (lib) types;
  inherit (import ./types.nix { inherit lib; })
    str
    strD
    nullable
    strList
    typed
    typedD
    ;
in
{
  options.dev = {
    user = {
      name = str "Login name of the host's user.";
      uid = typed (types.ints.between 1000 59999) ''
        Pinned user id: files on /data keep their owner across reinstalls (a reinstall wipes
        /var/lib/nixos, so an allocated id could change).
      '';
      sshKeys = strList [ ] "Public keys allowed for the user (the static keys, assets/ssh/*.pub).";
      git = {
        name = str "Author name of the commits made on the host.";
        email = str "Author e-mail; the GitHub machine key signs for it (git's allowed signers).";
      };
      githubKey = nullable types.str ''
        Public half of the GitHub machine key (`<type> <base64>`; the private half is the secret
        `github-ssh-key`): git's allowed signers. null = no machine key (git does not sign).
      '';
    };

    unfree = typedD (types.listOf types.str) [ ] ''
      Unfree nixpkgs packages allowed on the host, by name (`lib.getName`); modules add the ones
      they need (one predicate: two modules cannot each set allowUnfreePredicate).
    '';

    storage = {
      dataLabel = strD "data" ''
        Filesystem label of the data disk (formatted once by hand, never by an install). Mounted
        at storage.dataDir in the initrd: without it the host does not boot.
      '';
      dataDir = strD "/data" "Mount point of the data disk (homes, service state).";
    };
  };
}
