# libvirt VM for a dev host

The dev host is a libvirt/KVM VM on a bare-metal NixOS router/hypervisor host, on the site LAN behind the site router.
For `hetzner-fra-dev-001` the site is `hetzner-fra-router-001`. The VM has one NIC (the LAN) and a second disk that
holds all state (`/data`) and survives every install.

## VM

The VM is defined by [libvirt/hetzner-fra-dev-001.yml](../libvirt/hetzner-fra-dev-001.yml):

| Setting | Value | Why |
| --- | --- | --- |
| vCPUs / memory | 8 / 16 GiB | 2-4 concurrent workspaces plus agents |
| `mac` | `bc:24:11:25:ab:8e` | the host renames its NIC by MAC; the host file's `network.mac` |
| disk 0 (`sda`, OS) | 64 GiB | wiped by every install (disko); the host file's `hardware.disk` is its stable path |
| disk 1 (`sdb`, `/data`) | 200 GiB | homes, workspaces, Coder, PostgreSQL; never touched by an install |
| `iso` | NixOS minimal 26.05, attached as a CD-ROM | the installer; remove it from the spec after the install |

The disks are zvols in the pool `guests` (`hetzner-fra-dev-001-disk0`, `hetzner-fra-dev-001-disk1`). The VM boots with
OVMF (UEFI, Secure Boot off); the `qemu` hardware profile boots with either firmware.

With two disks, `/dev/sda` and `/dev/sdb` are not stable in general: the host file names the OS disk by its stable
path, `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0` (the data disk is `...drive-scsi1`). Check it in the
installer with `ls -l /dev/disk/by-id/`.

Sizing: the OS disk holds only the Nix store (the system, up to `system.gc.keep` generations, builds during a deploy),
the journal and the secrets; everything else is on the data disk (homes, mise runtimes, Docker images and volumes,
caches, Coder and PostgreSQL). The data disk can grow later ([install.md](install.md#growing-the-data-disk)).

## Creating the VM

From a checkout of [homelab-router-infrastructure](https://github.com/muhlba91/homelab-router-infrastructure), in its
`nix/` folder, with the site data set up as for `./router deploy`:

```bash
# create missing disks, upload the installer image, define the VM, enable autostart and start it
./router libvirt-deploy hetzner-fra-router-001 <path to libvirt/hetzner-fra-dev-001.yml>

# print the domain XML without changing anything
./router libvirt-render <path to libvirt/hetzner-fra-dev-001.yml>
```

The deploy is idempotent and deletes nothing: run it again after a spec change. `./router virsh hetzner-fra-router-001
<args>` runs `virsh` on the host (from the same folder). The tool is documented in `docs/libvirt.md` of that repository.

## First install

`./host install` (from `nix/` on the workstation) needs SSH to the installer on the site LAN: from a device in the
mesh (NetBird/Tailscale reach the site LANs) or through the hypervisor host as a jump host.

1. Open the console. It is VNC on the hypervisor host's `127.0.0.1` only. Get the display number (the port is 5900
   plus the number) and tunnel it over SSH to the host (user `deploy`, reachable over the mesh):

   ```bash
   # prints the display, for example 127.0.0.1:0
   ./router virsh hetzner-fra-router-001 vncdisplay hetzner-fra-dev-001

   # forward it, then connect a VNC client to localhost:5900 (plus the display number)
   ssh -N -L 5900:127.0.0.1:<5900 + display number> deploy@<management address>
   ```

2. In the VM's console (user `nixos`; no paste, so short commands; the NIC is the one with the host file's MAC, `ip
   -br link`). **Format the data disk once**, on the first install only: it is never formatted by an install, and
   never automatically (a unit that formats "when no filesystem is found" can wipe the disk on a transient read
   error). `./host install` refuses to run without a disk labelled `data`, and refuses to wipe a disk that carries the
   label.

   ```bash
   passwd                       # temporary password, only for copying the key
   sudo -i
   ls -l /dev/disk/by-id/       # scsi0: the OS disk, scsi1: the data disk
   mkfs.ext4 -L data /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1   # FIRST INSTALL ONLY
   ip addr add <address>/<netmask> dev <nic> && ip route add default via <gateway>
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

4. Eject the installer image and remove `iso` from the spec, so that a later deploy does not attach it again:

   ```bash
   ./router virsh hetzner-fra-router-001 change-media hetzner-fra-dev-001 sdz --eject --live --config
   ```

5. Register the GitHub machine key and validate the host: [install.md](install.md), [validation.md](validation.md).

A reinstall skips the `mkfs` step: [install.md](install.md#reinstall).

## Growing a disk

Disks cannot shrink: start generous. Grow the data disk (`hetzner-fra-dev-001-disk1`), then reboot the VM: `/data` is
mounted with `autoResize`, so the filesystem grows at the mount ([install.md](install.md#growing-the-data-disk)).

```bash
# set the new size, for example 300G
./router virsh hetzner-fra-router-001 vol-resize --pool guests hetzner-fra-dev-001-disk1 <new size>
```

The OS disk (`hetzner-fra-dev-001-disk0`) is wiped by every install and grows the same way.
