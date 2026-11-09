# Fixture: only the required values plus a deploy key (IPv4 only, no pinned host key, no machine
# key, no Coder): the defaults of the schema. Evaluation only.
{
  dev = {
    meta.deployable = false;

    host = {
      name = "fixture-minimal";
      hostname = "fixture-minimal";
      domain = "fixture.internal.example";
    };

    mgmt = {
      address = "10.46.60.2";
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFhl/9WAbovwuyCeVz+1yll3s5SVzWSnukMPnLs7a1ri fixture-deploy"
      ];
    };

    hardware.disk = "/dev/sda";

    network = {
      mac = "bc:24:11:00:00:02";
      iface = "lan0";
      v4 = {
        address = "10.46.60.2/16";
        gateway = "10.46.0.1";
      };
    };

    user = {
      name = "user";
      uid = 1001;
      git = {
        name = "Fixture User";
        email = "fixture@example.org";
      };
    };
  };
}
