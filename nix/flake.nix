{
  description = "NixOS dev hosts: one module set, one generated vars file per host, deployed with deploy-rs";

  inputs = {
    # Stable release; Renovate proposes the next one.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Single packages that must be newer than the release (an overlay per package; see the
    # modules using `pkgsUnstable`). Updated with flake.lock.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

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
    # Nix store: never secrets. install.sh matches the url line verbatim.
    hosts = {
      url = "path:./tests/hosts";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      deploy-rs,
      disko,
      hosts,
      ...
    }:
    let
      inherit (nixpkgs) lib;

      hostData = import ./lib/hosts.nix { inherit lib; };
      selected = hostData.of hosts;

      # Hand-written hardware/boot profiles: hardware/<profile>.nix, chosen per host by
      # dev.hardware.profile (modules/options/host.nix reads the same directory for its enum).
      hardwareProfile = name: ./hardware + "/${name}.nix";

      # Systems the checks and the devShell run on (the hosts are x86_64-linux).
      systems = [
        "aarch64-linux"
        "x86_64-linux"
      ];

      mkHost =
        dir: host:
        let
          vars = dir + "/${host}/vars.nix";
        in
        lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            pkgsUnstable = nixpkgs-unstable.legacyPackages.x86_64-linux;
          };
          modules = [
            disko.nixosModules.disko
            ./modules
            vars
            (hardwareProfile (hostData.cfg vars).hardware.profile)
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

      hostsIn = dir: lib.genAttrs (hostData.of dir).names (mkHost dir);

      # deploy-rs from nixpkgs (binary cache) with the input's lib: `deploy` and the activation
      # tool on the host are the same package.
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
    in
    {
      # One configuration per directory under `hosts`.
      nixosConfigurations = hostsIn hosts;

      # `./host hosts` and `./host`'s targets (lib/hosts.nix).
      hostList = selected.list;
      hostTarget = selected.target;

      # `./host dump <host>`: the parts of a host's configuration that matter (tests/dump.nix).
      hostDump = lib.mapAttrs (_: system: import ./tests/dump.nix system.config) self.nixosConfigurations;

      # `deploy .#<host>` (use ./host deploy <host>). The first install of a new VM is
      # `nixos-anywhere` (./host install <host>), not deploy-rs.
      deploy.nodes = lib.genAttrs selected.deployable (host: {
        hostname = (selected.cfgOf host).mgmt.address;
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
          # The hosts' Terraform (unfree: cache.nixos.org has no build, the check builds it once).
          inherit
            (import nixpkgs {
              inherit system;
              config.allowUnfreePredicate = p: lib.getName p == "terraform";
            })
            terraform
            ;
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
              ./install.sh
              ./coder/templates
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
