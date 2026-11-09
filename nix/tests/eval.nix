# Eval tests (flake check `eval`, lib.runTests) on the fixtures in tests/hosts, independent of
# the host data ./host injects: what the modules derive from the vars, and that invalid vars
# fail evaluation (the assertions and the typed options). Empty result = all pass.
{ lib, fixtures }:
let
  dev = fixtures.fixture-dev;
  minimal = fixtures.fixture-minimal;

  # Whether a fixture still evaluates with one more module (a failed assertion or a wrong
  # option value throws).
  evaluates =
    system: module:
    (builtins.tryEval
      (system.extendModules { modules = [ module ]; }).config.system.build.toplevel.drvPath
    ).success;
  fails = system: module: !(evaluates system module);
in
lib.runTests {
  testHostnames = {
    expr = lib.mapAttrs (_: s: s.config.networking.hostName) fixtures;
    expected = {
      fixture-dev = "fixture-dev";
      fixture-minimal = "fixture-minimal";
    };
  };

  # The qemu profile boots with either firmware and wipes only dev.hardware.disk.
  testBootLoader = {
    expr = {
      inherit (dev.config.boot.loader.grub) devices efiInstallAsRemovable;
      disks = lib.attrNames dev.config.disko.devices.disk;
    };
    expected = {
      devices = [ "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0" ];
      efiInstallAsRemovable = true;
      disks = [ "main" ];
    };
  };

  # The data disk: by label, in the initrd, never part of disko.
  testDataDisk = {
    expr = {
      inherit (dev.config.fileSystems."/data") device fsType neededForBoot;
    };
    expected = {
      device = "/dev/disk/by-label/data";
      fsType = "ext4";
      neededForBoot = true;
    };
  };

  # The user: pinned ids, home on /data, linger, no sudo, SSH keys outside the home.
  testUser = {
    expr =
      let
        u = dev.config.users.users.daniel;
      in
      {
        inherit (u)
          uid
          group
          home
          linger
          extraGroups
          ;
        subUid = map (r: r.startUid) u.subUidRanges;
        mutable = dev.config.users.mutableUsers;
      };
    expected = {
      uid = 1000;
      group = "users";
      home = "/data/home/daniel";
      linger = true;
      extraGroups = [ ];
      subUid = [ 100000 ];
      mutable = false;
    };
  };

  # git signs with the machine key's file when there is one, and not at all without.
  testGitSigning = {
    expr =
      map
        (
          s:
          let
            # programs.git.config is a list of attribute sets (merged in order).
            g = lib.foldl' lib.recursiveUpdate { } (lib.toList s.config.programs.git.config);
          in
          {
            sign = g.commit.gpgsign or false;
            format = g.gpg.format or null;
            key = g.user.signingkey or null;
          }
        )
        [
          dev
          minimal
        ];
    expected = [
      {
        sign = true;
        format = "ssh";
        key = "/var/lib/secrets/github-ssh-key";
      }
      {
        sign = false;
        format = null;
        key = null;
      }
    ];
  };

  # The secrets each fixture needs, and the machine key readable by the user only.
  testSecrets = {
    expr = {
      dev = lib.attrNames dev.config.dev.secrets;
      minimal = lib.attrNames minimal.config.dev.secrets;
      githubKey = {
        inherit (dev.config.dev.secrets.github-ssh-key) owner mode;
      };
    };
    expected = {
      dev = [
        "coder-admin-password"
        "github-ssh-key"
        "restic-password"
        "restic-s3"
        "ssh-host-key"
        "vault-role-id"
        "vault-secret-id"
      ];
      minimal = [ ];
      githubKey = {
        owner = "daniel";
        mode = "0400";
      };
    };
  };

  # Coder runs as the user (no own user, no createLocally), PostgreSQL on the data disk with
  # the peer map, the bootstrap as the user with the password as a credential.
  testCoder = {
    expr = {
      inherit (dev.config.services.coder) user group;
      inherit (dev.config.services.coder.database) createLocally username;
      coderUser = dev.config.users.users ? coder;
      pgDataDir = lib.hasPrefix "/data/postgresql/" dev.config.services.postgresql.dataDir;
      identMap = lib.hasInfix "coder daniel coder" dev.config.services.postgresql.identMap;
      configDir = dev.config.systemd.services.coder.environment.CODER_CONFIG_DIR;
      bootstrapUser = dev.config.systemd.services.coder-bootstrap.serviceConfig.User;
      bootstrapCredential = dev.config.systemd.services.coder-bootstrap.serviceConfig.LoadCredential;
      minimal = minimal.config.services.coder.enable;
    };
    expected = {
      user = "daniel";
      group = "users";
      createLocally = false;
      username = "coder";
      coderUser = false;
      pgDataDir = true;
      identMap = true;
      configDir = "/data/coder/config";
      bootstrapUser = "daniel";
      bootstrapCredential = "admin-password:/var/lib/secrets/coder-admin-password";
      minimal = false;
    };
  };

  # Static addresses; IPv6 with router advertisements (route and DNS), never SLAAC or DHCPv6.
  testNetwork = {
    expr =
      map
        (
          s:
          let
            n = s.config.systemd.network.networks."10-lan";
          in
          {
            inherit (n) address;
            ra = n.networkConfig.IPv6AcceptRA;
            raConfig = n.ipv6AcceptRAConfig or { };
            routes = map (r: r.Gateway) n.routes;
          }
        )
        [
          dev
          minimal
        ];
    expected = [
      {
        address = [
          "10.46.60.1/16"
          "fd46::60:1/64"
        ];
        ra = true;
        raConfig = {
          UseAutonomousPrefix = false;
          DHCPv6Client = false;
          UseDNS = true;
          UseDomains = false;
        };
        routes = [ "10.46.0.1" ];
      }
      {
        address = [ "10.46.60.2/16" ];
        ra = false;
        raConfig = { };
        routes = [ "10.46.0.1" ];
      }
    ];
  };

  # SSH (and Coder's port and Docker's open ports when enabled) only from the trusted networks.
  testFirewall = {
    expr =
      map
        (s: {
          ssh = lib.hasInfix "ip saddr { 10.0.0.0/8 } tcp dport { 22" s.config.networking.firewall.extraInputRules;
          coder = lib.hasInfix ", 3000" s.config.networking.firewall.extraInputRules;
          docker = lib.hasInfix ", 8000-8999 }" s.config.networking.firewall.extraInputRules;
          open = s.config.networking.firewall.allowedTCPPorts;
        })
        [
          dev
          minimal
        ];
    expected = [
      {
        ssh = true;
        coder = true;
        docker = true;
        open = [ ];
      }
      {
        ssh = true;
        coder = false;
        docker = false;
        open = [ ];
      }
    ];
  };

  # nix-ld for prebuilt binaries (also in the user manager), mise's system config, the unfree
  # packages allowed (Terraform only with Coder).
  testDevEnv = {
    expr = {
      nixLd = dev.config.programs.nix-ld.enable;
      userManager = lib.hasInfix "NIX_LD=" dev.config.systemd.user.extraConfig;
      envfs = dev.config.services.envfs.enable;
      # The repositories' mise.toml set min_version.
      miseVersion = lib.versionAtLeast dev.pkgs.mise.version "2026.10.0";
      mise =
        lib.hasInfix ''trusted_config_paths = ["/data/home/daniel/workspaces"]''
          dev.config.environment.etc."mise/config.toml".text;
      unfree = map (s: lib.sort lib.lessThan s.config.dev.unfree) [
        dev
        minimal
      ];
    };
    expected = {
      nixLd = true;
      userManager = true;
      envfs = true;
      miseVersion = true;
      mise = true;
      unfree = [
        [
          "terraform"
          "vault"
        ]
        [ "vault" ]
      ];
    };
  };

  # Rootless Docker for the user only (no docker group), never restarted by a deploy, localhost
  # as the default bind address, DOCKER_HOST in the user manager (next to nix-ld's variables).
  testDocker = {
    expr = {
      rootless = map (s: s.config.virtualisation.docker.rootless.enable) [
        dev
        minimal
      ];
      daemon = dev.config.virtualisation.docker.enable;
      ip =
        let
          d = dev.config.virtualisation.docker.rootless.daemon.settings;
        in
        [
          d.ip
          d.default-network-opts.bridge."com.docker.network.bridge.host_binding_ipv4"
        ];
      condition = dev.config.systemd.user.services.docker.unitConfig.ConditionUser;
      inherit (dev.config.systemd.user.services.docker) restartIfChanged;
      userManager = map (v: lib.hasInfix v dev.config.systemd.user.extraConfig) [
        "DOCKER_HOST=unix:///run/user/1000/docker.sock"
        "NIX_LD="
      ];
      inherit (dev.config.users.users.daniel) extraGroups;
    };
    expected = {
      rootless = [
        true
        false
      ];
      daemon = false;
      ip = [
        "127.0.0.1"
        "127.0.0.1"
      ];
      condition = "daniel";
      restartIfChanged = false;
      userManager = [
        true
        true
      ];
      extraGroups = [ ];
    };
  };

  # Coder's database backed up with restic to <repository>/coder, nightly; only with a repository.
  testBackup = {
    expr = {
      repository = dev.config.services.restic.backups.coder.repository;
      inherit (dev.config.services.restic.backups.coder) passwordFile environmentFile paths;
      minimal = minimal.config.services.restic.backups ? coder;
    };
    expected = {
      repository = "s3:https://s3.fr-par.scw.cloud/fixture-backups/dev/fixture-dev/coder";
      passwordFile = "/var/lib/secrets/restic-password";
      environmentFile = "/var/lib/secrets/restic-s3";
      paths = [ "/data/backup/coder" ];
      minimal = false;
    };
  };

  # The Vault Agent as its own pinned user, the only reader of the secret ID; the token sink for
  # the group vault-token (the user); the secret ID file is never deleted by the agent; the CLI
  # finds the token through the helper, in shells and in the user manager.
  testVault = {
    expr =
      let
        c = dev.config;
        a = c.services.vault-agent.instances.dev;
      in
      {
        agentUser = {
          inherit (c.users.users.vault-agent) uid group;
        };
        tokenGroup = {
          inherit (c.users.groups.vault-token) gid members;
        };
        secretId = {
          inherit (c.dev.secrets.vault-secret-id) owner group mode;
        };
        removeSecretId =
          (builtins.head a.settings.auto_auth.method).config.remove_secret_id_file_after_reading;
        sink = (builtins.head a.settings.auto_auth.sink).config;
        addr = c.environment.variables.VAULT_ADDR;
        configPath = c.environment.variables ? VAULT_CONFIG_PATH;
        userManager = lib.hasInfix "VAULT_ADDR=https://vault.example.org:8200" c.systemd.user.extraConfig;
        minimal = minimal.config.services.vault-agent.instances ? dev;
      };
    expected = {
      agentUser = {
        uid = 950;
        group = "vault-token";
      };
      tokenGroup = {
        gid = 950;
        members = [ "daniel" ];
      };
      secretId = {
        owner = "vault-agent";
        group = "vault-token";
        mode = "0400";
      };
      removeSecretId = false;
      sink = {
        path = "/run/vault-agent/token";
        mode = 288;
      };
      addr = "https://vault.example.org:8200";
      configPath = true;
      userManager = true;
      minimal = false;
    };
  };

  # Invalid vars fail evaluation.
  testInvalid = {
    expr = {
      lowUid = fails minimal { dev.user.uid = lib.mkForce 999; };
      badMac = fails minimal { dev.network.mac = lib.mkForce "bc:24:11:00:00"; };
      badCidr = fails minimal { dev.network.v4.address = lib.mkForce "10.46.60.2"; };
      v6NoRoute = fails dev {
        dev.network.v6 = lib.mkForce {
          address = "fd46::60:1/64";
          acceptRA = false;
        };
      };
      nameMismatch = fails minimal { dev.host.name = lib.mkForce "other"; };
      badPort = fails dev { dev.docker.trustedPorts = lib.mkForce [ "8000:8999" ]; };
      vaultNoAddress = fails dev { dev.vault.address = lib.mkForce null; };
      deployableWithoutKeys = fails minimal {
        dev.meta.deployable = lib.mkForce true;
        dev.mgmt.sshKeys = lib.mkForce [ ];
      };
      valid = evaluates minimal { };
    };
    expected = {
      lowUid = true;
      badMac = true;
      badCidr = true;
      v6NoRoute = true;
      nameMismatch = true;
      badPort = true;
      vaultNoAddress = true;
      deployableWithoutKeys = true;
      valid = true;
    };
  };
}
