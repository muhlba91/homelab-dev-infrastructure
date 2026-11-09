{
  description = "NixOS dev hosts: one module set, one generated vars file per host, deployed with deploy-rs";

  inputs = {
    # Stable release (supported until 2026-12-31); Renovate proposes the next one.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Host data: <host>/vars.nix (sets `dev.*`, schema in modules/options/), rendered by
    # Pulumi and injected by ./host (--override-input). Default: the fixtures. Copied to the
    # Nix store: never secrets.
    hosts = {
      url = "path:./tests/hosts";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      deploy-rs,
      disko,
      hosts,
      ...
    }:
    let
      inherit (nixpkgs) lib;

      # The hosts of a folder of host data: one directory per host, holding its vars.nix.
      namesIn = dir: lib.attrNames (lib.filterAttrs (_: t: t == "directory") (builtins.readDir dir));
      hostNames = namesIn hosts;

      # Hand-written hardware/boot profiles: hardware/<profile>.nix, chosen per host by
      # dev.hardware.profile (modules/options/host.nix reads the same directory for its enum).
      hardwareProfile = name: ./hardware + "/${name}.nix";

      # Where Nix runs: the podman container on the Mac (aarch64-linux), CI runners and the
      # hosts (x86_64-linux).
      systems = [
        "aarch64-linux"
        "x86_64-linux"
      ];

      # The host's dev.* values, evaluated on their own (cheap: no nixpkgs needed)
      # so the flake can pick the hardware profile and the deploy target statically.
      hostCfg =
        vars:
        (lib.evalModules {
          modules = [
            ./modules/options
            vars
          ];
          specialArgs = { inherit lib; };
        }).config.dev;

      mkHost =
        dir: host:
        let
          vars = dir + "/${host}/vars.nix";
        in
        lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            disko.nixosModules.disko
            ./modules
            vars
            (hardwareProfile (hostCfg vars).hardware.profile)
            (
              { config, ... }:
              {
                assertions = [
                  {
                    assertion = config.dev.host.name == host;
                    message = "dev.host.name (${config.dev.host.name}) must equal the host directory name (${host})";
                  }
                ];
              }
            )
          ];
        };

      hostsIn = dir: lib.genAttrs (namesIn dir) (mkHost dir);

      # deploy-rs as packaged in nixpkgs (in cache.nixos.org: nothing to compile), with the
      # flake input's lib on top (as its README describes): `deploy` and the activation tool on
      # the host are then the same package.
      deployLib =
        (import nixpkgs {
          system = "x86_64-linux";
          overlays = [
            deploy-rs.overlays.default
            (_: prev: {
              deploy-rs = {
                inherit (nixpkgs.legacyPackages.x86_64-linux) deploy-rs;
                inherit (prev.deploy-rs) lib;
              };
            })
          ];
        }).deploy-rs.lib;
      hostCfgOf = host: hostCfg (hosts + "/${host}/vars.nix");
      deployableHosts = lib.filter (h: (hostCfgOf h).meta.deployable) hostNames;
      # Sort key of the deploy order: meta.deployOrder, hosts without one last (the sort is
      # stable, so ties stay sorted by name).
      deployRank =
        host:
        let
          order = (hostCfgOf host).meta.deployOrder;
        in
        if order == null then 9223372036854775807 else order;
    in
    {
      # One configuration per directory under `hosts`.
      nixosConfigurations = hostsIn hosts;

      # `./host hosts`, one line each: "<name> deployable=<bool> automated=<bool> mgmt=<address>"
      # (from the host data alone, no nixpkgs), in deploy order (meta.deployOrder; none last, by
      # name). automated = deployable and meta.deployAutomated: CI deploys exactly these.
      hostList = lib.concatMapStrings (
        host:
        let
          h = hostCfgOf host;
        in
        "${host} deployable=${lib.boolToString h.meta.deployable} automated=${
          lib.boolToString (h.meta.deployable && h.meta.deployAutomated)
        } mgmt=${h.mgmt.address}\n"
      ) (lib.sortOn deployRank hostNames);

      # `./host` connects to a deployable host with this: "<mgmt address>[ <host key>]" (with
      # a pinned host key, mgmt.hostKey, it is the host's known_hosts line).
      hostTarget = lib.genAttrs deployableHosts (
        host:
        let
          inherit (hostCfgOf host) mgmt;
        in
        toString ([ mgmt.address ] ++ lib.optional (mgmt.hostKey != null) mgmt.hostKey)
      );

      # `./host dump <host>`: the parts of a host's configuration that matter (tests/dump.nix).
      hostDump = lib.mapAttrs (_: system: import ./tests/dump.nix system.config) self.nixosConfigurations;

      # `deploy .#<host>` (use ./host deploy <host>). The first install of a new VM is
      # `nixos-anywhere` (./host install <host>), not deploy-rs.
      deploy.nodes = lib.genAttrs deployableHosts (host: {
        hostname = (hostCfgOf host).mgmt.address;
        sshUser = "deploy";
        user = "root";
        # The host builds itself: the Mac's container is aarch64, and from CI it fetches from
        # cache.nixos.org directly.
        remoteBuild = true;
        magicRollback = true;
        autoRollback = true;
        confirmTimeout = 120;
        profiles.system.path = deployLib.activate.nixos self.nixosConfigurations.${host};
      });

      # tests/checks.nix (deploy-rs' own checks would build every host system).
      checks = lib.genAttrs systems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        import ./tests/checks.nix {
          inherit pkgs lib;
          configurations = self.nixosConfigurations;
          # The eval tests always use the fixtures, whatever `hosts` is overridden with.
          fixtures = hostsIn ./tests/hosts;
          inherit (self) deploy;
          deploySchema = deploy-rs + "/interface.json";
          src = lib.fileset.toSource {
            root = ./.;
            fileset = lib.fileset.unions [
              (lib.fileset.fileFilter (f: f.hasExt "nix") ./.)
              ./statix.toml
              ./host
              ./nx
              ./secrets-sync.sh
            ];
          };
        }
      );

      # `nix fmt` (./host fmt): nixfmt (RFC 166, default settings) over the tree; the `lint`
      # check runs the same nixfmt read-only. Root = this flake (works without git).
      formatter = lib.genAttrs systems (
        system:
        nixpkgs.legacyPackages.${system}.nixfmt-tree.override {
          settings = {
            tree-root-file = "flake.nix";
          };
        }
      );

      devShells = lib.genAttrs systems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.deploy-rs
              pkgs.nixos-anywhere
              pkgs.openssh # ssh/nix copy to the host (also inside the ./nx container)
              pkgs.git
              pkgs.nixfmt
            ];
          };
        }
      );
    };
}
