# The data disk (formatted once by hand, label dev.storage.dataLabel, never touched by an install),
# mounted in the initrd so activation can create homes on it. Without it the host does not boot, by
# design: nothing may write into an empty /data on the OS disk.
{ config, ... }:
let
  s = config.dev.storage;
in
{
  fileSystems.${s.dataDir} = {
    device = "/dev/disk/by-label/${s.dataLabel}";
    fsType = "ext4";
    neededForBoot = true;
    # The disk has no partition table: after growing it in Proxmox, the filesystem grows at the
    # next boot (or live: resize2fs /dev/disk/by-label/<label>).
    autoResize = true;
    options = [
      "noatime"
      "discard"
    ];
  };

  systemd.tmpfiles.rules = [
    "d ${s.dataDir}/home 0755 root root -"
  ];
}
