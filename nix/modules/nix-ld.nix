# Generic-Linux binaries (mise runtimes, the VS Code Server, npm CLIs): nix-ld provides the loader
# and libraries (extend the list when something fails), envfs `#!/bin/bash` and `#!/usr/bin/env`.
{
  lib,
  pkgs,
  dlib,
  ...
}:
let
  ld = "/run/current-system/sw/share/nix-ld/lib/ld.so";
  libraryPath = "/run/current-system/sw/share/nix-ld/lib";
in
{
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc.lib # libstdc++, libgcc_s
      zlib
      zstd
      openssl
      libffi
      bzip2
      xz
      ncurses
      readline
      sqlite
      expat
      libxml2
      libxslt
      libuuid
      gdbm
      icu
      curl
      glib
    ];
  };

  # The module sets NIX_LD* for login sessions only; the user manager (workspace agents, user
  # services) gets them here.
  systemd.user.extraConfig = dlib.userEnv {
    NIX_LD = ld;
    NIX_LD_LIBRARY_PATH = libraryPath;
  };

  services.envfs.enable = lib.mkDefault true;
}
