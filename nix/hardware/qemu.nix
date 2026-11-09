# Hardware profile: x86_64 QEMU/KVM guest (Proxmox, a cloud VM). Boots with either firmware:
# GRUB is installed for legacy BIOS (BIOS boot partition) and for UEFI (the removable fallback
# path on the ESP, so no EFI variables are needed), so a VM can switch between SeaBIOS and OVMF
# without a reinstall.
# Selected by dev.hardware.profile (= this file name); hand-written, never generated.
# The OS disk only (dev.hardware.disk): the data disk is never part of disko (modules/storage.nix).
{ config, modulesPath, ... }:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  # disko adds the disk to boot.loader.grub.devices (it has an EF02 partition).
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    configurationLimit = config.dev.system.gc.keep;
  };
  services.qemuGuest.enable = true;

  disko.devices.disk.main = {
    type = "disk";
    device = config.dev.hardware.disk;
    content = {
      type = "gpt";
      partitions = {
        boot = {
          size = "1M";
          type = "EF02";
        };
        ESP = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
