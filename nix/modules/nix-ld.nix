# Software from outside Nix (§5.5 of the plan): mise's prebuilt runtimes (Python from
# python-build-standalone, Node, ...), the VS Code Server and npm CLIs are dynamically linked for
# a generic Linux. nix-ld provides the loader and a library set (extended when something fails);
# envfs resolves `#!/bin/bash` and `#!/usr/bin/env python3`.
{ lib, pkgs, ... }:
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
  systemd.user.extraConfig = ''
    DefaultEnvironment="NIX_LD=${ld}" "NIX_LD_LIBRARY_PATH=${libraryPath}"
  '';

  services.envfs.enable = lib.mkDefault true;
}
