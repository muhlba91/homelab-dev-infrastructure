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
  # `./host hosts` (CI deploys the automated hosts from it) and `./host`'s targets.
  testHostData = {
    expr =
      let
        d = (import ../lib/hosts.nix { inherit lib; }).of ./hosts;
      in
      {
        inherit (d) list target deployable;
      };
    expected = {
      list = ''
        fixture-dev deployable=true automated=true mgmt=10.46.60.1
        fixture-minimal deployable=false automated=false mgmt=10.46.60.2
      '';
      target.fixture-dev = "10.46.60.1 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFhl/9WAbovwuyCeVz+1yll3s5SVzWSnukMPnLs7a1ri fixture-host";
      deployable = [ "fixture-dev" ];
    };
  };

  # `./host dump` evaluates.
  testDump = {
    expr = builtins.attrNames (import ./dump.nix minimal.config) != [ ];
    expected = true;
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

  # The secrets each fixture needs, all listed in /etc/dev-secrets (prune keeps them), and the
  # machine key readable by the user only.
  testSecrets = {
    expr = {
      dev = lib.attrNames dev.config.dev.secrets;
      minimal = lib.attrNames minimal.config.dev.secrets;
      listed =
        dev.config.environment.etc.dev-secrets.text
        == lib.concatLines (lib.attrNames dev.config.dev.secrets);
      githubKey = {
        inherit (dev.config.dev.secrets.github-ssh-key) owner mode;
      };
    };
    expected = {
      dev = [
        "coder-admin-password"
        "coder-oidc"
        "github-ssh-key"
        "restic-password"
        "restic-s3"
        "ssh-host-key"
        "vault-role-id"
        "vault-secret-id"
      ];
      minimal = [ ];
      listed = true;
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
      bootstrapAdmin = lib.hasInfix "--arg e admin@fixture-dev.fixture.internal.example" dev.config.systemd.services.coder-bootstrap.script;
      inherit (dev.config.services.coder) accessUrl wildcardAccessUrl;
      proxy = {
        inherit (dev.config.systemd.services.coder.environment)
          CODER_PROXY_TRUSTED_HEADERS
          CODER_PROXY_TRUSTED_ORIGINS
          CODER_SECURE_AUTH_COOKIE
          CODER_DERP_FORCE_WEBSOCKETS
          ;
      };
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
      bootstrapAdmin = true;
      accessUrl = "https://coder.example.org";
      wildcardAccessUrl = "*.coder.example.org";
      proxy = {
        CODER_PROXY_TRUSTED_HEADERS = "X-Forwarded-For";
        CODER_PROXY_TRUSTED_ORIGINS = "10.0.0.0/8,fc00::/7,2001:678:dc0::/48";
        CODER_SECURE_AUTH_COOKIE = "true";
        CODER_DERP_FORCE_WEBSOCKETS = "true";
      };
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

  # fnox: the dev profile and the managed global config, in shells and the user manager.
  testFnox = {
    expr =
      let
        c = dev.config;
        global = builtins.fromTOML c.environment.etc."fnox/config.toml".text;
      in
      {
        profile = c.environment.variables.FNOX_PROFILE;
        configDir = c.environment.variables.FNOX_CONFIG_DIR;
        userManager = lib.hasInfix "FNOX_PROFILE=dev" c.systemd.user.extraConfig;
        provider = global.providers.dev-infrastructure;
        source = {
          inherit (global.profiles.dev.secrets.GCP_SOURCE_CREDENTIALS) provider value env;
        };
        minimal = minimal.config.environment.etc ? "fnox/config.toml";
      };
    expected = {
      profile = "dev";
      configDir = "/etc/fnox";
      userManager = true;
      provider = {
        type = "vault";
        path = "dev-infrastructure";
        credential_command = "vault print token";
      };
      source = {
        provider = "dev-infrastructure";
        value = "gcp-dev-fixture-dev/credentials";
        env = false;
      };
      minimal = false;
    };
  };

  # Invalid vars fail evaluation.
  # Every template's required_version (`>= X`) accepts the hosts' Terraform: a raised minimum fails
  # the template push and with it the deploy.
  testTemplateTerraform = {
    expr = lib.mapAttrs (
      name: _:
      let
        # Line by line: a regex over the whole file backtracks forever in Nix's matcher.
        versions = lib.concatMap (
          l:
          let
            m = builtins.match " *required_version = \">= ([0-9.]+)\"" l;
          in
          if m == null then [ ] else m
        ) (lib.splitString "\n" (builtins.readFile (../coder/templates + "/${name}/main.tf")));
      in
      versions != [ ] && lib.all (lib.versionAtLeast dev.pkgs.terraform.version) versions
    ) (builtins.readDir ../coder/templates);
    expected = {
      local-dir = true;
    };
  };

  # Dotfiles: chezmoi for the host's user only, cloned once, then updated; none without the URL.
  testDotfiles = {
    expr = {
      condition = dev.config.systemd.user.services.dotfiles.unitConfig.ConditionUser;
      init = lib.hasInfix "chezmoi init --apply --force --no-tty https://github.com/example/dotfiles.git" dev.config.systemd.user.services.dotfiles.script;
      timer = dev.config.systemd.user.timers.dotfiles.wantedBy;
      minimal = minimal.config.systemd.user.services ? dotfiles;
      ssh = fails dev { dev.user.dotfiles = lib.mkForce "git@github.com:example/dotfiles.git"; };
    };
    expected = {
      condition = "daniel";
      init = true;
      timer = [ "timers.target" ];
      minimal = false;
      ssh = true;
    };
  };

  # SSO with OIDC: the client ID in the environment, the secret only from the environment file.
  testCoderOIDC = {
    expr =
      let
        s = dev.config.systemd.services.coder;
      in
      {
        inherit (s.environment)
          CODER_OIDC_ISSUER_URL
          CODER_OIDC_CLIENT_ID
          CODER_OIDC_SIGN_IN_TEXT
          CODER_OIDC_ALLOW_SIGNUPS
          ;
        file = s.serviceConfig.EnvironmentFile;
        secret = dev.config.dev.secrets ? coder-oidc;
        minimal = minimal.config.dev.secrets ? coder-oidc;
        direct = fails dev { dev.coder.accessUrl = lib.mkForce null; };
        trailingSlash = fails dev { dev.coder.oidc.issuerUrl = lib.mkForce "https://id.example.org/"; };
      };
    expected = {
      CODER_OIDC_ISSUER_URL = "https://id.example.org";
      CODER_OIDC_CLIENT_ID = "123456789@dev";
      CODER_OIDC_SIGN_IN_TEXT = "Sign in with SSO";
      CODER_OIDC_ALLOW_SIGNUPS = "true";
      file = "/var/lib/secrets/coder-oidc";
      secret = true;
      minimal = false;
      direct = true;
      trailingSlash = true;
    };
  };

  # Coder without a proxy: the default URL, no trusted proxy headers. The template's agent URL
  # uses dev.coder.port.
  testCoderDirect = {
    expr =
      let
        c = (dev.extendModules { modules = [ { dev.coder.accessUrl = lib.mkForce null; } ]; }).config;
        env = c.systemd.services.coder.environment;
      in
      {
        inherit (c.services.coder) accessUrl;
        proxied = env ? CODER_PROXY_TRUSTED_HEADERS || env ? CODER_SECURE_AUTH_COOKIE;
        templatePort = lib.hasInfix "http://127.0.0.1:${toString c.dev.coder.port}" (
          builtins.readFile ../coder/templates/local-dir/main.tf
        );
      };
    expected = {
      accessUrl = "http://10.46.60.1:3000";
      proxied = false;
      templatePort = true;
    };
  };

  # A pinned host key is sshd's only key (no generated fallback); passwords and root are off.
  testSsh = {
    expr = {
      hostKeys = dev.config.services.openssh.hostKeys;
      keygen = dev.config.systemd.services.sshd-keygen.enable;
      check = dev.config.system.activationScripts ? devHostKey;
      minimalKeygen = minimal.config.systemd.services.sshd-keygen.enable;
      minimalCheck = minimal.config.system.activationScripts ? devHostKey;
      inherit (dev.config.services.openssh.settings) PasswordAuthentication PermitRootLogin;
    };
    expected = {
      hostKeys = [
        {
          path = "/var/lib/secrets/ssh-host-key";
          type = "ed25519";
        }
      ];
      keygen = false;
      check = true;
      minimalKeygen = true;
      minimalCheck = false;
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # The watchdog ("0s" disables it) and the garbage collection's two limits.
  testSystem = {
    expr = {
      watchdog = dev.config.systemd.settings.Manager.RuntimeWatchdogSec;
      watchdogOff =
        (minimal.extendModules { modules = [ { dev.system.watchdog = lib.mkForce "0s"; } ]; })
        .config.systemd.settings.Manager
          ? RuntimeWatchdogSec;
      gcKeep = lib.hasSuffix "--delete-generations +3" dev.config.systemd.services.nix-gc.preStart;
      gcAge = dev.config.nix.gc.options;
    };
    expected = {
      watchdog = "60s";
      watchdogOff = false;
      gcKeep = true;
      gcAge = "--delete-older-than 7d";
    };
  };

  # Every secret lives in the directory ./host pushes to (SECRETS_DIR in nix/host).
  testSecretsDir = {
    expr = lib.all (s: lib.hasPrefix "/var/lib/secrets/" s.path) (
      lib.attrValues dev.config.dev.secrets
    );
    expected = true;
  };

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
