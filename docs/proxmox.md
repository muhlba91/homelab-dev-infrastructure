# Proxmox VM for a dev host

The dev host is a VM on a site's Proxmox host, on the site LAN behind the site router (`vmbr10` in the router repo's
[Proxmox runbook](https://github.com/muhlba91/homelab-router-infrastructure/blob/main/docs/proxmox.md)). It is
created and installed exactly like a router VM, with two differences: one NIC (the LAN) and a second disk that holds
all state (`/data`) and survives every install.

## Variables

Set these in the Proxmox host's shell for the commands below (example values from the host file):

```bash
export DEV_VMID=110
export LAN_MAC=bc:24:11:00:00:01      # the host file's network.mac
```

## VM

| Setting | Value | Why |
| --- | --- | --- |
| `machine` | `q35` | PCIe chipset; the ICH9 watchdog (`iTCO_wdt`) is built in for the host file's `system.watchdog` |
| `bios` | `seabios` or `ovmf` | the `qemu` profile boots with either (OVMF: EFI disk with `pre-enrolled-keys=0`) |
| `cpu` | `host` | all host CPU features |
| `cores` / `memory` / `balloon` | `8` / `24576`-`32768` / `0` | 2-4 concurrent workspaces plus agents; no ballooning |
| `net0` | `virtio`, the host file's MAC, `vmbr10`, `queues` = 4 | the host renames its NIC by MAC |
| `scsihw` | `virtio-scsi-single` | one controller per disk, `iothread` per disk |
| `scsi0` (OS) | 64 GB, `iothread=1`, `discard=on`, `ssd=1` | wiped by every install (disko); the host file's `hardware.disk` is its stable path |
| `scsi1` (data) | 200-500 GB, `iothread=1`, `discard=on`, `ssd=1` | `/data`: homes, workspaces, Coder, PostgreSQL; never touched by an install |
| `agent` | `1` | the QEMU guest agent (clean shutdown, IP display) |

```bash
qm create "$DEV_VMID" --name <host> --machine q35 --cpu host --cores 8 --memory 32768 --balloon 0 \
  --agent 1 --onboot 1 --startup order=2 --scsihw virtio-scsi-single \
  --net0 "virtio=${LAN_MAC},bridge=vmbr10,queues=4" \
  --scsi0 local-lvm:64,iothread=1,discard=on,ssd=1 \
  --scsi1 local-lvm:300,iothread=1,discard=on,ssd=1
```

With two disks, `/dev/sda` and `/dev/sdb` are not stable: the host file names the OS disk by its stable path,
`/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0` (check it in the installer: `ls -l /dev/disk/by-id/`).

## First install

`./host install` (from `nix/` on the workstation) needs SSH to the installer on the site LAN: from a device in the
mesh (NetBird/Tailscale reach the site LANs) or through the Proxmox host as a jump host.

1. On the Proxmox host: the NixOS minimal ISO of the release in `nix/flake.nix`, boot order disk first (an empty disk
   falls through to the ISO):

   ```bash
   wget -P /var/lib/vz/template/iso https://channels.nixos.org/nixos-26.05/latest-nixos-minimal-x86_64-linux.iso
   qm set "$DEV_VMID" --ide2 local:iso/latest-nixos-minimal-x86_64-linux.iso,media=cdrom --boot order='scsi0;ide2'
   qm start "$DEV_VMID"
   ```

2. In the VM's console (user `nixos`; no paste, so short commands; the NIC is the one with the host file's MAC,
   `ip -br link`, usually `ens18`). **Format the data disk once**, on the first install only: it is never formatted
   by an install, and never automatically (a unit that formats "when no filesystem is found" can wipe the disk on a
   transient read error). `./host install` refuses to run without a disk labelled `data`, and refuses to wipe a disk
   that carries the label.

   ```bash
   passwd                       # temporary password, only for copying the key
   sudo -i
   ls -l /dev/disk/by-id/       # scsi0: the OS disk, scsi1: the data disk
   mkfs.ext4 -L data /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1   # FIRST INSTALL ONLY
   ip addr add <address>/<netmask> dev ens18 && ip route add default via <gateway>
   echo 'nameserver <gateway>' > /etc/resolv.conf
   systemctl start sshd
   ```

3. On the workstation (in `nix/`): copy the host's deploy key to `root` (asks for the temporary password), then
   install (wipes the OS disk, keeps the data disk, reboots into the host):

   ```bash
   ssh-keygen -y -f ../infrastructure/outputs/keys/<host>/deploy-key | ssh -o StrictHostKeyChecking=no \
     -o UserKnownHostsFile=/dev/null nixos@<address> 'sudo mkdir -p /root/.ssh && sudo tee /root/.ssh/authorized_keys'
   ./host install <host> <address>
   ```

4. On the Proxmox host: remove the ISO: `qm set "$DEV_VMID" --ide2 none --boot order=scsi0`.

5. Register the GitHub machine key and validate the host: [install.md](install.md), [validation.md](validation.md).

A **reinstall** is the same without the `mkfs` step: everything on `/data` (homes, workspaces, Coder's database) is
kept, the secrets are delivered again.
