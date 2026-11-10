# Fixture: everything on (IPv6, pinned host key, machine key, Docker with open ports, Coder with
# backups and a proxied URL, Vault Agent).
# Evaluation only (meta.deployable = false); the keys are throw-away public keys.
{
  dev = {
    meta.deployable = false;
    meta.deployOrder = 200;

    host = {
      name = "fixture-dev";
      hostname = "fixture-dev";
      domain = "fixture.internal.example";
    };

    mgmt = {
      address = "10.46.60.1";
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFhl/9WAbovwuyCeVz+1yll3s5SVzWSnukMPnLs7a1ri fixture-deploy"
      ];
      hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFhl/9WAbovwuyCeVz+1yll3s5SVzWSnukMPnLs7a1ri fixture-host";
    };

    hardware = {
      profile = "qemu";
      disk = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0";
    };

    network = {
      mac = "bc:24:11:00:00:01";
      iface = "lan0";
      v4 = {
        address = "10.46.60.1/16";
        gateway = "10.46.0.1";
      };
      v6.address = "fd46::60:1/64";
    };

    user = {
      name = "daniel";
      uid = 1000;
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFhl/9WAbovwuyCeVz+1yll3s5SVzWSnukMPnLs7a1ri fixture-user"
      ];
      git = {
        name = "Fixture User";
        email = "fixture@example.org";
      };
      githubKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFhl/9WAbovwuyCeVz+1yll3s5SVzWSnukMPnLs7a1ri fixture-github";
    };

    docker = {
      enable = true;
      trustedPorts = [ "8000-8999" ];
    };
    coder = {
      enable = true;
      accessUrl = "https://coder.example.org";
      wildcardAccessUrl = "*.coder.example.org";
    };
    backup.repository = "s3:https://s3.fr-par.scw.cloud/fixture-backups/dev/fixture-dev";
    vault = {
      enable = true;
      address = "https://vault.example.org:8200";
    };
  };
}
