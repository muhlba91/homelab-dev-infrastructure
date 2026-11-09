# Storage (§5.4 of the plan): the data disk, formatted once by hand (ext4, label
# dev.storage.dataLabel) and never touched by an install, is mounted at dev.storage.dataDir in the
# initrd (neededForBoot): before the activation creates homes and applies ownership. Without the
# disk the host does not boot, deliberately: nothing writes into an empty /data on the OS disk.
# The OS disk (disko, hardware/<profile>.nix) is wiped by every install.
{ config, ... }:
let
  s = config.dev.storage;
in
{
  fileSystems.${s.dataDir} = {
    device = "/dev/disk/by-label/${s.dataLabel}";
    fsType = "ext4";
    neededForBoot = true;
    options = [
      "noatime"
      "discard"
    ];
  };

  systemd.tmpfiles.rules = [
    "d ${s.dataDir}/home 0755 root root -"
  ];
}
